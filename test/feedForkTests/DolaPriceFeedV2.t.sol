// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkCurveFeed.sol";
import "forge-std/console.sol";

contract DolaPriceFeedV2Test is Test {
    ChainlinkCurveFeed feed;
    address dolasUSDS = address(0x8b83c4aA949254895507D09365229BC3a8c7f710);
    address baseDAItoUsdAddr =
        address(0x070287A072cf7Ead994F5b91d75FBdf92A5eAFB7);
    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21293718);
        feed = new ChainlinkCurveFeed(baseDAItoUsdAddr, dolasUSDS, 0, 0);
    }

    function test_decimals() public {
        assertEq(feed.decimals(), 18);
    }

    function test_description() public {
        string memory expected = "DOLA / USD";
        assertEq(feed.description(), expected);
    }

    function test_latestRoundData() public {
        (
            uint80 roundId,
            int256 dolaUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        (
            uint80 clRoundId,
            int256 clDAIToUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = IChainlinkBasePriceFeed(feed.assetToUsd()).latestRoundData();

        uint256 usdsDolaPrice = feed.curvePool().price_oracle(0);
        uint256 estDolaUsdPrice = (uint(clDAIToUsdPrice) * 1e18) /
            usdsDolaPrice;
        assertEq(roundId, clRoundId);
        assertEq(uint(dolaUsdPrice), estDolaUsdPrice);
        assertEq(startedAt, clStartedAt);
        assertEq(updatedAt, clUpdatedAt);
        assertEq(answeredInRound, clAnsweredInRound);
        console.log(uint(dolaUsdPrice));
    }
}
