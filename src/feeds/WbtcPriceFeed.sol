pragma solidity ^0.8.13;

interface IChainlinkFeed {
    function decimals() external view returns (uint8 decimals);
    function latestRoundData() external view returns (uint80 roundId, int256 crvUsdPrice, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

contract WbtcPriceFeed is IChainlinkFeed {
    
    IChainlinkFeed public btcToUsd = IChainlinkFeed(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
    IChainlinkFeed public wbtcToBtc = IChainlinkFeed(0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23);

    function decimals() external view returns (uint8){
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
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80){
        (uint80 wbtcBtcRoundId,int256 wbtcBtcPrice,uint wbtcBtcStartedAt,uint wbtcBtcUpdatedAt,uint80 wbtcBtcAnsweredInRound) = wbtcToBtc.latestRoundData();
        (uint80 btcUsdRoundId,int256 btcUsdPrice,uint btcUsdStartedAt,uint btcUsdUpdatedAt,uint80 btcUsdAnsweredInRound) = btcToUsd.latestRoundData();
        int wbtcUsdPrice = btcUsdPrice * 10**8 / wbtcBtcPrice;
        if(wbtcBtcUpdatedAt < btcUsdUpdatedAt){
            return (wbtcBtcRoundId, wbtcUsdPrice, wbtcBtcStartedAt, wbtcBtcUpdatedAt, wbtcBtcAnsweredInRound);
        } else {
            return (btcUsdRoundId, wbtcUsdPrice, btcUsdStartedAt, btcUsdUpdatedAt, btcUsdAnsweredInRound);
        }
    }
}
