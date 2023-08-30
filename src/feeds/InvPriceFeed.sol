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
    ICurvePool public constant tricrypto =
        ICurvePool(0x5426178799ee0a0181A89b4f57eFddfAb49941Ec);

    IChainlinkFeed public constant usdcToUsd =
        IChainlinkFeed(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    IChainlinkFeed public constant ethToUsd =
        IChainlinkFeed(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    uint256 public constant ethK = 0;
    uint256 public constant invK = 1;

    /**
     * @notice Retrieves the latest round data for the INV token price feed
     * @dev This function calculates the INV price in USD by combining the USDC to USD price from a Chainlink oracle and the INV to USDC ratio from the tricrypto pool
     * @return roundId The round ID of the Chainlink price feed
     * @return usdcUsdPrice The latest USDC price in USD computed from the INV/USDC and USDC/USD feeds
     * @return startedAt The timestamp when the latest round of Chainlink price feed started
     * @return updatedAt The timestamp when the latest round of Chainlink price feed was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        external
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
        int256 invDollarPrice = int256(tricrypto.price_oracle(invK));

        invDollarPrice =
            (invDollarPrice * usdcUsdPrice * int(10 ** 10)) /
            int(10 ** decimals());

        return (roundId, invDollarPrice, startedAt, updatedAt, answeredInRound);
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
     * @return roundId The round ID of the Chainlink price feed
     * @return usdcToUsdPrice The latest USDC price in USD computed from the ETH/USD and ETH/USDC feeds
     * @return startedAt The timestamp when the latest round of Chainlink price feed started
     * @return updatedAt The timestamp when the latest round of Chainlink price feed was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function usdcToUsdFallbackOracle()
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        int crvEthToUsdc = int(tricrypto.price_oracle(ethK));

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
