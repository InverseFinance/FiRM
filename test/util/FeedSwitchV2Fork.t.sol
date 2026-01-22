// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {FeedSwitchV2} from "src/util/FeedSwitchV2.sol";
import {ChainlinkBasePriceFeed, IChainlinkFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";
import {CurveLPPessimisticFeed, ICurvePool} from "src/feeds/CurveLPPessimisticFeed.sol";

/// @title FeedSwitchV2 Fork Test
/// @notice Fork test for FeedSwitchV2 using our wrapped USDe(normalized via sUSDe) and USDT 
contract FeedSwitchV2ForkTest is Test, ConfigAddr {
    FeedSwitchV2 feedSwitch;
    
    // Chainlinkfeed (8 decimals)
    address clUsdtToUsd = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    
    // Wrapped feeds (18 decimals)
    // This feed is the one already in use by the LP feed for DOLA/sUSDe
    ChainlinkBasePriceFeed sUSDeWrappedFeed = ChainlinkBasePriceFeed(0x6277cB27232F35C75D3d908b26F3670e7d167400);
    ChainlinkBasePriceFeed usdtWrappedFeed;
    
    CurveLPPessimisticFeed dolaSUSDeFeed;
    ICurvePool curvePool = ICurvePool(0x744793B5110f6ca9cC7CDfe1CE16677c3Eb192ef); // DOLA/sUSDe Curve Pool
    address dolaFixedPriceFeed = 0x5CB542EB054f81b8Fa1760c077f44AA80271c75D; // DOLA/USD fixed price feed

    address guardian = address(0x123);
    address user = address(0x456);
    
    uint256 timelockPeriod = 18 hours;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21236794);
        
        
        usdtWrappedFeed = new ChainlinkBasePriceFeed(
            gov,
            clUsdtToUsd,
            address(0), 
            24 hours  // usdt heartbeat 
        );
        
        // deploy FeedSwitchV2 with USDT as initial feed and sUSDe as fallback
        feedSwitch = new FeedSwitchV2(
            address(usdtWrappedFeed),
            address(sUSDeWrappedFeed),
            timelockPeriod,
            gov,
            guardian
        );

        // seploy LP feed using the feed switch together with fixed dola price feed
        dolaSUSDeFeed = new CurveLPPessimisticFeed(
            address(curvePool),
            address(feedSwitch),
            dolaFixedPriceFeed,
            false
        );
    }

    function test_deployment() public view {
        assertEq(address(feedSwitch.feed()), address(usdtWrappedFeed));
        assertEq(address(feedSwitch.initialFeed()), address(usdtWrappedFeed));
        assertEq(address(feedSwitch.fallbackFeed()), address(sUSDeWrappedFeed));
        assertEq(feedSwitch.timelockPeriod(), timelockPeriod);
        assertEq(feedSwitch.decimals(), 18);
        assertEq(sUSDeWrappedFeed.decimals(), 18);
        assertEq(usdtWrappedFeed.decimals(), 18);
        assertEq(feedSwitch.switchCompletedAt(), 0);
    }

    function test_toggleFeedSwitch() public {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        assertEq(address(feedSwitch.feed()), address(sUSDeWrappedFeed));
        assertEq(address(feedSwitch.previousFeed()), address(usdtWrappedFeed));
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp + timelockPeriod);

        int256 price = feedSwitch.latestAnswer();
        int256 expectedPrice = usdtWrappedFeed.latestAnswer();
        assertEq(price, expectedPrice);

        vm.warp(block.timestamp + timelockPeriod);
        // after timelock, latest answer should be from the new feed
        price = feedSwitch.latestAnswer();
        expectedPrice = sUSDeWrappedFeed.latestAnswer();
        assertEq(price, expectedPrice);
    }

    function test_toggleFeedSwitch_revertsIfNotGuardian() public {
        vm.prank(user);
        vm.expectRevert(FeedSwitchV2.NotGuardian.selector);
        feedSwitch.toggleFeedSwitch();
    }

    function test_toggleFeedSwitch_then_toggleBack() public {
        // First toggle: USDT -> sUSDe
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        vm.warp(block.timestamp + timelockPeriod);
        
        // Second toggle: sUSDe -> USDT
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        assertEq(address(feedSwitch.feed()), address(usdtWrappedFeed));
        assertEq(address(feedSwitch.previousFeed()), address(sUSDeWrappedFeed));
    }

    function test_toggleFeedSwitch_then_cancel_DuringTimelock() public {
        // Initiate switch
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        uint256 expectedCompletedAt = block.timestamp + timelockPeriod;
        assertEq(feedSwitch.switchCompletedAt(), expectedCompletedAt);
        
        // advance time but still before timelock has passed
        vm.warp(block.timestamp + timelockPeriod / 2);
        
        // cancel switch
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        // should reset switchCompletedAt to 0 and toggle back to USDT
        assertEq(feedSwitch.switchCompletedAt(), 0);
        assertEq(address(feedSwitch.feed()), address(usdtWrappedFeed));
    }

    function test_latestRoundData_return_USDT_beforeSwitch_and_LP_Feed_price() public {
        (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feedSwitch.latestRoundData();
        
        (
            uint80 expectedRoundId,
            int256 expectedPrice,
            uint256 expectedStartedAt,
            uint256 expectedUpdatedAt,
            uint80 expectedAnsweredInRound
        ) = usdtWrappedFeed.latestRoundData();
        
        assertEq(roundId, expectedRoundId);
        assertEq(price, expectedPrice);
        assertEq(startedAt, expectedStartedAt);
        assertEq(updatedAt, expectedUpdatedAt);
        assertEq(answeredInRound, expectedAnsweredInRound);

        // Check that nested CurveLPPessimisticFeed uses feed switch price and curve pool virtual price to get LP price
        // mock dola fixed price feed at 1.1$ since usdt is slighlty above 1$
        vm.mockCall(dolaFixedPriceFeed, abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector), abi.encode(0,1.1e18,0,0,0));
        int256 lpPrice = dolaSUSDeFeed.latestAnswer();
        int256 expectedLpPrice = (price * int256(curvePool.get_virtual_price())) / 1e18;
        assertEq(lpPrice, expectedLpPrice);
    }

    function test_latestRoundData_returnsPreviousFeed_DuringTimelock_and_LP_Feed_price() public {
        (, int256 usdtPrice, , ,) = usdtWrappedFeed.latestRoundData();
        
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        // during timelock, should still return previous feed (USDT)
        (, int256 price, , ,) = feedSwitch.latestRoundData();
        
        assertEq(price, usdtPrice);

        // mock dola fixed price feed at 1.1$ since usdt is slighlty above 1$
        vm.mockCall(dolaFixedPriceFeed, abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector), abi.encode(0,1.1e18,0,0,0));
        int256 lpPrice = dolaSUSDeFeed.latestAnswer();
        int256 expectedLpPrice = (price * int256(curvePool.get_virtual_price())) / 1e18;
        assertEq(lpPrice, expectedLpPrice);
    }

    function test_latestRoundData_returns_SUSDe_AfterTimelock() public {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        vm.warp(block.timestamp + timelockPeriod);
        
        (, int256 price, , uint256 updatedAt ,) = feedSwitch.latestRoundData();
        (, int256 expectedPrice, ,uint256 expectedUpdatedAt ,) = sUSDeWrappedFeed.latestRoundData();
        
        assertEq(price, expectedPrice);
        assertEq(updatedAt, expectedUpdatedAt);

        console.log("price", price);
        // mock dola fixed price feed at 1.1$ since sUSDe is slighlty above 1$
        vm.mockCall(dolaFixedPriceFeed, abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector), abi.encode(0,1.1e18,0,0,0));
        // LP Feed now uses sUSDe price
        int256 lpPrice = dolaSUSDeFeed.latestAnswer();
        int256 expectedLpPrice = (price * int256(curvePool.get_virtual_price())) / 1e18;
        assertEq(lpPrice, expectedLpPrice);
    }
   
    function test_latestAnswer_returns_USDT_BeforeSwitch() public view {
        int256 price = feedSwitch.latestAnswer();
        int256 expectedPrice = usdtWrappedFeed.latestAnswer();
        assertEq(price, expectedPrice);
    }

    function test_latestAnswer_returns_SUSDe_AfterTimelock() public {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        // Move after timelock
        vm.warp(block.timestamp + timelockPeriod);
        
        int256 price = feedSwitch.latestAnswer();
        int256 expectedPrice = sUSDeWrappedFeed.latestAnswer();
        assertEq(price, expectedPrice);
    }

    function test_isFeedSwitchQueued_returnsZero_WhenNotQueued() public view {
        uint256 timeLeft = feedSwitch.isFeedSwitchQueued();
        assertEq(timeLeft, 0);
    }

    function test_isFeedSwitchQueued_returnsTimeLeft_WhenQueued() public {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        uint256 timeLeft = feedSwitch.isFeedSwitchQueued();
        assertEq(timeLeft, timelockPeriod);
    }

    function test_isFeedSwitchQueued_decreaseOverTime() public {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        vm.warp(block.timestamp + 6 hours);
        
        uint256 timeLeft = feedSwitch.isFeedSwitchQueued();
        assertEq(timeLeft, timelockPeriod - 6 hours);
    }

    function test_isFeedSwitchQueued_returnsZero_AfterTimelock() public {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        vm.warp(block.timestamp + timelockPeriod);
        
        uint256 timeLeft = feedSwitch.isFeedSwitchQueued();
        assertEq(timeLeft, 0);
    }

 
    function test_zeroTimelockPeriod_immediateSwitch() public {
        vm.prank(gov);
        feedSwitch.setTimelockPeriod(0);
        
        int256 sUSDePrice = sUSDeWrappedFeed.latestAnswer();
        
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        // Should immediately use the new feed
        int256 price = feedSwitch.latestAnswer();
        assertEq(price, sUSDePrice);

        console.log("price", price);
        // mock dola fixed price feed at 1.1$ since sUSDe is slighlty above 1$
        vm.mockCall(dolaFixedPriceFeed, abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector), abi.encode(0,1.1e18,0,0,0));
        // LP Feed now uses sUSDe price
        int256 lpPrice = dolaSUSDeFeed.latestAnswer();
        int256 expectedLpPrice = (price * int256(curvePool.get_virtual_price())) / 1e18;
        assertEq(lpPrice, expectedLpPrice);
    }

    // Multiple switch tests

    function test_switchCancelReinitiate() public {
        int256 usdtPrice = usdtWrappedFeed.latestAnswer();
        assertEq(feedSwitch.latestAnswer(), usdtPrice);
        
        // Guardian initiates switch
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        assertEq(address(feedSwitch.feed()), address(sUSDeWrappedFeed));
        
        // During timelock, still returns USDT price
        vm.warp(block.timestamp + 6 hours);
        assertEq(feedSwitch.latestAnswer(), usdtPrice);
        
        // Guardian cancels switch
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        assertEq(address(feedSwitch.feed()), address(usdtWrappedFeed));
        assertEq(feedSwitch.switchCompletedAt(), 0);
        
        // Still returns USDT price
        vm.warp(block.timestamp + 1 days);
        assertEq(feedSwitch.latestAnswer(), usdtPrice);
        
        // Guardian re-initiates switch
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        assertEq(address(feedSwitch.feed()), address(sUSDeWrappedFeed));
        
        // Wait for timelock to complete
        vm.warp(block.timestamp + timelockPeriod);
        
        // Now returns sUSDe price
        int256 sUSDePrice = sUSDeWrappedFeed.latestAnswer();
        assertEq(feedSwitch.latestAnswer(), sUSDePrice);
    }

    function test_multipleSwitches() public {
        // Switch to sUSDe
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        vm.warp(block.timestamp + timelockPeriod);
        int256 sUSDePrice = sUSDeWrappedFeed.latestAnswer();
        assertEq(feedSwitch.latestAnswer(), sUSDePrice);
        
        // Switch back to USDT
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        vm.warp(block.timestamp + timelockPeriod);
        int256 usdtPrice = usdtWrappedFeed.latestAnswer();
        assertEq(feedSwitch.latestAnswer(), usdtPrice);
        
        // Switch again to sUSDe
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        vm.warp(block.timestamp + timelockPeriod);
        sUSDePrice = sUSDeWrappedFeed.latestAnswer();
        assertEq(feedSwitch.latestAnswer(), sUSDePrice);
    }


    // Admin tests
    function test_setPendingGov() public {
        address newGov = address(0x5);
        
        vm.prank(gov);
        feedSwitch.setPendingGov(newGov);
        
        assertEq(feedSwitch.pendingGov(), newGov);
    }

    function test_setPendingGov_revertsIfNotGov() public {
        vm.prank(user);
        vm.expectRevert(FeedSwitchV2.NotGov.selector);
        feedSwitch.setPendingGov(user);
    }

    function test_acceptGov() public {
        address newGov = address(0x5);
        
        vm.prank(gov);
        feedSwitch.setPendingGov(newGov);
        
        vm.prank(newGov);
        feedSwitch.acceptGov();
        
        assertEq(feedSwitch.gov(), newGov);
        assertEq(feedSwitch.pendingGov(), address(0));
    }

    function test_acceptGov_revertsIfNotPendingGov() public {
        address newGov = address(0x5);
        
        vm.prank(gov);
        feedSwitch.setPendingGov(newGov);
        
        vm.prank(user);
        vm.expectRevert(FeedSwitchV2.NotPendingGov.selector);
        feedSwitch.acceptGov();
    }

    function test_setGuardian() public {
        address newGuardian = address(0x6);
        
        vm.prank(gov);
        feedSwitch.setGuardian(newGuardian, true);
        
        assertEq(feedSwitch.isGuardian(newGuardian), true);
    }

    function test_setGuardian_removeGuardian() public {
        vm.prank(gov);
        feedSwitch.setGuardian(guardian, false);
        
        assertEq(feedSwitch.isGuardian(guardian), false);
    }

    function test_setGuardian_revertsIfNotGov() public {
        vm.prank(user);
        vm.expectRevert(FeedSwitchV2.NotGov.selector);
        feedSwitch.setGuardian(user, true);
    }

    function test_setTimelockPeriod() public {
        uint256 newTimelockPeriod = 24 hours;
        
        vm.prank(gov);
        feedSwitch.setTimelockPeriod(newTimelockPeriod);
        
        assertEq(feedSwitch.timelockPeriod(), newTimelockPeriod);
    }

    function test_setTimelockPeriod_canSetToZero() public {
        vm.prank(gov);
        feedSwitch.setTimelockPeriod(0);
        
        assertEq(feedSwitch.timelockPeriod(), 0);
    }

    function test_setTimelockPeriod_revertsIfNotGov() public {
        vm.prank(user);
        vm.expectRevert(FeedSwitchV2.NotGov.selector);
        feedSwitch.setTimelockPeriod(24 hours);
    }

}
