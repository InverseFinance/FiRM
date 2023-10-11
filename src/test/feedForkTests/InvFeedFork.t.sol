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

        uint256 invUSDCPrice = feed.tricryptoINV().price_oracle(1);
        uint256 estimatedInvUSDPrice = (invUSDCPrice *
            uint256(clUsdcToUsdPrice) *
            10 ** 10) / 10 ** 18;

        assertEq(uint256(invUsdPrice), estimatedInvUSDPrice);
        assertEq(uint256(invUsdPrice), uint(feed.latestAnswer()));
    }

    function testWillReturnFallbackWhenOutOfMaxBounds() public {
        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();

        _mockChainlinkPrice(feed.usdcToUsd(), 10 ** 12);

        (
            uint80 roundId,
            int256 invUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);

        uint256 invUSDCPrice = feed.tricryptoINV().price_oracle(1);
        (, int256 usdcFallback, , , ) = feed.usdcToUsdFallbackOracle();

        uint256 estimatedInvUSDPrice = (invUSDCPrice *
            uint256(usdcFallback) *
            10 ** 10) / 10 ** 18;

        assertEq(uint256(invUsdPrice), estimatedInvUSDPrice);
        assertEq(uint256(invUsdPrice), uint(feed.latestAnswer()));
    }

    function testWillReturnFallbackWhenOutOfMinBounds() public {
        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();

        _mockChainlinkPrice(feed.usdcToUsd(), 10);

        (
            uint80 roundId,
            int256 invUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);

        uint256 invUSDCPrice = feed.tricryptoINV().price_oracle(1);
        (, int256 usdcFallback, , , ) = feed.usdcToUsdFallbackOracle();

        uint256 estimatedInvUSDPrice = (invUSDCPrice *
            uint256(usdcFallback) *
            10 ** 10) / 10 ** 18;

        assertEq(uint256(invUsdPrice), estimatedInvUSDPrice);
        assertEq(uint256(invUsdPrice), uint(feed.latestAnswer()));
    }

    function test_StaleETH_WillReturnFallbackWhenOutOfMinBoundsUSDC() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();

        _mockChainlinkPrice(feed.usdcToUsd(), 10);
        _mockChainlinkUpdatedAt(feed.ethToUsd(), -1*int(feed.ethHeartbeat()));

        (
            uint80 roundId,
            int256 invUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if stale price return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        uint256 invUSDCPrice = feed.tricryptoINV().price_oracle(1);
        (, int256 usdcFallback, , , ) = feed.usdcToUsdFallbackOracle();

        uint256 estimatedInvUSDPrice = (invUSDCPrice *
            uint256(usdcFallback) *
            10 ** 10) / 10 ** 18;

        assertEq(uint256(invUsdPrice), estimatedInvUSDPrice);
        assertEq(uint256(invUsdPrice), uint(feed.latestAnswer()));
    }

    function test_OutOfMinBoundsETH_WillReturnFallbackWhenOutOfMinBoundsUSDC() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();

        _mockChainlinkPrice(feed.usdcToUsd(), 10);
        _mockChainlinkPrice(feed.ethToUsd(), 1);

        (
            uint80 roundId,
            int256 invUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
       
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if out of bounds return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        uint256 invUSDCPrice = feed.tricryptoINV().price_oracle(1);
        (, int256 usdcFallback, , , ) = feed.usdcToUsdFallbackOracle();

        uint256 estimatedInvUSDPrice = (invUSDCPrice *
            uint256(usdcFallback) *
            10 ** 10) / 10 ** 18;

        assertEq(uint256(invUsdPrice), estimatedInvUSDPrice);
        assertEq(uint256(invUsdPrice), uint(feed.latestAnswer()));
    }

    function test_revert_withOutOfMaxBoundsETH_fallbackWhenOutOfMinBoundsUSDC() public {
        _mockChainlinkPrice(feed.usdcToUsd(), 10);
        _mockChainlinkPrice(feed.ethToUsd(), IAggregator(feed.ethToUsd().aggregator()).maxAnswer()+1);

        // if ETH price > maxAnswer (95780971304118053647396689196894323976171195136475135) will revert
        vm.expectRevert(stdError.arithmeticError);
        feed.latestRoundData();
    }

    function test_compare_oracle() public {
        (
            ,
            int256 invUsdPrice,
            ,
            ,
        ) = feed.latestRoundData();
        assertEq(uint256(invUsdPrice), uint(feed.latestAnswer()));

        _mockChainlinkPrice(feed.usdcToUsd(), 10);

        (, int256 invUsdPriceFallback, , , ) = feed.latestRoundData();
        assertEq(uint256(invUsdPriceFallback), uint(feed.latestAnswer()));

        assertApproxEqAbs(
            uint256(invUsdPrice),
            uint256(invUsdPriceFallback),
            0.5 ether
        ); // 0.5 dollar
    }

    function test_setEthHeartbeat() public {
        assertEq(feed.ethHeartbeat(), 3600);

        vm.expectRevert(InvPriceFeed.OnlyGov.selector);
        feed.setEthHeartbeat(100);
        assertEq(feed.ethHeartbeat(), 3600);

        vm.prank(feed.gov());
        feed.setEthHeartbeat(100);
        assertEq(feed.ethHeartbeat(), 100);
    } 

    function test_setGov() public {
        assertEq(feed.gov(), 0x926dF14a23BE491164dCF93f4c468A50ef659D5B);

        vm.expectRevert(InvPriceFeed.OnlyGov.selector);
        feed.setGov(address(this));
        assertEq(feed.gov(), 0x926dF14a23BE491164dCF93f4c468A50ef659D5B);

        vm.prank(feed.gov());
        feed.setGov(address(this));
        assertEq(feed.gov(), address(this));
    }

    function _mockChainlinkPrice(IChainlinkFeed clFeed, int mockPrice) internal {
        (
            uint80 roundId,
            ,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = clFeed.latestRoundData();
         vm.mockCall(
            address(clFeed),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                roundId,
                mockPrice,
                startedAt,
                updatedAt,
                answeredInRound
            )
        );   
    }

    function _mockChainlinkUpdatedAt(IChainlinkFeed clFeed, int updatedAtDelta) internal {
        (
            uint80 roundId,
            int price,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = clFeed.latestRoundData();
         vm.mockCall(
            address(clFeed),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                roundId,
                price,
                startedAt,
                uint(int(updatedAt) + updatedAtDelta),
                answeredInRound
            )
        );   
    }
}
