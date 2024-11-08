pragma solidity ^0.8.20;

interface IChainlinkFeed {
    function aggregator() external view returns (address aggregator);
    function decimals() external view returns (uint8 decimals);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 crvUsdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
    function latestAnswer() external view returns (int256 price);
}
interface IAggregator {
    function maxAnswer() external view returns (int192);
    function minAnswer() external view returns (int192);
}
interface ICurvePool {
    function price_oracle(uint k) external view returns (uint256);
}

contract WbtcPriceFeed {
    IChainlinkFeed public btcToUsd =
        IChainlinkFeed(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
    IChainlinkFeed public wbtcToBtc =
        IChainlinkFeed(0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23);
    IChainlinkFeed public usdtToEth =
        IChainlinkFeed(0xEe9F2375b4bdF6387aa8265dD4FB8F16512A1d46);
    IChainlinkFeed public ethToUsd =
        IChainlinkFeed(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    ICurvePool public tricrypto =
        ICurvePool(0xf5f5B97624542D72A9E06f04804Bf81baA15e2B4);

    function decimals() external view returns (uint8) {
        return 8;
    }

    /**
     * @notice Retrieves the latest round data for the wBTC token price feed
     * @dev This function calculates the wBTC price in USD by combining the BTC to USD price from a Chainlink oracle and the wBTC to BTC ratio from another Chainlink oracle
     * @return roundId The round ID of the Chainlink price feed for the feed with the lowest updatedAt feed
     * @return wbtcUsdPrice The latest wBTC price in USD computed from the Wbtc/BTC and BTC/USD feeds
     * @return startedAt The timestamp when the latest round of Chainlink price feed started of the lowest last updatedAt feed
     * @return updatedAt The lowest timestamp when either of the latest round of Chainlink price feed was updated
     * @return answeredInRound The round ID in which the answer was computed of the lowest updatedAt feed
     */
    function latestRoundData()
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (
            uint80 wbtcBtcRoundId,
            int256 wbtcBtcPrice,
            uint wbtcBtcStartedAt,
            uint wbtcBtcUpdatedAt,
            uint80 wbtcBtcAnsweredInRound
        ) = wbtcToBtc.latestRoundData();
        (
            uint80 btcUsdRoundId,
            int256 btcUsdPrice,
            uint btcUsdStartedAt,
            uint btcUsdUpdatedAt,
            uint80 btcUsdAnsweredInRound
        ) = btcToUsd.latestRoundData();
        int wbtcUsdPrice = (btcUsdPrice * 10 ** 8) / wbtcBtcPrice;
        if (isPriceOutOfBounds(wbtcBtcPrice, wbtcToBtc)) {
            wbtcUsdPrice = wbtcToUsdFallbackOracle();
        }
        if (wbtcBtcUpdatedAt < btcUsdUpdatedAt) {
            return (
                wbtcBtcRoundId,
                wbtcUsdPrice,
                wbtcBtcStartedAt,
                wbtcBtcUpdatedAt,
                wbtcBtcAnsweredInRound
            );
        } else {
            return (
                btcUsdRoundId,
                wbtcUsdPrice,
                btcUsdStartedAt,
                btcUsdUpdatedAt,
                btcUsdAnsweredInRound
            );
        }
    }
    /**
     * @notice Returns the latest price only
     * @dev Unlike chainlink oracles, the latestAnswer will always be the same as in the latestRoundData
     * @return int256 Returns the last finalized price of the chainlink oracle
     */
    function latestAnswer() external view returns (int256) {
        (, int256 latestPrice, , , ) = latestRoundData();
        return latestPrice;
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
     * @notice Fetches the WBTC to USDT price and adjusts the decimals to match Chainlink oracles.
     * @dev The function assumes that the `price_oracle` returns the price with 18 decimals, and it adjusts to 8 decimals for compatibility with Chainlink oracles.
     * @return int Returns the WBTC price in USD format with reduced decimals.
     */
    function wbtcToUsdFallbackOracle() public view returns (int) {
        //0 index is wbtc usdt price
        //Reduce to 8 decimals to be in line with chainlink oracles
        int crvWbtcToUsdt = int(tricrypto.price_oracle(0));
        (, int usdtEth, , , ) = usdtToEth.latestRoundData();
        (, int ethUsd, , , ) = ethToUsd.latestRoundData();
        int usdtToUsd = (usdtEth * ethUsd) / 10 ** 18;
        return (crvWbtcToUsdt * usdtToUsd) / 10 ** 18;
    }
}
