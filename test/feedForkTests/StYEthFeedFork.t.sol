// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {StYEthPriceFeed, IAggregator, IChainlinkFeed, ICurvePool} from "src/feeds/StYEthPriceFeed.sol";
import "forge-std/console.sol";


contract WstETHFeedFork is Test {
    StYEthPriceFeed feed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 18535539);

        feed = new StYEthPriceFeed();
    }

    function test_decimals() public {
        assertEq(feed.decimals(), 18);
    }

    function test_latestRoundData() public {
        (
            uint80 clRoundId,
            int256 clEthToUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();
        (
            uint80 roundId,
            int256 stYEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(roundId, clRoundId);
        assertEq(startedAt, clStartedAt);
        assertEq(updatedAt, clUpdatedAt);
        assertEq(answeredInRound, clAnsweredInRound);

        uint256 ethTostyEthRatio = feed.curveYETH().ema_price() * feed.styETH().convertToAssets(1 ether);
        uint256 estimatedStyEthUSDPrice = uint(clEthToUsdPrice) * ethTostyEthRatio / 10 **8 / 10 **18;

        assertEq(uint256(stYEthUsdPrice), estimatedStyEthUSDPrice);
        assertEq(uint256(stYEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_use_capper_exchange_rate_YETH_ETH() public {
        (
            uint80 clRoundId,
            int256 clEthToUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.ethToUsd().latestRoundData();
        
        vm.mockCall(address(feed.curveYETH()), abi.encodeWithSelector(ICurvePool.ema_price.selector), abi.encode(10 ether));

        (
            uint80 roundId,
            int256 stYEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(roundId, clRoundId);
        assertEq(startedAt, clStartedAt);
        assertEq(updatedAt, clUpdatedAt);
        assertEq(answeredInRound, clAnsweredInRound);

     
        uint256 ethTostyEthRatio = 1e18 * feed.styETH().convertToAssets(1 ether);
        uint256 estimatedStyEthUSDPrice = uint(clEthToUsdPrice) * ethTostyEthRatio / 10 **8 / 10 **18;

        assertEq(uint256(stYEthUsdPrice), estimatedStyEthUSDPrice);
        assertEq(uint256(stYEthUsdPrice), uint(feed.latestAnswer()));
    }
    function test_WillReturnFallbackWhenOutOfMaxBounds() public {
        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.ethToBtc().latestRoundData();

        _mockChainlinkPrice(feed.ethToUsd(),type(int192).max);

        (
            uint80 roundId,
            int256 stYEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId,'round');
        assertEq(clStartedAt, startedAt,'startedAt');
        assertEq(clUpdatedAt, updatedAt,'updatedAt');
        assertEq(clAnsweredInRound, answeredInRound, 'answeredInRound');

        (, int256 ethFallback, , , ) = feed.ethToUsdFallbackOracle();

        uint256 estimatedStyEthUSDPrice = feed.curveYETH().ema_price() * feed.styETH().convertToAssets(1 ether) *
            uint256(ethFallback) / 10 ** 8 / 10 ** 18;

        assertEq(uint256(stYEthUsdPrice), estimatedStyEthUSDPrice, 'price');
        assertEq(uint256(stYEthUsdPrice), uint(feed.latestAnswer()),'latestAnswer');
    }

    function test_WillReturnFallbackWhenOutOfMinBounds() public {
          (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.ethToBtc().latestRoundData();

        _mockChainlinkPrice(feed.ethToUsd(),1);

        (
            uint80 roundId,
            int256 stYEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 ethFallback, , , ) = feed.ethToUsdFallbackOracle();

        uint256 estimatedStyEthUSDPrice = feed.curveYETH().ema_price() * feed.styETH().convertToAssets(1 ether) *
            uint256(ethFallback) / 10 ** 8 / 10 ** 18;

        assertEq(uint256(stYEthUsdPrice), estimatedStyEthUSDPrice);
        assertEq(uint256(stYEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_StaleEthToBtc_WillReturnFallbackWhenOutOfMinBoundsEthToUsd() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToBtc().latestRoundData();

        _mockChainlinkPrice(feed.ethToUsd(),1);
        _mockChainlinkUpdatedAt(feed.ethToBtc(), -1*int(feed.ethToBtcHeartbeat()));

        (
            uint80 roundId,
            int256 stYEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if stale price return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 ethFallback, , , ) = feed.ethToUsdFallbackOracle();

        uint256 estimatedStyEthUSDPrice = feed.curveYETH().ema_price() * feed.styETH().convertToAssets(1 ether) *
            uint256(ethFallback) / 10 ** 8 / 10 ** 18;

        assertEq(uint256(stYEthUsdPrice), estimatedStyEthUSDPrice);
        assertEq(uint256(stYEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_StaleBtcToUsd_WillReturnFallbackWhenOutOfMinBoundsEthToUsd() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToBtc().latestRoundData();

        _mockChainlinkPrice(feed.ethToUsd(),1);
        _mockChainlinkUpdatedAt(feed.btcToUsd(), -1*int(feed.btcToUsdHeartbeat()));

        (
            uint80 roundId,
            int256 stYEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if stale price return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 ethFallback, , , ) = feed.ethToUsdFallbackOracle();

        uint256 estimatedStyEthUSDPrice = feed.curveYETH().ema_price() * feed.styETH().convertToAssets(1 ether) *
            uint256(ethFallback) / 10 ** 8 / 10 ** 18;

        assertEq(uint256(stYEthUsdPrice), estimatedStyEthUSDPrice);
        assertEq(uint256(stYEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_OutOfMinBoundsETH_WillReturn_STALE_fallbackWhenOutOfMinBoundsEthToUsd() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToBtc().latestRoundData();

        _mockChainlinkPrice(feed.ethToUsd(),1);
        _mockChainlinkPrice(feed.ethToBtc(), 1);

        (
            uint80 roundId,
            int256 stYEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if out of bounds return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 ethFallback, , , ) = feed.ethToUsdFallbackOracle();

        uint256 estimatedStyEthUSDPrice = feed.curveYETH().ema_price() * feed.styETH().convertToAssets(1 ether) *
            uint256(ethFallback) / 10 ** 8 / 10 ** 18;

        assertEq(uint256(stYEthUsdPrice), estimatedStyEthUSDPrice);
        assertEq(uint256(stYEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_OutOfMaxBoundsETHtoBTC_WillReturn_STALE_fallbackWhenOutOfMinBoundsEthToUsd() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToBtc().latestRoundData();


        _mockChainlinkPrice(feed.ethToUsd(), 1);
         IAggregator aggregator = IAggregator(feed.ethToBtc().aggregator());
        _mockChainlinkPrice(feed.ethToBtc(),  aggregator.maxAnswer()); // won't revert even if maxAnswer but will return Stale price

            (
            uint80 roundId,
            int256 stYEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if out of bounds ETH return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 ethFallback, , , ) = feed.ethToUsdFallbackOracle();

        uint256 estimatedStyEthUSDPrice = feed.curveYETH().ema_price() * feed.styETH().convertToAssets(1 ether) *
            uint256(ethFallback) / 10 ** 8 / 10 ** 18;

        assertEq(uint256(stYEthUsdPrice), estimatedStyEthUSDPrice);
        assertEq(uint256(stYEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_OutOfMinBoundsBTCtoUSD_WillReturn_STALE_fallbackWhenOutOfMinBoundsEthToUsd() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToBtc().latestRoundData();

        _mockChainlinkPrice(feed.ethToUsd(),1);
        _mockChainlinkPrice(feed.btcToUsd(), 1);

        (
            uint80 roundId,
            int256 stYEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if out of bounds return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 ethFallback, , , ) = feed.ethToUsdFallbackOracle();

        uint256 estimatedStyEthUSDPrice = feed.curveYETH().ema_price() * feed.styETH().convertToAssets(1 ether) *
            uint256(ethFallback) / 10 ** 8 / 10 ** 18;

        assertEq(uint256(stYEthUsdPrice), estimatedStyEthUSDPrice);
        assertEq(uint256(stYEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_OutOfMaxBoundsBTCtoUSD_WillReturn_STALE_fallbackWhenOutOfMinBoundsEthToUsd() public {

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            ,
            uint80 clAnsweredInRound
        ) = feed.ethToBtc().latestRoundData();


        _mockChainlinkPrice(feed.ethToUsd(), 1);
        IAggregator aggregator = IAggregator(feed.btcToUsd().aggregator()); 
        _mockChainlinkPrice(feed.btcToUsd(), aggregator.maxAnswer() );// won't revert even if maxAnswer but will return Stale price
            (
            uint80 roundId,
            int256 stYEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(0, updatedAt); // if out of bounds ETH return updateAt == 0
        assertEq(clAnsweredInRound, answeredInRound);

        (, int256 ethFallback, , , ) = feed.ethToUsdFallbackOracle();

        uint256 estimatedStyEthUSDPrice = feed.curveYETH().ema_price() * feed.styETH().convertToAssets(1 ether) *
            uint256(ethFallback) / 10 ** 8 / 10 ** 18;

        assertEq(uint256(stYEthUsdPrice), estimatedStyEthUSDPrice);
        assertEq(uint256(stYEthUsdPrice), uint(feed.latestAnswer()));
    }

    function test_setEthBtcHeartbeat() public {
        assertEq(feed.ethToBtcHeartbeat(), 3600);

        vm.expectRevert(StYEthPriceFeed.OnlyGov.selector);
        feed.setEthBtcHeartbeat(100);
        assertEq(feed.ethToBtcHeartbeat(), 3600);

        vm.prank(feed.gov());
        feed.setEthBtcHeartbeat(100);
        assertEq(feed.ethToBtcHeartbeat(), 100);
    } 

    function test_setBtcToUsdHeartbeat() public {
        assertEq(feed.btcToUsdHeartbeat(), 3600);

        vm.expectRevert(StYEthPriceFeed.OnlyGov.selector);
        feed.setBtcUsdHeartbeat(100);
        assertEq(feed.btcToUsdHeartbeat(), 3600);

        vm.prank(feed.gov());
        feed.setBtcUsdHeartbeat(100);
        assertEq(feed.btcToUsdHeartbeat(), 100);
    } 

    function test_setGov() public {
        assertEq(feed.gov(), 0x926dF14a23BE491164dCF93f4c468A50ef659D5B);

        vm.expectRevert(StYEthPriceFeed.OnlyGov.selector);
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