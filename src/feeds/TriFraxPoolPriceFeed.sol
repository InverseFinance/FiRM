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
            int256 lpDollarPrice,
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

    function get_virtual_price() external view returns (uint256);
}

contract TriFraxPoolPriceFeed {
    ICurvePool public constant tricryptoINV =
        ICurvePool(0x5426178799ee0a0181A89b4f57eFddfAb49941Ec);

    ICurvePool public constant tricryptoFRAX =
        ICurvePool(0xE57180685E3348589E9521aa53Af0BCD497E884d);

    IChainlinkFeed public constant usdcToUsd =
        IChainlinkFeed(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    IChainlinkFeed public constant ethToUsd =
        IChainlinkFeed(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    IChainlinkFeed public constant fraxToUsd =
        IChainlinkFeed(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);

    uint256 public constant ethK = 0;

    uint256 public constant fraxHeartbeat = 1 hours;

    /**
     * @notice Retrieves the latest round data for the LP token price feed
     * @dev This function calculates the LP token price in USD using the lowest usd price for FRAX and USDC from a Chainlink oracle
     * and the virtual price from the DOLA-FRAX-USDC tricrypto pool.
     * If USDC/USD price is out of bounds, it will fallback to ETH/USD price oracle and USDC to ETH ratio from the tricrypto pool
     * @return roundId The round ID of the Chainlink price feed
     * @return lpUsdPrice The latest LP token price in USD computed from the virtual price and USDC/USD or FRAX/USD feed
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

        (
            uint80 roundIdFrax,
            int256 fraxUsdPrice,
            uint startedAtFrax,
            uint updatedAtFrax,
            uint80 answeredInRoundFrax
        ) = fraxToUsd.latestRoundData();

        // TODO: add FRAX to USD fallback oracle? from which pool/oracle?

        int256 minUsdPrice;

        // If FRAX price is lower than USDC price and the FRAX price is not stale, use FRAX price
        if (
            fraxUsdPrice < usdcUsdPrice &&
            block.timestamp - updatedAtFrax <= fraxHeartbeat
        ) {
            minUsdPrice = fraxUsdPrice;
            roundId = roundIdFrax;
            startedAt = startedAtFrax;
            updatedAt = updatedAtFrax;
            answeredInRound = answeredInRoundFrax;
        } else {
            minUsdPrice = usdcUsdPrice;
        }

        return (
            roundId,
            (int(tricryptoFRAX.get_virtual_price()) * minUsdPrice) / 10 ** 8,
            startedAt,
            updatedAt,
            answeredInRound
        );
    }

    /** 
    @notice Retrieves the latest price for the LP token
    @return price The latest price for the LP token
    */
    function latestAnswer() external view returns (int256) {
        (, int256 price, , , ) = latestRoundData();
        return price;
    }

    /**
     * @notice Retrieves number of decimals for the LP token price feed
     * @return decimals The number of decimals for the LP token price feed
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
        int crvEthToUsdc = int(tricryptoINV.price_oracle(ethK));

        (
            uint80 roundId,
            int256 ethToUsdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = ethToUsd.latestRoundData();

        int256 usdcToUsdPrice = (crvEthToUsdc * 10 ** 8) /
            ethToUsdPrice /
            10 ** 10;

        return (roundId, usdcToUsdPrice, startedAt, updatedAt, answeredInRound);
    }
}
