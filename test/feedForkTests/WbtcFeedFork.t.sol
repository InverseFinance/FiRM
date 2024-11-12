// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/feeds/WbtcPriceFeed.sol";
import {IAggregator} from "src/feeds/WbtcPriceFeed.sol";
contract WbtcFeedFork is Test {
    WbtcPriceFeed feed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        feed = new WbtcPriceFeed();
    }

    // function test_latestRoundData_NominalCaseWithinBounds() public view {
    //     {
    //         (
    //             uint80 clRoundId1,
    //             int256 btcToUsdPrice,
    //             uint clStartedAt1,
    //             uint clUpdatedAt1,
    //             uint80 clAnsweredInRound1
    //         ) = feed.btcToUsd().latestRoundData();

    //         (
    //             uint80 clRoundId2,
    //             int256 wbtcToBtcPrice,
    //             uint clStartedAt2,
    //             uint clUpdatedAt2,
    //             uint80 clAnsweredInRound2
    //         ) = feed.wbtcToBtc().latestRoundData();

    //         (
    //             uint80 roundId,
    //             int256 wbtcUsdPrice,
    //             uint startedAt,
    //             uint updatedAt,
    //             uint80 answeredInRound
    //         ) = feed.latestRoundData();

    //         if (clUpdatedAt1 < clUpdatedAt2) {
    //             assertEq(clRoundId1, roundId);
    //             assertEq(clStartedAt1, startedAt);
    //             assertEq(clUpdatedAt1, updatedAt);
    //             assertEq(clAnsweredInRound1, answeredInRound);
    //         } else {
    //             assertEq(clRoundId2, roundId);
    //             assertEq(clStartedAt2, startedAt);
    //             assertEq(clUpdatedAt2, updatedAt);
    //             assertEq(clAnsweredInRound2, answeredInRound);
    //         }

    //         assertGt(wbtcUsdPrice, 10 ** 8);
    //         assertEq((btcToUsdPrice * 10 ** 8) / wbtcToBtcPrice, wbtcUsdPrice);
    //         if (wbtcToBtcPrice > 10 ** 8) assertGt(btcToUsdPrice, wbtcUsdPrice);
    //         if (wbtcToBtcPrice < 10 ** 8) assertGt(wbtcUsdPrice, btcToUsdPrice);
    //     }
    // }

    function test_latestRoundData_WillReturnFallbackWhenOutOfMaxBounds()
        public
    {
        (
            uint80 clRoundId1,
            int256 btcToUsdPrice,
            uint clStartedAt1,
            uint clUpdatedAt1,
            uint80 clAnsweredInRound1
        ) = feed.btcToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 wbtcToBtcPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = feed.wbtcToBtc().latestRoundData();
        vm.mockCall(
            address(feed.wbtcToBtc()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId2,
                IAggregator(feed.wbtcToBtc().aggregator()).maxAnswer(),
                clStartedAt2,
                clUpdatedAt2,
                clAnsweredInRound2
            )
        );
        (
            uint80 roundId,
            int256 wbtcUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        if (clUpdatedAt1 < clUpdatedAt2) {
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
        assertLt(
            wbtcUsdPrice,
            (feed.btcToUsd().latestAnswer() * 110) / 100,
            "Fallback price more than 10% higher than oracle"
        );
        assertGt(
            wbtcUsdPrice,
            (feed.btcToUsd().latestAnswer() * 90) / 100,
            "Wbtc more than 10% lower than oracle"
        );
        assertEq(
            feed.wbtcToUsdFallbackOracle(),
            wbtcUsdPrice,
            "Did not return fallback price"
        );
    }

    function test_latestRoundData_WillReturnFallbackWhenOutOfMinBounds()
        public
    {
        (
            uint80 clRoundId1,
            int256 btcToUsdPrice,
            uint clStartedAt1,
            uint clUpdatedAt1,
            uint80 clAnsweredInRound1
        ) = feed.btcToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 wbtcToBtcPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = feed.wbtcToBtc().latestRoundData();
        vm.mockCall(
            address(feed.wbtcToBtc()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId2,
                IAggregator(feed.wbtcToBtc().aggregator()).minAnswer(),
                clStartedAt2,
                clUpdatedAt2,
                clAnsweredInRound2
            )
        );
        (
            uint80 roundId,
            int256 wbtcUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        if (clUpdatedAt1 < clUpdatedAt2) {
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

        assertLt(
            wbtcUsdPrice,
            (feed.btcToUsd().latestAnswer() * 110) / 100,
            "Fallback price more than 10% higher than oracle"
        );
        assertGt(
            wbtcUsdPrice,
            (feed.btcToUsd().latestAnswer() * 90) / 100,
            "Wbtc more than 10% lower than oracle"
        );
        assertEq(
            feed.wbtcToUsdFallbackOracle(),
            wbtcUsdPrice,
            "Did not return fallback price"
        );
    }

    function test_latestAnswer_ReturnSameAsLatestRoundData() public {
        (, int btcLRD, , , ) = feed.wbtcToBtc().latestRoundData();
        int btcLA = feed.wbtcToBtc().latestAnswer();

        assertEq(btcLRD, btcLA);
    }
}
