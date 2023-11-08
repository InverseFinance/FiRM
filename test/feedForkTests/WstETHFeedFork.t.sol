// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {WstETHPriceFeed, IAggregator, IChainlinkFeed} from "src/feeds/WstETHPriceFeed.sol";
import "forge-std/console.sol";


contract WstETHFeedFork is Test {
    WstETHPriceFeed feed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        feed = new WstETHPriceFeed();
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
        ) = feed.stEthToUsd().latestRoundData();
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

        uint256 wstEthTostEthRatio = feed.wstETH().stEthPerToken();
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

        _mockChainlinkPrice(feed.stEthToUsd(),type(int192).max);

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

        (, int256 stEthFallback, , , ) = feed.stEthToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.wstETH().stEthPerToken() *
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

        _mockChainlinkPrice(feed.stEthToUsd(),1);

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

        (, int256 stEthFallback, , , ) = feed.stEthToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.wstETH().stEthPerToken() *
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

        _mockChainlinkPrice(feed.stEthToUsd(),1);
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

        (, int256 stEthFallback, , , ) = feed.stEthToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.wstETH().stEthPerToken() *
            uint256(stEthFallback) / 10 ** 8;
     
        assertEq(uint256(wstEthUsdPrice), estimatedWstEthUSDPrice);
        assertEq(uint256(wstEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_StaleStEthToEth_WillReturnFallbackWhenOutOfMinBoundsStETH() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();

        _mockChainlinkPrice(feed.stEthToUsd(),1);
        _mockChainlinkUpdatedAt(feed.stEthToEth(), -1*int(feed.stEthToEthHeartbeat()));

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

        (, int256 stEthFallback, , , ) = feed.stEthToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.wstETH().stEthPerToken() *
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

        _mockChainlinkPrice(feed.stEthToUsd(),1);
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

        (, int256 stEthFallback, , , ) = feed.stEthToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.wstETH().stEthPerToken() *
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


        _mockChainlinkPrice(feed.stEthToUsd(), 1);
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

        (, int256 stEthFallback, , , ) = feed.stEthToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.wstETH().stEthPerToken() *
            uint256(stEthFallback) / 10 ** 8;
     
        assertEq(uint256(wstEthUsdPrice), estimatedWstEthUSDPrice);
        assertEq(uint256(wstEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_OutOfMinBoundsStETHtoEth_WillReturn_STALE_fallbackWhenOutOfMinBoundsStETH() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();

        _mockChainlinkPrice(feed.stEthToUsd(),1);
        _mockChainlinkPrice(feed.stEthToEth(), 1);

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

        (, int256 stEthFallback, , , ) = feed.stEthToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.wstETH().stEthPerToken() *
            uint256(stEthFallback) / 10 ** 8;
     
        assertEq(uint256(wstEthUsdPrice), estimatedWstEthUSDPrice);
        assertEq(uint256(wstEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_OutOfMaxBoundsStETHtoEth_WillReturn_STALE_fallbackWhenOutOfMinBoundsStETH() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();


        _mockChainlinkPrice(feed.stEthToUsd(), 1);
        _mockChainlinkPrice(feed.stEthToEth(),  type(int192).max); // won't revert even if maxAnswer is the maximum int192 value but will return Stale price

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

        (, int256 stEthFallback, , , ) = feed.stEthToUsdFallbackOracle();

        uint256 estimatedWstEthUSDPrice = feed.wstETH().stEthPerToken() *
            uint256(stEthFallback) / 10 ** 8;
     
        assertEq(uint256(wstEthUsdPrice), estimatedWstEthUSDPrice);
        assertEq(uint256(wstEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_Mutations() public {
        // Mutated line 128 return (max < price || min >= price);
        // If maxAnswer is out of bounds return TRUE
        IAggregator aggregator = IAggregator(feed.stEthToUsd().aggregator());
        int192 max = aggregator.maxAnswer();
        _mockChainlinkPrice(feed.stEthToUsd(), max);
        bool success = feed.isPriceOutOfBounds(max, feed.stEthToUsd());
        assertTrue(success);

        // Mutated line 161 int256 stEthToUsdPrice = ethToUsdPrice / stEthToEthPrice / 10**18;
        // Assert gt than ZERO
        // We are returning the price from the fallback since it's already stEthToUsd is already out of bounds from above mutation
        (,int price,,,) = feed.latestRoundData();
        assertGt(uint(price),0);

        // Mutated line 163  if(isPriceOutOfBounds(ethToUsdPrice, ethToUsd) || block.timestamp - updatedAt >= ethHeartbeat) {
        // Return NOT stale (updatedAtEth != 0) when  block.timestamp - updatedAt == ethHeartbeat
        (, , , uint updatedAt, ) = feed.ethToUsd().latestRoundData();
        _mockChainlinkUpdatedAt(feed.ethToUsd(), -1*int(feed.ethHeartbeat() - (block.timestamp - updatedAt)));
        (, , , uint updatedAtEth, ) = feed.stEthToUsdFallbackOracle();
        // Not stale when ethHeartbeat == block.timestamp - updatedAt
        assertGt(updatedAtEth,0);
        assertEq(feed.ethHeartbeat(),block.timestamp - updatedAtEth);


        // Mutated line 168  if(isPriceOutOfBounds(stEthToEthPrice, stEthToEth) || block.timestamp - updatedAtStEth >= stEthToEthHeartbeat) {
        // Not stale when stEthHeartbeat == block.timestamp - updatedAt, return updateAtEth from eth/usd oracle
        (, , , uint updatedAtStEth, ) = feed.stEthToEth().latestRoundData();
        _mockChainlinkUpdatedAt(feed.stEthToEth(), -1*int(feed.stEthToEthHeartbeat() - (block.timestamp - updatedAtStEth)));
        (, , , uint updatedAtstEthToEth,) = feed.stEthToEth().latestRoundData();
        assertEq(feed.stEthToEthHeartbeat(),block.timestamp - updatedAtstEthToEth);
        // The fallback returns the updatedAtEth (eth/usd) 
        (, , , uint updatedAtAfter, ) = feed.stEthToUsdFallbackOracle();
        assertEq(updatedAtEth,updatedAtAfter);
    }

    function test_setEthHeartbeat() public {
        assertEq(feed.ethHeartbeat(), 3600);

        vm.expectRevert(WstETHPriceFeed.OnlyGov.selector);
        feed.setEthHeartbeat(100);
        assertEq(feed.ethHeartbeat(), 3600);

        vm.prank(feed.gov());
        feed.setEthHeartbeat(100);
        assertEq(feed.ethHeartbeat(), 100);
    } 

    function test_setStEthToEthHeartbeat() public {
        assertEq(feed.stEthToEthHeartbeat(), 86400);

        vm.expectRevert(WstETHPriceFeed.OnlyGov.selector);
        feed.setStEthHeartbeat(100);
        assertEq(feed.stEthToEthHeartbeat(), 86400);

        vm.prank(feed.gov());
        feed.setStEthHeartbeat(100);
        assertEq(feed.stEthToEthHeartbeat(), 100);
    } 

    function test_setGov() public {
        assertEq(feed.gov(), 0x926dF14a23BE491164dCF93f4c468A50ef659D5B);

        vm.expectRevert(WstETHPriceFeed.OnlyGov.selector);
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
        console.log("updatedAt in mockChainlinkUpdatedat", updatedAt);
        console.log(uint(int(updatedAt) + updatedAtDelta), "updatedAtDelta");
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