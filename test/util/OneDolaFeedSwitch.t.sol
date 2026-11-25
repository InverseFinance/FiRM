// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {OneDolaFeedSwitch} from "src/feeds/OneDolaFeedSwitch.sol";
import {MockFeedDescription} from "test/mocks/MockFeedDescription.sol";
import {BorrowController} from "src/BorrowController.sol";
import {DolaBorrowingRights} from "src/DBR.sol";
import {Oracle, IChainlinkFeed} from "src/Oracle.sol";

contract OneDolaFeedSwitchTest is Test {
    OneDolaFeedSwitch feedSwitch;
    MockFeedDescription underlyingFeed;
    address gov = address(1);
    address guardian = address(2);
    address rwg = address(3);
    address user = address(4);
    uint256 constant TIMELOCK = 18 hours;
    int256 constant THRESHOLD = 0.95e18;

    event FeedSwitchInitiated(bool useFixedPrice, uint256 effectiveAt);
    event BorrowThresholdChanged(int256 newBorrowThreshold);

    function setUp() public {
        vm.warp(10 days);
        underlyingFeed = new MockFeedDescription(18, 0.98e18, "Asset / USD");
        feedSwitch = new OneDolaFeedSwitch(address(underlyingFeed), TIMELOCK, gov, guardian, rwg, THRESHOLD);
    }

    function test_DeploymentStartsWithFixedPrice() public view {
        assertEq(feedSwitch.FIXED_PRICE(), 1e18);
        assertEq(address(feedSwitch.underlyingFeed()), address(underlyingFeed));
        assertEq(feedSwitch.RWG(), rwg);
        assertEq(feedSwitch.gov(), gov);
        assertTrue(feedSwitch.isGuardian(guardian));
        assertEq(feedSwitch.borrowThreshold(), THRESHOLD);
        assertEq(feedSwitch.timelockPeriod(), TIMELOCK);
        assertEq(feedSwitch.switchCompletedAt(), 0);
        assertEq(feedSwitch.decimals(), 18);
        assertEq(feedSwitch.description(), "OneDolaFeedSwitch: Fixed 1e18 or Asset / USD");
        assertTrue(feedSwitch.isFixedPriceActive());
        assertTrue(feedSwitch.useFixedPrice());
        _assertFixed(block.timestamp);
    }

    function test_RejectsWrongDecimals() public {
        MockFeedDescription badFeed = new MockFeedDescription(8, 1e8, "Asset / USD");
        vm.expectRevert(OneDolaFeedSwitch.FeedDecimalsMismatch.selector);
        new OneDolaFeedSwitch(address(badFeed), TIMELOCK, gov, guardian, rwg, THRESHOLD);
    }

    function test_RejectsZeroAddresses() public {
        vm.expectRevert(OneDolaFeedSwitch.ZeroAddress.selector);
        new OneDolaFeedSwitch(address(0), TIMELOCK, gov, guardian, rwg, THRESHOLD);
        vm.expectRevert(OneDolaFeedSwitch.ZeroAddress.selector);
        new OneDolaFeedSwitch(address(underlyingFeed), TIMELOCK, address(0), guardian, rwg, THRESHOLD);
        vm.expectRevert(OneDolaFeedSwitch.ZeroAddress.selector);
        new OneDolaFeedSwitch(address(underlyingFeed), TIMELOCK, gov, address(0), rwg, THRESHOLD);
        vm.expectRevert(OneDolaFeedSwitch.ZeroAddress.selector);
        new OneDolaFeedSwitch(address(underlyingFeed), TIMELOCK, gov, guardian, address(0), THRESHOLD);
    }

    function test_RejectsNonpositiveInitialThreshold() public {
        vm.expectRevert(OneDolaFeedSwitch.InvalidBorrowThreshold.selector);
        new OneDolaFeedSwitch(address(underlyingFeed), TIMELOCK, gov, guardian, rwg, 0);
        vm.expectRevert(OneDolaFeedSwitch.InvalidBorrowThreshold.selector);
        new OneDolaFeedSwitch(address(underlyingFeed), TIMELOCK, gov, guardian, rwg, -1);
    }

    function test_FixedPriceBelowThresholdAndRecovery() public {
        underlyingFeed.changeAnswer(uint256(THRESHOLD - 1));
        _assertFixed(0);
        underlyingFeed.changeAnswer(uint256(THRESHOLD));
        _assertFixed(block.timestamp);
        underlyingFeed.changeAnswer(1.05e18);
        _assertFixed(block.timestamp);
    }

    function test_NonpositiveUnderlyingPriceBlocksBorrowingInFixedMode() public {
        _mockRound(-1, block.timestamp);
        _assertFixed(0);
        _mockRound(0, block.timestamp);
        _assertFixed(0);
        _mockRound(type(int256).min, block.timestamp);
        _assertFixed(0);
    }

    function test_UnderlyingRevertKeepsFixedPricingAndBlocksBorrowing() public {
        vm.mockCallRevert(address(underlyingFeed), abi.encodeWithSignature("latestRoundData()"), "broken");
        _assertFixed(0);
        _toggle();
        _assertFixed(0);
        vm.warp(feedSwitch.switchCompletedAt());
        vm.expectRevert(bytes("broken"));
        feedSwitch.latestRoundData();
        vm.expectRevert(bytes("broken"));
        feedSwitch.latestAnswer();
        _toggle();
        vm.warp(feedSwitch.switchCompletedAt());
        _assertFixed(0);
    }

    function testFuzz_FixedPriceThresholdComparison(int256 price, int256 threshold) public {
        threshold = bound(threshold, 1, type(int256).max);
        vm.prank(rwg);
        feedSwitch.setBorrowThreshold(threshold);
        _mockRound(price, block.timestamp);
        _assertFixed(price < threshold ? 0 : block.timestamp);
    }

    function test_RWGSetsThresholdWithImmediateEffect() public {
        vm.expectEmit(false, false, false, true);
        emit BorrowThresholdChanged(0.99e18);
        vm.prank(rwg);
        feedSwitch.setBorrowThreshold(0.99e18);
        assertEq(feedSwitch.borrowThreshold(), 0.99e18);
        _assertFixed(0);
        vm.prank(rwg);
        feedSwitch.setBorrowThreshold(0.97e18);
        _assertFixed(block.timestamp);
    }

    function test_OnlyRWGCanSetThreshold() public {
        address[3] memory callers = [gov, guardian, user];
        for (uint256 i; i < callers.length; i++) {
            vm.prank(callers[i]);
            vm.expectRevert(OneDolaFeedSwitch.OnlyRWG.selector);
            feedSwitch.setBorrowThreshold(1e18);
        }
    }

    function test_RWGCannotSetNonpositiveThreshold() public {
        vm.startPrank(rwg);
        vm.expectRevert(OneDolaFeedSwitch.InvalidBorrowThreshold.selector);
        feedSwitch.setBorrowThreshold(0);
        vm.expectRevert(OneDolaFeedSwitch.InvalidBorrowThreshold.selector);
        feedSwitch.setBorrowThreshold(-1);
        vm.stopPrank();
    }

    function test_SwitchToUnderlyingHonorsTimelockAndForwardsAllData() public {
        _mockRound(0.9e18, block.timestamp - 60);
        uint256 deadline = block.timestamp + TIMELOCK;
        vm.expectEmit(false, false, false, true);
        emit FeedSwitchInitiated(false, deadline);
        _toggle();
        assertFalse(feedSwitch.useFixedPrice());
        assertTrue(feedSwitch.isFixedPriceActive());
        assertEq(feedSwitch.isFeedSwitchQueued(), TIMELOCK);
        _assertFixed(0);
        vm.warp(deadline - 1);
        assertEq(feedSwitch.isFeedSwitchQueued(), 1);
        _assertFixed(0);
        vm.warp(deadline);
        assertFalse(feedSwitch.isFixedPriceActive());
        assertEq(feedSwitch.isFeedSwitchQueued(), 0);
        _assertUnderlying();
    }

    function test_SwitchBackAtExactDeadlineGetsFullTimelock() public {
        _mockRound(0.9e18, block.timestamp);
        _switchToUnderlying();
        uint256 deadline = block.timestamp + TIMELOCK;
        _toggle();
        assertTrue(feedSwitch.useFixedPrice());
        assertFalse(feedSwitch.isFixedPriceActive());
        assertEq(feedSwitch.switchCompletedAt(), deadline);
        _assertUnderlying();
        vm.warp(deadline - 1);
        _assertUnderlying();
        vm.warp(deadline);
        _assertFixed(0);
    }

    function test_CancelSwitchInBothDirections() public {
        _toggle();
        vm.warp(block.timestamp + TIMELOCK / 2);
        vm.expectEmit(false, false, false, true);
        emit FeedSwitchInitiated(true, block.timestamp);
        _toggle();
        assertEq(feedSwitch.switchCompletedAt(), 0);
        assertEq(feedSwitch.isFeedSwitchQueued(), 0);
        _assertFixed(block.timestamp);
        _switchToUnderlying();
        _toggle();
        vm.warp(block.timestamp + TIMELOCK / 2);
        _toggle();
        assertEq(feedSwitch.switchCompletedAt(), 0);
        assertFalse(feedSwitch.isFixedPriceActive());
        _assertUnderlying();
    }

    function test_ZeroTimelockAllowsRepeatedSameBlockSwitches() public {
        vm.prank(gov);
        feedSwitch.setTimelockPeriod(0);
        for (uint256 i; i < 6; i++) {
            _toggle();
            assertEq(feedSwitch.isFeedSwitchQueued(), 0);
            assertEq(feedSwitch.isFixedPriceActive(), i % 2 == 1);
            if (i % 2 == 0) _assertUnderlying();
            else _assertFixed(block.timestamp);
        }
    }

    function test_SwitchAtTimestampZeroStillQueues() public {
        vm.warp(0);
        _toggle();
        assertEq(feedSwitch.switchCompletedAt(), TIMELOCK);
        assertTrue(feedSwitch.isFixedPriceActive());
        vm.warp(TIMELOCK);
        assertFalse(feedSwitch.isFixedPriceActive());
    }

    function test_ChangingTimelockKeepsQueuedDeadline() public {
        _toggle();
        uint256 deadline = feedSwitch.switchCompletedAt();
        vm.prank(gov);
        feedSwitch.setTimelockPeriod(0);
        assertEq(feedSwitch.switchCompletedAt(), deadline);
        assertTrue(feedSwitch.isFixedPriceActive());
        _toggle(); // Cancel the original switch.
        _toggle(); // New switch uses the updated delay.
        assertFalse(feedSwitch.isFixedPriceActive());
        assertEq(feedSwitch.isFeedSwitchQueued(), 0);
    }

    function test_ThresholdChangesApplyDuringPendingSwitch() public {
        _toggle();
        vm.prank(rwg);
        feedSwitch.setBorrowThreshold(1e18);
        _assertFixed(0);
        vm.warp(feedSwitch.switchCompletedAt());
        _assertUnderlying();
    }

    function test_LiveModePreservesStaleAndNonpositiveData() public {
        _switchToUnderlying();
        _mockRound(0.9e18, 0);
        _assertUnderlying();
        _mockRound(-1, block.timestamp);
        _assertUnderlying();
    }

    function test_DescriptionIsSnapshotAcrossSwitches() public {
        string memory expected = feedSwitch.description();
        vm.mockCall(address(underlyingFeed), abi.encodeWithSignature("description()"), abi.encode("Changed"));
        _switchToUnderlying();
        assertEq(feedSwitch.description(), expected);
        _toggle();
        vm.warp(feedSwitch.switchCompletedAt());
        assertEq(feedSwitch.description(), expected);
    }

    function test_GuardianManagementAndAuthorization() public {
        vm.prank(user);
        vm.expectRevert(OneDolaFeedSwitch.NotGuardian.selector);
        feedSwitch.toggleFeedSwitch();
        vm.prank(rwg);
        vm.expectRevert(OneDolaFeedSwitch.NotGuardian.selector);
        feedSwitch.toggleFeedSwitch();
        vm.startPrank(gov);
        feedSwitch.setGuardian(user, true);
        feedSwitch.setGuardian(guardian, false);
        vm.stopPrank();
        vm.prank(guardian);
        vm.expectRevert(OneDolaFeedSwitch.NotGuardian.selector);
        feedSwitch.toggleFeedSwitch();
        vm.prank(user);
        feedSwitch.toggleFeedSwitch();
        assertEq(feedSwitch.isFeedSwitchQueued(), TIMELOCK);
    }

    function test_GovernanceTransferDoesNotChangeRWG() public {
        vm.prank(gov);
        feedSwitch.setPendingGov(user);
        vm.prank(user);
        feedSwitch.acceptGov();
        assertEq(feedSwitch.gov(), user);
        assertEq(feedSwitch.pendingGov(), address(0));
        vm.prank(gov);
        vm.expectRevert(OneDolaFeedSwitch.NotGov.selector);
        feedSwitch.setTimelockPeriod(0);
        vm.prank(user);
        feedSwitch.setTimelockPeriod(0);
        vm.prank(user);
        vm.expectRevert(OneDolaFeedSwitch.OnlyRWG.selector);
        feedSwitch.setBorrowThreshold(1e18);
        vm.prank(rwg);
        feedSwitch.setBorrowThreshold(1e18);
        _assertFixed(0);
    }

    function test_GovernanceAuthorization() public {
        vm.startPrank(user);
        vm.expectRevert(OneDolaFeedSwitch.NotGov.selector);
        feedSwitch.setPendingGov(user);
        vm.expectRevert(OneDolaFeedSwitch.NotPendingGov.selector);
        feedSwitch.acceptGov();
        vm.expectRevert(OneDolaFeedSwitch.NotGov.selector);
        feedSwitch.setGuardian(user, true);
        vm.expectRevert(OneDolaFeedSwitch.NotGov.selector);
        feedSwitch.setTimelockPeriod(0);
        vm.stopPrank();
    }

    function test_BorrowControllerBlocksBorrowingWhileOracleKeepsFixedPrice() public {
        Oracle oracle = new Oracle(address(this));
        DolaBorrowingRights dbr = new DolaBorrowingRights(10000, "DBR", "DBR", address(this));
        BorrowController controller = new BorrowController(address(this), address(dbr));
        address market = address(0x100);
        address collateral = address(0x200);
        vm.mockCall(market, abi.encodeWithSignature("oracle()"), abi.encode(address(oracle)));
        vm.mockCall(market, abi.encodeWithSignature("collateral()"), abi.encode(collateral));
        oracle.setFeed(collateral, IChainlinkFeed(address(feedSwitch)), 18);
        controller.setStalenessThreshold(market, 1 days);
        controller.setDailyLimit(market, 100e18);
        controller.allow(user);

        assertFalse(controller.isPriceStale(market));
        vm.prank(market);
        assertTrue(controller.borrowAllowed(user, user, 1e18));

        underlyingFeed.changeAnswer(uint256(THRESHOLD - 1));
        assertTrue(controller.isPriceStale(market));
        vm.prank(market);
        assertFalse(controller.borrowAllowed(user, user, 1e18));
        assertEq(oracle.getFeedPrice(collateral), 1e18);
        assertEq(oracle.viewPrice(collateral, 0), 1e18);

        underlyingFeed.changeAnswer(uint256(THRESHOLD));
        assertFalse(controller.isPriceStale(market));
        vm.prank(market);
        assertTrue(controller.borrowAllowed(user, user, 1e18));
    }

    function _toggle() internal {
        vm.prank(guardian);
        feedSwitch.toggleFeedSwitch();
    }

    function _switchToUnderlying() internal {
        _toggle();
        vm.warp(feedSwitch.switchCompletedAt());
    }

    function _mockRound(int256 price, uint256 updatedAt) internal {
        vm.mockCall(
            address(underlyingFeed),
            abi.encodeWithSignature("latestRoundData()"),
            abi.encode(uint80(42), price, uint256(123), updatedAt, uint80(43))
        );
    }

    function _assertFixed(uint256 expectedUpdatedAt) internal view {
        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            feedSwitch.latestRoundData();
        assertEq(roundId, 0);
        assertEq(price, 1e18);
        assertEq(startedAt, 0);
        assertEq(updatedAt, expectedUpdatedAt);
        assertEq(answeredInRound, 0);
        assertEq(feedSwitch.latestAnswer(), price);
    }

    function _assertUnderlying() internal view {
        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            feedSwitch.latestRoundData();
        (
            uint80 expectedRound,
            int256 expectedPrice,
            uint256 expectedStart,
            uint256 expectedUpdate,
            uint80 expectedAnswer
        ) = underlyingFeed.latestRoundData();
        assertEq(roundId, expectedRound);
        assertEq(price, expectedPrice);
        assertEq(startedAt, expectedStart);
        assertEq(updatedAt, expectedUpdate);
        assertEq(answeredInRound, expectedAnswer);
        assertEq(feedSwitch.latestAnswer(), price);
    }
}
