// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {FeedSwitch} from "src/util/FeedSwitch.sol";
import "src/interfaces/IChainlinkFeed.sol";
import {console} from "forge-std/console.sol";
import {MockFeed} from "test/mocks/MockFeed.sol";

contract FeedSwitchTest is Test {
    FeedSwitch feedSwitch;
    MockFeed currentFeed;
    MockFeed beforeMaturityFeed;
    MockFeed afterMaturityFeed;
    address guardian = address(0x2);

    function setUp() public {
        vm.warp(2 days);
        currentFeed = new MockFeed(18, 1e18);
        beforeMaturityFeed = new MockFeed(18, 0.95e18);
        afterMaturityFeed = new MockFeed(18, 0.99e18);
        feedSwitch = new FeedSwitch(
            address(currentFeed),
            address(beforeMaturityFeed),
            address(afterMaturityFeed),
            18 hours,
            block.timestamp + 100 days,
            guardian
        );
    }

    function test_Deployment() public view {
        assertEq(address(feedSwitch.feed()), address(currentFeed));
        assertEq(
            address(feedSwitch.beforeMaturityFeed()),
            address(beforeMaturityFeed)
        );
        assertEq(
            address(feedSwitch.afterMaturityFeed()),
            address(afterMaturityFeed)
        );
        assertEq(feedSwitch.timelockPeriod(), 18 hours);
        assertEq(feedSwitch.maturity(), block.timestamp + 100 days);
        assertEq(feedSwitch.guardian(), guardian);
    }

    function test_InitiateFeedSwitch() public {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchInitiatedAt(), block.timestamp);
    }

    function test_Fail_InitiateFeedSwitchNotGuardian() public {
        vm.expectRevert(FeedSwitch.NotGuardian.selector);
        feedSwitch.initiateFeedSwitch();
    }

    function test_SwitchFeed_before_maturity() public {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        vm.warp(block.timestamp + 1 days);
        feedSwitch.switchFeed();
        assertEq(address(feedSwitch.feed()), address(beforeMaturityFeed));
    }

    function test_SwitchFeed_after_maturity() public {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        vm.warp(block.timestamp + 101 days);
        feedSwitch.switchFeed();
        assertEq(address(feedSwitch.feed()), address(afterMaturityFeed));
    }

    function test_SwitchFeed_before_maturity_and_again_after_maturity() public {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        // Before Maturity
        vm.warp(block.timestamp + 1 days);
        feedSwitch.switchFeed();
        assertEq(address(feedSwitch.feed()), address(beforeMaturityFeed));

        vm.warp(block.timestamp + 101 days);
        // After Maturity
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchInitiatedAt(), block.timestamp);
        vm.warp(block.timestamp + 1 days);
        feedSwitch.switchFeed();
        assertEq(address(feedSwitch.feed()), address(afterMaturityFeed));
        assertEq(feedSwitch.switchInitiatedAt(), 0);
    }

    function test_SwitchFeed_twice_before_maturity_always_return_before_maturity_feed()
        public
    {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        // Before Maturity
        vm.warp(block.timestamp + 1 days);
        feedSwitch.switchFeed();
        assertEq(address(feedSwitch.feed()), address(beforeMaturityFeed));

        // Before Maturity
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        vm.warp(block.timestamp + 50 days);
        feedSwitch.switchFeed();
        assertEq(address(feedSwitch.feed()), address(beforeMaturityFeed));
    }

    function test_switchFeed_twice_after_maturity_always_return_after_maturity_feed()
        public
    {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        vm.warp(block.timestamp + 101 days);
        feedSwitch.switchFeed();
        assertEq(address(feedSwitch.feed()), address(afterMaturityFeed));

        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        vm.warp(block.timestamp + 50 days);
        feedSwitch.switchFeed();
        assertEq(address(feedSwitch.feed()), address(afterMaturityFeed));
    }

    function test_Fail_SwitchFeedNotInitiated() public {
        vm.expectRevert(FeedSwitch.SwitchNotInitiated.selector);
        feedSwitch.switchFeed();
    }

    function test_Fail_switchFeed_before_timelock() public {
        vm.startPrank(guardian);
        feedSwitch.initiateFeedSwitch();
        vm.expectRevert(FeedSwitch.CannotSwitchYet.selector);
        feedSwitch.switchFeed();
    }

    function test_LatestRoundData() public view {
        (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feedSwitch.latestRoundData();
        assertEq(updatedAt, block.timestamp);
        assertEq(uint(price), currentFeed.latestAnswer());
    }

    function test_LatestAnswer() public view {
        int256 price = feedSwitch.latestAnswer();
        assertEq(uint(price), currentFeed.latestAnswer());
    }

    function test_Decimals() public view {
        uint8 decimals = feedSwitch.decimals();
        assertEq(decimals, 18);
    }

    function test_Deploy_Revert_Wrong_Decimals() public {
        MockFeed wrongDecimalsFeed = new MockFeed(8, 1e18);
        vm.expectRevert(FeedSwitch.FeedDecimalsMismatch.selector);
        FeedSwitch feedSwitch = new FeedSwitch(
            address(wrongDecimalsFeed),
            address(beforeMaturityFeed),
            address(afterMaturityFeed),
            18 hours,
            block.timestamp + 100 days,
            guardian
        );

        vm.expectRevert(FeedSwitch.FeedDecimalsMismatch.selector);
        feedSwitch = new FeedSwitch(
            address(currentFeed),
            address(wrongDecimalsFeed),
            address(afterMaturityFeed),
            18 hours,
            block.timestamp + 100 days,
            guardian
        );

        vm.expectRevert(FeedSwitch.FeedDecimalsMismatch.selector);
        feedSwitch = new FeedSwitch(
            address(currentFeed),
            address(beforeMaturityFeed),
            address(wrongDecimalsFeed),
            18 hours,
            block.timestamp + 100 days,
            guardian
        );
    }
}
