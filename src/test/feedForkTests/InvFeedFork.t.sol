// SPDX-License-Identifier: UNLICENSED 
pragma solidity ^0.8.19; 

import "forge-std/Test.sol"; 
import "src/feeds/InvPriceFeed.sol"; 

interface ICurvePool2 {
    function fee() external view returns (uint256);
}

contract InvFeedFork is Test {

    InvPriceFeed feed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        feed = new InvPriceFeed();
    }

    function test_decimals() public {
       assertEq(feed.decimals(), 18);
    
    }

    function test_latestRoundData() public {
        (uint80 clRoundId, int256 clInvUsdPrice, uint clStartedAt, uint clUpdatedAt, uint80 clAnsweredInRound) = feed.usdcToUsd().latestRoundData();
        (uint80 roundId, int256 invUsdPrice, uint startedAt, uint updatedAt, uint80 answeredInRound) = feed.latestRoundData();
        assertEq(roundId, clRoundId);
        assertEq(startedAt, clStartedAt);
        assertEq(updatedAt, clUpdatedAt);
        assertEq(answeredInRound, clAnsweredInRound);
    }
}
