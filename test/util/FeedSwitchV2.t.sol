// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {FeedSwitchV2} from "src/util/FeedSwitchV2.sol";
import {MockFeed} from "test/mocks/MockFeed.sol";

contract FeedSwitchV2Test is Test {
    FeedSwitchV2 feedSwitch;
    MockFeed initialFeed;
    MockFeed fallbackFeed;
    
    address gov = address(0x1);
    address guardian = address(0x2);
    address user = address(0x3);
    
    uint256 timelockPeriod = 18 hours;

    event FeedSwitchInitiated(address indexed newFeed, uint256 effectiveAt);
    event NewPendingGov(address indexed pendingGov);
    event GovChanged(address indexed newGov);
    event GuardianSet(address indexed guardian, bool isGuardian);
    event TimelockPeriodChanged(uint256 newTimelockPeriod);

    function setUp() public {
        initialFeed = new MockFeed(18, 1e18);
        fallbackFeed = new MockFeed(18, 0.95e18);
        
        feedSwitch = new FeedSwitchV2(
            address(initialFeed),
            address(fallbackFeed),
            timelockPeriod,
            gov,
            guardian
        );
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deployment() public view {
        assertEq(address(feedSwitch.feed()), address(initialFeed));
        assertEq(address(feedSwitch.initialFeed()), address(initialFeed));
        assertEq(address(feedSwitch.fallbackFeed()), address(fallbackFeed));
        assertEq(feedSwitch.timelockPeriod(), timelockPeriod);
        assertEq(feedSwitch.gov(), gov);
        assertEq(feedSwitch.isGuardian(guardian), true);
        assertEq(feedSwitch.decimals(), 18);
        assertEq(feedSwitch.switchCompletedAt(), 0);
    }

    function test_Deployment_RevertsIfInitialFeedNotDecimals18() public {
        MockFeed badFeed = new MockFeed(8, 1e8);
        
        vm.expectRevert(FeedSwitchV2.FeedDecimalsMismatch.selector);
        new FeedSwitchV2(
            address(badFeed),
            address(fallbackFeed),
            timelockPeriod,
            gov,
            guardian
        );
    }

    function test_Deployment_RevertsIfFallbackFeedNotDecimals18() public {
        MockFeed badFeed = new MockFeed(8, 1e8);
        
        vm.expectRevert(FeedSwitchV2.FeedDecimalsMismatch.selector);
        new FeedSwitchV2(
            address(initialFeed),
            address(badFeed),
            timelockPeriod,
            gov,
            guardian
        );
    }

    /*//////////////////////////////////////////////////////////////
                        TOGGLE FEED SWITCH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ToggleFeedSwitch_InitiatesSwitchToFallback() public {
        vm.prank(guardian);
        vm.expectEmit(true, false, false, false);
        emit FeedSwitchInitiated(address(fallbackFeed), block.timestamp + timelockPeriod);
        feedSwitch.toggleFeedSwitch();
        
        assertEq(address(feedSwitch.feed()), address(fallbackFeed));
        assertEq(address(feedSwitch.previousFeed()), address(initialFeed));
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp + timelockPeriod);
    }

    function test_ToggleFeedSwitch_RevertsIfNotGuardian() public {
        vm.prank(user);
        vm.expectRevert(FeedSwitchV2.NotGuardian.selector);
        feedSwitch.toggleFeedSwitch();
    }

    function test_ToggleFeedSwitch_ToggleBackToInitial() public {
        // First toggle: initial -> fallback
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        // Warp past timelock
        vm.warp(block.timestamp + timelockPeriod + 1);
        
        // Second toggle: fallback -> initial
        vm.prank(guardian);
        vm.expectEmit(true, false, false, false);
        emit FeedSwitchInitiated(address(initialFeed), block.timestamp);
        feedSwitch.toggleFeedSwitch();
        
        assertEq(address(feedSwitch.feed()), address(initialFeed));
        assertEq(address(feedSwitch.previousFeed()), address(fallbackFeed));
    }

    function test_ToggleFeedSwitch_CancelsDuringTimelock() public {
        // Initiate switch
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        uint256 expectedCompletedAt = block.timestamp + timelockPeriod;
        assertEq(feedSwitch.switchCompletedAt(), expectedCompletedAt);
        
        // Warp partway through timelock
        vm.warp(block.timestamp + timelockPeriod / 2);
        
        // Toggle again (should cancel and toggle feed)
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        // Should reset switchCompletedAt to 0 and toggle back to initial
        assertEq(feedSwitch.switchCompletedAt(), 0);
        assertEq(address(feedSwitch.feed()), address(initialFeed));
    }

    function test_ToggleFeedSwitch_MultipleGuardiansCanToggle() public {
        address guardian2 = address(0x4);
        
        vm.prank(gov);
        feedSwitch.setGuardian(guardian2, true);
        
        vm.prank(guardian2);
        feedSwitch.toggleFeedSwitch();
        
        assertEq(address(feedSwitch.feed()), address(fallbackFeed));
    }

    /*//////////////////////////////////////////////////////////////
                        LATEST ROUND DATA TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LatestRoundData_ReturnsInitialFeedBeforeSwitch() public view {
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
        ) = initialFeed.latestRoundData();
        
        assertEq(roundId, expectedRoundId);
        assertEq(price, expectedPrice);
        assertEq(startedAt, expectedStartedAt);
        assertEq(updatedAt, expectedUpdatedAt);
        assertEq(answeredInRound, expectedAnsweredInRound);
    }

    function test_LatestRoundData_ReturnsPreviousFeedDuringTimelock() public {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        // During timelock, should still return previous feed (initialFeed)
        (, int256 price, , ,) = feedSwitch.latestRoundData();
        (, int256 expectedPrice, , ,) = initialFeed.latestRoundData();
        
        assertEq(price, expectedPrice);
    }

    function test_LatestRoundData_ReturnsNewFeedAfterTimelock() public {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        // Warp past timelock
        vm.warp(block.timestamp + timelockPeriod);
        
        (, int256 price, , ,) = feedSwitch.latestRoundData();
        (, int256 expectedPrice, , ,) = fallbackFeed.latestRoundData();
        
        assertEq(price, expectedPrice);
    }

    /*//////////////////////////////////////////////////////////////
                          LATEST ANSWER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LatestAnswer_ReturnsInitialFeedBeforeSwitch() public view {
        int256 price = feedSwitch.latestAnswer();
        assertEq(uint256(price), 1e18);
    }

    function test_LatestAnswer_ReturnsPreviousFeedDuringTimelock() public {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        // During timelock
        int256 price = feedSwitch.latestAnswer();
        assertEq(uint256(price), 1e18); // initialFeed price
    }

    function test_LatestAnswer_ReturnsNewFeedAfterTimelock() public {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        // Warp past timelock
        vm.warp(block.timestamp + timelockPeriod);
        
        int256 price = feedSwitch.latestAnswer();
        assertEq(uint256(price), 0.95e18); // fallbackFeed price
    }

    /*//////////////////////////////////////////////////////////////
                        IS FEED SWITCH QUEUED TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsFeedSwitchQueued_ReturnsZeroWhenNotQueued() public view {
        uint256 timeLeft = feedSwitch.isFeedSwitchQueued();
        assertEq(timeLeft, 0);
    }

    function test_IsFeedSwitchQueued_ReturnsTimeLeftWhenQueued() public {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        uint256 timeLeft = feedSwitch.isFeedSwitchQueued();
        assertEq(timeLeft, timelockPeriod);
    }

    function test_IsFeedSwitchQueued_DecrementsOverTime() public {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        vm.warp(block.timestamp + 6 hours);
        
        uint256 timeLeft = feedSwitch.isFeedSwitchQueued();
        assertEq(timeLeft, timelockPeriod - 6 hours);
    }

    function test_IsFeedSwitchQueued_ReturnsZeroAfterTimelock() public {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        vm.warp(block.timestamp + timelockPeriod);
        
        uint256 timeLeft = feedSwitch.isFeedSwitchQueued();
        assertEq(timeLeft, 0);
    }

    /*//////////////////////////////////////////////////////////////
                          GOVERNANCE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetPendingGov() public {
        address newGov = address(0x5);
        
        vm.prank(gov);
        vm.expectEmit(true, false, false, false);
        emit NewPendingGov(newGov);
        feedSwitch.setPendingGov(newGov);
        
        assertEq(feedSwitch.pendingGov(), newGov);
    }

    function test_SetPendingGov_RevertsIfNotGov() public {
        vm.prank(user);
        vm.expectRevert(FeedSwitchV2.NotGov.selector);
        feedSwitch.setPendingGov(user);
    }

    function test_AcceptGov() public {
        address newGov = address(0x5);
        
        vm.prank(gov);
        feedSwitch.setPendingGov(newGov);
        
        vm.prank(newGov);
        vm.expectEmit(true, false, false, false);
        emit GovChanged(newGov);
        feedSwitch.acceptGov();
        
        assertEq(feedSwitch.gov(), newGov);
        assertEq(feedSwitch.pendingGov(), address(0));
    }

    function test_AcceptGov_RevertsIfNotPendingGov() public {
        address newGov = address(0x5);
        
        vm.prank(gov);
        feedSwitch.setPendingGov(newGov);
        
        vm.prank(user);
        vm.expectRevert(FeedSwitchV2.NotPendingGov.selector);
        feedSwitch.acceptGov();
    }

    /*//////////////////////////////////////////////////////////////
                           GUARDIAN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetGuardian() public {
        address newGuardian = address(0x6);
        
        vm.prank(gov);
        vm.expectEmit(true, false, false, true);
        emit GuardianSet(newGuardian, true);
        feedSwitch.setGuardian(newGuardian, true);
        
        assertEq(feedSwitch.isGuardian(newGuardian), true);
    }

    function test_SetGuardian_RemoveGuardian() public {
        vm.prank(gov);
        vm.expectEmit(true, false, false, true);
        emit GuardianSet(guardian, false);
        feedSwitch.setGuardian(guardian, false);
        
        assertEq(feedSwitch.isGuardian(guardian), false);
    }

    function test_SetGuardian_RevertsIfNotGov() public {
        vm.prank(user);
        vm.expectRevert(FeedSwitchV2.NotGov.selector);
        feedSwitch.setGuardian(user, true);
    }

    /*//////////////////////////////////////////////////////////////
                        TIMELOCK PERIOD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetTimelockPeriod() public {
        uint256 newTimelockPeriod = 24 hours;
        
        vm.prank(gov);
        vm.expectEmit(false, false, false, true);
        emit TimelockPeriodChanged(newTimelockPeriod);
        feedSwitch.setTimelockPeriod(newTimelockPeriod);
        
        assertEq(feedSwitch.timelockPeriod(), newTimelockPeriod);
    }

    function test_SetTimelockPeriod_CanSetToZero() public {
        vm.prank(gov);
        feedSwitch.setTimelockPeriod(0);
        
        assertEq(feedSwitch.timelockPeriod(), 0);
    }

    function test_SetTimelockPeriod_RevertsIfNotGov() public {
        vm.prank(user);
        vm.expectRevert(FeedSwitchV2.NotGov.selector);
        feedSwitch.setTimelockPeriod(24 hours);
    }

    /*//////////////////////////////////////////////////////////////
                        ZERO TIMELOCK PERIOD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ZeroTimelockPeriod_ImmediateSwitch() public {
        FeedSwitchV2 instantSwitch = new FeedSwitchV2(
            address(initialFeed),
            address(fallbackFeed),
            0, // zero timelock
            gov,
            guardian
        );
        
        vm.prank(guardian);
        instantSwitch.toggleFeedSwitch();
        
        // Should immediately use the new feed
        int256 price = instantSwitch.latestAnswer();
        assertEq(uint256(price), 0.95e18); // fallbackFeed price
    }

    function test_TimelockUpdatedToZero_KeepsPreviousSwitchCompletedAt() public {
        // Initiate switch with 18 hour timelock
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        uint256 originalSwitchCompletedAt = feedSwitch.switchCompletedAt();
        assertEq(originalSwitchCompletedAt, block.timestamp + timelockPeriod);
        
        // Still using initialFeed during timelock
        assertEq(uint256(feedSwitch.latestAnswer()), 1e18);
        
        // Gov updates timelock to zero
        vm.prank(gov);
        feedSwitch.setTimelockPeriod(0);
        
        // switchCompletedAt is unchanged - the queued switch still uses original timelock
        assertEq(feedSwitch.switchCompletedAt(), originalSwitchCompletedAt);
        
        // Warp partway through original timelock - still using initialFeed
        vm.warp(block.timestamp + 6 hours);
        assertEq(uint256(feedSwitch.latestAnswer()), 1e18);
        assertGt(feedSwitch.isFeedSwitchQueued(), 0); // Still queued
        
        // Warp past original timelock - now uses fallbackFeed
        vm.warp(originalSwitchCompletedAt);
        assertEq(uint256(feedSwitch.latestAnswer()), 0.95e18);
        assertEq(feedSwitch.isFeedSwitchQueued(), 0); // No longer queued
    }

    function test_TimelockUpdatedToZero_CancelAndReswitchImmediate() public {
        // Initiate switch with 18 hour timelock
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        // Still using initialFeed during timelock
        assertEq(uint256(feedSwitch.latestAnswer()), 1e18);
        
        // Warp partway through timelock
        vm.warp(block.timestamp + 6 hours);
        assertEq(uint256(feedSwitch.latestAnswer()), 1e18);
        
        // Gov updates timelock to zero
        vm.prank(gov);
        feedSwitch.setTimelockPeriod(0);
        
        // Guardian cancels the current switch (toggle back to initial)
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), 0);
        assertEq(address(feedSwitch.feed()), address(initialFeed));
        
        // Guardian re-initiates switch - now with zero timelock, it's immediate
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        // switchCompletedAt is block.timestamp + 0 = block.timestamp
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp);
        
        // Immediately uses fallbackFeed (block.timestamp >= switchCompletedAt)
        assertEq(uint256(feedSwitch.latestAnswer()), 0.95e18);
        assertEq(feedSwitch.isFeedSwitchQueued(), 0); // Not queued, already effective
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLEX SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Scenario_SwitchCancelReinitiate() public {
        // Initial state: using initialFeed
        assertEq(uint256(feedSwitch.latestAnswer()), 1e18);
        
        // Guardian initiates switch
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        assertEq(address(feedSwitch.feed()), address(fallbackFeed));
        
        // During timelock, still returns initialFeed price
        vm.warp(block.timestamp + 6 hours);
        assertEq(uint256(feedSwitch.latestAnswer()), 1e18);
        
        // Guardian cancels (toggles back)
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        assertEq(address(feedSwitch.feed()), address(initialFeed));
        assertEq(feedSwitch.switchCompletedAt(), 0);
        
        // Still returns initialFeed price
        vm.warp(block.timestamp + 1 days);
        assertEq(uint256(feedSwitch.latestAnswer()), 1e18);
        
        // Guardian re-initiates switch
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        assertEq(address(feedSwitch.feed()), address(fallbackFeed));
        
        // Wait for timelock to complete
        vm.warp(block.timestamp + timelockPeriod);
        
        // Now returns fallbackFeed price
        assertEq(uint256(feedSwitch.latestAnswer()), 0.95e18);
    }

    function test_Scenario_MultipleSwitches() public {
        // Switch to fallback
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        vm.warp(block.timestamp + timelockPeriod);
        assertEq(uint256(feedSwitch.latestAnswer()), 0.95e18);
        
        // Switch back to initial
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        vm.warp(block.timestamp + timelockPeriod);
        assertEq(uint256(feedSwitch.latestAnswer()), 1e18);
        
        // Switch again to fallback
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        vm.warp(block.timestamp + timelockPeriod);
        assertEq(uint256(feedSwitch.latestAnswer()), 0.95e18);
    }

    function test_Scenario_FeedPriceChanges() public {
        // Initial price from initialFeed
        assertEq(uint256(feedSwitch.latestAnswer()), 1e18);
        
        // Change initial feed price
        initialFeed.changeAnswer(1.5e18);
        assertEq(uint256(feedSwitch.latestAnswer()), 1.5e18);
        
        // Switch to fallback
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        // During timelock, still using initialFeed (now at 1.5e18)
        assertEq(uint256(feedSwitch.latestAnswer()), 1.5e18);
        
        // Change fallback feed price
        fallbackFeed.changeAnswer(0.9e18);
        
        // Still using initialFeed during timelock
        assertEq(uint256(feedSwitch.latestAnswer()), 1.5e18);
        
        // After timelock
        vm.warp(block.timestamp + timelockPeriod);
        assertEq(uint256(feedSwitch.latestAnswer()), 0.9e18);
    }

    function test_Scenario_GovernanceTransfer() public {
        address newGov = address(0x10);
        
        // Set new pending gov
        vm.prank(gov);
        feedSwitch.setPendingGov(newGov);
        
        // Old gov can still make changes
        vm.prank(gov);
        feedSwitch.setTimelockPeriod(24 hours);
        assertEq(feedSwitch.timelockPeriod(), 24 hours);
        
        // New gov accepts
        vm.prank(newGov);
        feedSwitch.acceptGov();
        
        // Old gov can no longer make changes
        vm.prank(gov);
        vm.expectRevert(FeedSwitchV2.NotGov.selector);
        feedSwitch.setTimelockPeriod(12 hours);
        
        // New gov can make changes
        vm.prank(newGov);
        feedSwitch.setTimelockPeriod(12 hours);
        assertEq(feedSwitch.timelockPeriod(), 12 hours);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_SetTimelockPeriod(uint256 newPeriod) public {
        vm.prank(gov);
        feedSwitch.setTimelockPeriod(newPeriod);
        assertEq(feedSwitch.timelockPeriod(), newPeriod);
    }

    function testFuzz_IsFeedSwitchQueued_TimeProgression(uint256 timeElapsed) public {
        vm.assume(timeElapsed < timelockPeriod);
        
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        vm.warp(block.timestamp + timeElapsed);
        
        uint256 timeLeft = feedSwitch.isFeedSwitchQueued();
        assertEq(timeLeft, timelockPeriod - timeElapsed);
    }

    function testFuzz_LatestAnswer_DuringTimelock(uint256 timeElapsed) public {
        vm.assume(timeElapsed < timelockPeriod);
        
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        vm.warp(block.timestamp + timeElapsed);
        
        // Should still return initialFeed price during timelock
        assertEq(uint256(feedSwitch.latestAnswer()), 1e18);
    }

    function testFuzz_LatestAnswer_AfterTimelock(uint256 timeElapsed) public {
        vm.assume(timeElapsed >= timelockPeriod && timeElapsed < 365 days);
        
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
        
        vm.warp(block.timestamp + timeElapsed);
        
        // Should return fallbackFeed price after timelock
        assertEq(uint256(feedSwitch.latestAnswer()), 0.95e18);
    }
}
