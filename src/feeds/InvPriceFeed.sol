// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IChainlinkFeed {
    function aggregator() external view returns (address aggregator);

    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 invDollarPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface IAggregator {
    function maxAnswer() external view returns (int192);

    function minAnswer() external view returns (int192);
}

interface ICurvePool {
    function price_oracle(uint256 k) external view returns (uint256);
}

contract InvPriceFeed {
    error OnlyGov();

    ICurvePool public constant tricryptoETH =
        ICurvePool(0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B);

    ICurvePool public constant tricryptoINV =
        ICurvePool(0x5426178799ee0a0181A89b4f57eFddfAb49941Ec);

    IChainlinkFeed public constant usdcToUsd =
        IChainlinkFeed(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    IChainlinkFeed public constant ethToUsd =
        IChainlinkFeed(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    uint256 public constant ethK = 1;
    uint256 public constant invK = 1;

    uint256 public ethHeartbeat = 1 hours;
    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    modifier onlyGov() {
        if (msg.sender != gov) revert OnlyGov();
        _;
    }

    /**
     * @notice Retrieves the latest round data for the INV token price feed
     * @dev This function calculates the INV price in USD by combining the USDC to USD price from a Chainlink oracle
     * and the INV to USDC ratio from the tricrypto pool.
     * If USDC/USD price is out of bounds, it will fallback to ETH/USD price oracle and USDC to ETH ratio from the tricrypto pool
     * @return roundId The round ID of the Chainlink price feed
     * @return usdcUsdPrice The latest USDC price in USD computed from the INV/USDC and USDC/USD feeds
     * @return startedAt The timestamp when the latest round of Chainlink price feed started
     * @return updatedAt The timestamp when the latest round of Chainlink price feed was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (
            uint80 roundId,
            int256 usdcUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = usdcToUsd.latestRoundData();

        if (isPriceOutOfBounds(usdcUsdPrice, usdcToUsd)) {
            (
                roundId,
                usdcUsdPrice,
                startedAt,
                updatedAt,
                answeredInRound
            ) = usdcToUsdFallbackOracle();
        }
        int256 invUsdcPrice = int256(tricryptoINV.price_oracle(invK));

        int256 invDollarPrice = (invUsdcPrice * usdcUsdPrice) /
            int(10 ** (decimals() - 10));

        return (roundId, invDollarPrice, startedAt, updatedAt, answeredInRound);
    }

    /** 
    @notice Retrieves the latest price for the INV token
    @return price The latest price for the INV token
    */
    function latestAnswer() external view returns (int256) {
        (, int256 price, , , ) = latestRoundData();
        return price;
    }

    /**
     * @notice Retrieves number of decimals for the INV price feed
     * @return decimals The number of decimals for the INV price feed
     */
    function decimals() public pure returns (uint8) {
        return 18;
    }

    /**
     * @notice Checks if a given price is out of the boundaries defined in the Chainlink aggregator.
     * @param price The price to be checked.
     * @param feed The Chainlink feed to retrieve the boundary information from.
     * @return bool Returns `true` if the price is out of bounds, otherwise `false`.
     */
    function isPriceOutOfBounds(
        int price,
        IChainlinkFeed feed
    ) public view returns (bool) {
        IAggregator aggregator = IAggregator(feed.aggregator());
        int192 max = aggregator.maxAnswer();
        int192 min = aggregator.minAnswer();
        return (max <= price || min >= price);
    }

    /**
     * @notice Fetches the ETH to USD price and the ETH to USDC to get USDC/USD price, adjusts the decimals to match Chainlink oracles.
     * @dev The function assumes that the `price_oracle` returns the price with 18 decimals, and it adjusts to 8 decimals for compatibility with Chainlink oracles.
     * @return roundId The round ID of the ETH/USD Chainlink price feed
     * @return usdcToUsdPrice The latest USDC price in USD computed from the ETH/USD and ETH/USDC feeds
     * @return startedAt The timestamp when the latest round of ETH/USD Chainlink price feed started
     * @return updatedAt The timestamp when the latest round of ETH/USD Chainlink price feed was updated
     * @return answeredInRound The round ID of the ETH/USD Chainlink price feed in which the answer was computed
     */
    function usdcToUsdFallbackOracle()
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        int crvEthToUsdc = int(tricryptoETH.price_oracle(ethK));

        (
            uint80 roundId,
            int256 ethToUsdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = ethToUsd.latestRoundData();

        int256 usdcToUsdPrice = (ethToUsdPrice * 10 ** 18) / crvEthToUsdc;

        if (
            isPriceOutOfBounds(ethToUsdPrice, ethToUsd) ||
            block.timestamp - updatedAt > ethHeartbeat
        ) {
            // Will force stale price on borrow controller
            updatedAt = 0;
        }

        return (roundId, usdcToUsdPrice, startedAt, updatedAt, answeredInRound);
    }

    /**
     * @notice Sets a new ETH heartbeat
     * @dev Can only be called by the current gov address
     * @param newHeartbeat The new ETH heartbeat
     */
    function setEthHeartbeat(uint256 newHeartbeat) external onlyGov {
        ethHeartbeat = newHeartbeat;
    }

    /**
     * @notice Sets a new gov address
     * @dev Can only be called by the current gov address
     * @param newGov The new gov address
     */
    function setGov(address newGov) external onlyGov {
        gov = newGov;
    }
}
