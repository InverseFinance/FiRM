// SPDX-License-Identifier: UNLICENSED 
pragma solidity ^0.8.13; 
 
import "forge-std/Test.sol"; 
import "../../feeds/WbtcPriceFeed.sol"; 

contract WbtcFeedFork is Test {

    WbtcPriceFeed feed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        feed = new WbtcPriceFeed();
    }

    function testNominalCaseWithinBounds() public {
        (uint80 clRoundId1, int256 btcToUsdPrice, uint clStartedAt1, uint clUpdatedAt1,  uint80 clAnsweredInRound1) = feed.btcToUsd().latestRoundData();
        (uint80 clRoundId2, int256 wbtcToBtcPrice, uint clStartedAt2, uint clUpdatedAt2,  uint80 clAnsweredInRound2) = feed.wbtcToBtc().latestRoundData();
        (uint80 roundId, int256 wbtcUsdPrice, uint startedAt, uint updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        if(clUpdatedAt1 < clUpdatedAt2){
            assertEq(clRoundId1, roundId);
            assertEq(clStartedAt1, startedAt);
            assertEq(clUpdatedAt1, updatedAt);
            assertEq(clAnsweredInRound1, answeredInRound);
        } else {
            assertEq(clRoundId2, roundId);
            assertEq(clStartedAt2, startedAt);
            assertEq(clUpdatedAt2, updatedAt);
            assertEq(clAnsweredInRound2, answeredInRound);
        }
        
        assertGt(wbtcUsdPrice, 10**8); 
        assertEq(btcToUsdPrice * 10**8 / wbtcToBtcPrice, wbtcUsdPrice);
        if(wbtcToBtcPrice > 10**8) assertGt(btcToUsdPrice, wbtcUsdPrice);
        if(wbtcToBtcPrice < 10**8) assertGt(wbtcUsdPrice, btcToUsdPrice);
    }
}

