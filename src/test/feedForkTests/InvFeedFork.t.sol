// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/InvPriceFeed.sol";
import "forge-std/console.sol";

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
        (
            uint80 clRoundId,
            int256 clUsdcToUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.usdcToUsd().latestRoundData();
        (
            uint80 roundId,
            int256 invUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        assertEq(roundId, clRoundId);
        assertEq(startedAt, clStartedAt);
        assertEq(updatedAt, clUpdatedAt);
        assertEq(answeredInRound, clAnsweredInRound);

        uint256 invUSDCPrice = feed.tricrypto().price_oracle(1);
        uint256 estimatedInvUSDPrice = (invUSDCPrice *
            uint256(clUsdcToUsdPrice) *
            10 ** 10) / 10 ** 18;

        assertEq(uint256(invUsdPrice), estimatedInvUSDPrice);
        assertEq(uint256(invUsdPrice), feed.latestAnswer());
    }

    function testWillReturnFallbackWhenOutOfMaxBounds() public {
        (
            uint80 clRoundId,
            int256 usdcToUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.usdcToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 ethToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = feed.ethToUsd().latestRoundData();
        vm.mockCall(
            address(feed.usdcToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                10 ** 12,
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
        );
        (
            uint80 roundId,
            int256 invUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 invUSDCPrice = feed.tricrypto().price_oracle(1);
        (, int256 usdcFallback, , , ) = feed.usdcToUsdFallbackOracle();

        uint256 estimatedInvUSDPrice = (invUSDCPrice *
            uint256(usdcFallback) *
            10 ** 10) / 10 ** 18;

        assertEq(uint256(invUsdPrice), estimatedInvUSDPrice);
        assertEq(uint256(invUsdPrice), feed.latestAnswer());
    }

    function testWillReturnFallbackWhenOutOfMinBounds() public {
        (
            uint80 clRoundId,
            int256 usdcToUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.usdcToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 ethToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = feed.ethToUsd().latestRoundData();
        vm.mockCall(
            address(feed.usdcToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                10,
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
        );
        (
            uint80 roundId,
            int256 invUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 invUSDCPrice = feed.tricrypto().price_oracle(1);
        (, int256 usdcFallback, , , ) = feed.usdcToUsdFallbackOracle();

        uint256 estimatedInvUSDPrice = (invUSDCPrice *
            uint256(usdcFallback) *
            10 ** 10) / 10 ** 18;

        assertEq(uint256(invUsdPrice), estimatedInvUSDPrice);
        assertEq(uint256(invUsdPrice), feed.latestAnswer());
    }

    function test_compare_oracle() public {
        (
            ,
            int256 invUsdPrice,
            ,
            ,
        ) = feed.latestRoundData();
        assertEq(uint256(invUsdPrice), feed.latestAnswer());

        vm.mockCall(
            address(feed.usdcToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 10, 0, 0, 0)
        );
        (, int256 invUsdPriceFallback, , , ) = feed.latestRoundData();
        assertEq(uint256(invUsdPriceFallback), feed.latestAnswer());

        assertApproxEqAbs(
            uint256(invUsdPrice),
            uint256(invUsdPriceFallback),
            0.5 ether
        ); // 0.5 dollar
    }
}
