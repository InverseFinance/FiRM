// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {SFraxPriceFeed, IAggregator, IChainlinkFeed} from "src/feeds/SFraxPriceFeed.sol";
import "forge-std/console.sol";


contract WstETHFeedFork is Test {
    SFraxPriceFeed feed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 18535539);

        feed = new SFraxPriceFeed();
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
        ) = feed.fraxToUsd().latestRoundData();
        (
            uint80 roundId,
            int256 wstEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(roundId, clRoundId);
        assertEq(startedAt, clStartedAt);
        assertEq(updatedAt, clUpdatedAt);
        assertEq(answeredInRound, clAnsweredInRound);

        uint256 wstEthTostEthRatio = feed.sFrax().convertToAssets(1 ether);
        uint256 estimatedwstEthUSDPrice = uint(clUsdcToUsdPrice) * wstEthTostEthRatio / 10 **8;

        assertEq(uint256(wstEthUsdPrice), estimatedwstEthUSDPrice);
        assertEq(uint256(wstEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_WillReturnFallbackWhenOutOfMaxBounds() public {
        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();

        _mockChainlinkPrice(feed.fraxToUsd(),type(int192).max);

        (
            uint80 roundId,
            int256 wstEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 stEthFallback, , , ) = feed.fraxToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.sFrax().convertToAssets(1 ether) *
            uint256(stEthFallback) / 10 ** 8;

        assertEq(uint256(wstEthUsdPrice), estimatedWstEthUSDPrice);
        assertEq(uint256(wstEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_WillReturnFallbackWhenOutOfMinBounds() public {
          (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();

        _mockChainlinkPrice(feed.fraxToUsd(),1);

        (
            uint80 roundId,
            int256 wstEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 stEthFallback, , , ) = feed.fraxToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.sFrax().convertToAssets(1 ether) *
            uint256(stEthFallback) / 10 ** 8;

        assertEq(uint256(wstEthUsdPrice), estimatedWstEthUSDPrice);
        assertEq(uint256(wstEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_StaleEthToUsd_WillReturnFallbackWhenOutOfMinBoundsStETH() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();

        _mockChainlinkPrice(feed.fraxToUsd(),1);
        _mockChainlinkUpdatedAt(feed.ethToUsd(), -1*int(feed.ethHeartbeat()));

        (
            uint80 roundId,
            int256 wstEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if stale price return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 stEthFallback, , , ) = feed.fraxToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.sFrax().convertToAssets(1 ether) *
            uint256(stEthFallback) / 10 ** 8;

        assertEq(uint256(wstEthUsdPrice), estimatedWstEthUSDPrice);
        assertEq(uint256(wstEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_StaleFraxToEth_WillReturnFallbackWhenOutOfMinBoundsStETH() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();

        _mockChainlinkPrice(feed.fraxToUsd(),1);
        _mockChainlinkUpdatedAt(feed.fraxToEth(), -1*int(feed.fraxToEthHeartbeat()));

        (
            uint80 roundId,
            int256 wstEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if stale price return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 stEthFallback, , , ) = feed.fraxToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.sFrax().convertToAssets(1 ether) *
            uint256(stEthFallback) / 10 ** 8;

        assertEq(uint256(wstEthUsdPrice), estimatedWstEthUSDPrice);
        assertEq(uint256(wstEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_OutOfMinBoundsETH_WillReturn_STALE_fallbackWhenOutOfMinBoundsStETH() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();

        _mockChainlinkPrice(feed.fraxToUsd(),1);
        _mockChainlinkPrice(feed.ethToUsd(), 1);

        (
            uint80 roundId,
            int256 wstEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if out of bounds return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 stEthFallback, , , ) = feed.fraxToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.sFrax().convertToAssets(1 ether) *
            uint256(stEthFallback) / 10 ** 8;

        assertEq(uint256(wstEthUsdPrice), estimatedWstEthUSDPrice);
        assertEq(uint256(wstEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_OutOfMaxBoundsETH_WillReturn_STALE_fallbackWhenOutOfMinBoundsStETH() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();


        _mockChainlinkPrice(feed.fraxToUsd(), 1);
        _mockChainlinkPrice(feed.ethToUsd(),  type(int192).max); // won't revert even if maxAnswer is the maximum int192 value but will return Stale price

            (
            uint80 roundId,
            int256 wstEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if out of bounds ETH return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 stEthFallback, , , ) = feed.fraxToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.sFrax().convertToAssets(1 ether) *
            uint256(stEthFallback) / 10 ** 8;

        assertEq(uint256(wstEthUsdPrice), estimatedWstEthUSDPrice);
        assertEq(uint256(wstEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_OutOfMinBoundsFraxtoEth_WillReturn_STALE_fallbackWhenOutOfMinBoundsStETH() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();

        _mockChainlinkPrice(feed.fraxToUsd(),1);
        _mockChainlinkPrice(feed.fraxToEth(), 1);

        (
            uint80 roundId,
            int256 wstEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if out of bounds return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 stEthFallback, , , ) = feed.fraxToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.sFrax().convertToAssets(1 ether) *
            uint256(stEthFallback) / 10 ** 8;

        assertEq(uint256(wstEthUsdPrice), estimatedWstEthUSDPrice);
        assertEq(uint256(wstEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_OutOfMaxBoundsFraxtoEth_WillReturn_STALE_fallbackWhenOutOfMinBoundsStETH() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();


        _mockChainlinkPrice(feed.fraxToUsd(), 1);
        _mockChainlinkPrice(feed.fraxToEth(),  type(int192).max); // won't revert even if maxAnswer is the maximum int192 value but will return Stale price

            (
            uint80 roundId,
            int256 wstEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if out of bounds ETH return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 stEthFallback, , , ) = feed.fraxToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.sFrax().convertToAssets(1 ether) *
            uint256(stEthFallback) / 10 ** 8;

        assertEq(uint256(wstEthUsdPrice), estimatedWstEthUSDPrice);
        assertEq(uint256(wstEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_Mutations() public {
        // Mutated line 128 return (max < price || min >= price);
        // If maxAnswer is out of bounds return TRUE
        IAggregator aggregator = IAggregator(feed.fraxToUsd().aggregator());
        int192 max = aggregator.maxAnswer();
        _mockChainlinkPrice(feed.fraxToUsd(), max);
        bool success = feed.isPriceOutOfBounds(max, feed.fraxToUsd());
        assertTrue(success);

        // Mutated line 161 int256 fraxToUsdPrice = ethToUsdPrice / fraxToEthPrice / 10**18;
        // Assert gt than ZERO
        // We are returning the price from the fallback since it's already fraxToUsd is already out of bounds from above mutation
        (,int price,,,) = feed.latestRoundData();
        assertGt(uint(price),0);

        // Mutated line 163  if(isPriceOutOfBounds(ethToUsdPrice, ethToUsd) || block.timestamp - updatedAt >= ethHeartbeat) {
        // Return NOT stale (updatedAtEth != 0) when  block.timestamp - updatedAt == ethHeartbeat
        (, , , uint updatedAt, ) = feed.ethToUsd().latestRoundData();
        _mockChainlinkUpdatedAt(feed.ethToUsd(), -1*int(feed.ethHeartbeat() - (block.timestamp - updatedAt)));
        (, , , uint updatedAtEth, ) = feed.fraxToUsdFallbackOracle();
        // Not stale when ethHeartbeat == block.timestamp - updatedAt
        assertGt(updatedAtEth,0);
        assertEq(feed.ethHeartbeat(),block.timestamp - updatedAtEth);


        // Mutated line 168  if(isPriceOutOfBounds(stEthToEthPrice, stEthToEth) || block.timestamp - updatedAtStEth >= stEthToEthHeartbeat) {
        // Not stale when stEthHeartbeat == block.timestamp - updatedAt, return updateAtEth from eth/usd oracle
        (, , , uint updatedAtStEth, ) = feed.fraxToEth().latestRoundData();
        _mockChainlinkUpdatedAt(feed.fraxToEth(), -1*int(feed.fraxToEthHeartbeat() - (block.timestamp - updatedAtStEth)));
        (, , , uint updatedAtstEthToEth,) = feed.fraxToEth().latestRoundData();
        assertEq(feed.fraxToEthHeartbeat(),block.timestamp - updatedAtstEthToEth);
        // The fallback returns the updatedAtEth (eth/usd) 
        (, , , uint updatedAtAfter, ) = feed.fraxToUsdFallbackOracle();
        assertEq(updatedAtEth,updatedAtAfter);
    }

    function test_setEthHeartbeat() public {
        assertEq(feed.ethHeartbeat(), 3600);

        vm.expectRevert(SFraxPriceFeed.OnlyGov.selector);
        feed.setEthHeartbeat(100);
        assertEq(feed.ethHeartbeat(), 3600);

        vm.prank(feed.gov());
        feed.setEthHeartbeat(100);
        assertEq(feed.ethHeartbeat(), 100);
    } 

    function test_setFraxToEthHeartbeat() public {
        assertEq(feed.fraxToEthHeartbeat(), 86400);

        vm.expectRevert(SFraxPriceFeed.OnlyGov.selector);
        feed.setFraxEthHeartbeat(100);
        assertEq(feed.fraxToEthHeartbeat(), 86400);

        vm.prank(feed.gov());
        feed.setFraxEthHeartbeat(100);
        assertEq(feed.fraxToEthHeartbeat(), 100);
    } 

    function test_setGov() public {
        assertEq(feed.gov(), 0x926dF14a23BE491164dCF93f4c468A50ef659D5B);

        vm.expectRevert(SFraxPriceFeed.OnlyGov.selector);
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