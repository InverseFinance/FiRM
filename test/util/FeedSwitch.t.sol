// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {FeedSwitch} from "src/util/FeedSwitch.sol";
import "src/interfaces/IChainlinkFeed.sol";
import {console} from "forge-std/console.sol";
import {MockFeed} from "test/mocks/MockFeed.sol";

contract FeedSwitchTest is Test {
    FeedSwitch feedSwitch;
    MockFeed initialFeed;
    MockFeed beforeMaturityFeed;
    MockFeed afterMaturityFeed;
    address guardian = address(0x2);

    function setUp() public {
        vm.warp(2 days);
        initialFeed = new MockFeed(18, 1e18);
        beforeMaturityFeed = new MockFeed(18, 0.95e18);
        afterMaturityFeed = new MockFeed(18, 0.99e18);
        feedSwitch = new FeedSwitch(
            address(initialFeed),
            address(beforeMaturityFeed),
            address(afterMaturityFeed),
            18 hours,
            block.timestamp + 100 days,
            guardian
        );
    }

    function test_Deployment() public view {
        assertEq(address(feedSwitch.feed()), address(initialFeed));
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
        assertEq(
            feedSwitch.switchCompletedAt(),
            block.timestamp + feedSwitch.timelockPeriod()
        );
    }

    function test_Fail_InitiateFeedSwitchNotGuardian() public {
        vm.expectRevert(FeedSwitch.NotGuardian.selector);
        feedSwitch.initiateFeedSwitch();
    }

    function test_SwitchFeed_before_maturity() public {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );
        vm.warp(block.timestamp + 0.5 days);
        int256 price = feedSwitch.latestAnswer();
        assertEq(uint(price), 1e18, "initial feed");
        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );
        price = feedSwitch.latestAnswer();
        assertEq(uint(price), 0.95e18);
    }

    function test_SwitchFeed_after_maturity_after_switch() public {
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );
        vm.warp(block.timestamp + 101 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(afterMaturityFeed.latestAnswer())
        );
    }

    function test_SwitchFeed_after_maturity() public {
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );

        vm.warp(block.timestamp + 101 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(afterMaturityFeed.latestAnswer())
        );
    }

    function test_SwitchFeed_before_maturity_and_after_maturity() public {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );
        // Before Maturity
        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );
        vm.warp(block.timestamp + 101 days);
        // After Maturity
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(afterMaturityFeed.latestAnswer())
        );
    }

    function test_Cancel_feed_switch() public {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp + 18 hours);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );
        vm.warp(block.timestamp + 0.5 days);

        // Cancel the feed switch
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), 0);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer()),
            "before feed switch"
        );
        assertEq(feedSwitch.switchCompletedAt(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );
    }

    function test_Cancel_feed_switch_and_reswitch() public {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp + 18 hours);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );
        vm.warp(block.timestamp + 0.5 days);

        // Cancel the feed switch
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), 0);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer()),
            "before feed switch"
        );
        assertEq(feedSwitch.switchCompletedAt(), 0);
        // After the feed is canceled, it keeps using the initialFeed
        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );

        // Initiate a feed switch again
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp + 18 hours);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );

        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );
    }

    function test_Cancel_feed_switch_with_beforeMaturityFeed_and_reswitch()
        public
    {
        // Switch feed to beforeMaturityFeed
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp + 18 hours);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );
        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );

        // Initiate a feed switch again
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp + 18 hours);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );

        // Cancel it when it is in the timelock period and keep using beforeMaturityFeed
        vm.warp(block.timestamp + 0.5 days);
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), 0);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );

        // Initiate a feed switch again
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp + 18 hours);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );

        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );
    }

    function test_SwitchFeed_twice_before_maturity() public {
        // Previous Feed is not initialized and current feed is initialFeed
        assertEq(address(feedSwitch.previousFeed()), address(0));
        assertEq(address(feedSwitch.feed()), address(initialFeed));
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );
        // Initiate a feed switch
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        // Feed switch initiated
        assertEq(address(feedSwitch.previousFeed()), address(initialFeed));
        assertEq(address(feedSwitch.feed()), address(beforeMaturityFeed));
        // Before timelock period, initialFeed is still the one used
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );
        // After timelock period, beforeMaturityFeed is used
        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );

        // After the switch is completed, the feed is switched back to initialFeed
        assertEq(address(feedSwitch.previousFeed()), address(initialFeed));
        assertEq(address(feedSwitch.feed()), address(beforeMaturityFeed));

        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(
            address(feedSwitch.previousFeed()),
            address(beforeMaturityFeed)
        );
        assertEq(address(feedSwitch.feed()), address(initialFeed));
        // Before timelock period, beforeMaturityFeed is still the one used
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );
        vm.warp(block.timestamp + 1 days);
        // After timelock period, initialFeed is used
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(initialFeed.latestAnswer())
        );
    }

    function test_Fail_initiateFeedSwitch_after_maturity() public {
        vm.warp(block.timestamp + 101 days);
        vm.prank(guardian);
        vm.expectRevert(FeedSwitch.MaturityPassed.selector);
        feedSwitch.initiateFeedSwitch();
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
        assertEq(uint(price), initialFeed.latestAnswer());
    }

    function test_LatestAnswer() public view {
        int256 price = feedSwitch.latestAnswer();
        assertEq(uint(price), initialFeed.latestAnswer());
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
            address(initialFeed),
            address(wrongDecimalsFeed),
            address(afterMaturityFeed),
            18 hours,
            block.timestamp + 100 days,
            guardian
        );

        vm.expectRevert(FeedSwitch.FeedDecimalsMismatch.selector);
        feedSwitch = new FeedSwitch(
            address(initialFeed),
            address(beforeMaturityFeed),
            address(wrongDecimalsFeed),
            18 hours,
            block.timestamp + 100 days,
            guardian
        );
    }
}
