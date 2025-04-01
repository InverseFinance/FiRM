// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {FeedSwitch, IPendlePT, IChainlinkFeed} from "src/util/FeedSwitch.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";
import {console} from "forge-std/console.sol";
import {MockFeed} from "test/mocks/MockFeed.sol";


contract MockPendlePT {
    function expiry() external pure returns (uint256) {
        return 100;
    }
}


interface INavFeed {
    function getDiscount(uint256 timeLeft) external view returns (uint256) ;
    function maturity() external view returns (uint256);
    function decimals() external view returns (uint8);
}

abstract contract BaseFeedSwitchNavForkTest is Test, ConfigAddr {
    FeedSwitch feedSwitch;
    IChainlinkFeed navFeed;
    IChainlinkFeed beforeMaturityFeed;
    IChainlinkFeed afterMaturityFeed;
    address guardian = pauseGuardian;
    address pendlePT = address(0xb7de5dFCb74d25c2f21841fbd6230355C50d9308);
    uint256 baseDiscount;
    uint256 timeLockPeriod = 18 hours;

    function initialize(address _beforeMaturityFeed, address _afterMaturityFeed, address _pendlePT, uint256 _baseDiscount, address _navFeed) public {
        afterMaturityFeed = IChainlinkFeed(_afterMaturityFeed);
        pendlePT = _pendlePT;
        baseDiscount = _baseDiscount;
        navFeed = IChainlinkFeed(_navFeed); 
        beforeMaturityFeed = IChainlinkFeed(_beforeMaturityFeed);
        feedSwitch = new FeedSwitch(
            address(navFeed),
            address(beforeMaturityFeed),
            address(afterMaturityFeed),
            timeLockPeriod,
            pendlePT,
            guardian
        );
    }
    function test_Deployment() public view {
        assertEq(address(feedSwitch.feed()), address(navFeed));
        assertEq(
            address(feedSwitch.beforeMaturityFeed()),
            address(beforeMaturityFeed)
        );
        assertEq(
            address(feedSwitch.afterMaturityFeed()),
            address(afterMaturityFeed)
        );
        assertEq(feedSwitch.timelockPeriod(), 18 hours);
        assertEq(feedSwitch.maturity(), IPendlePT(pendlePT).expiry());
        assertEq(feedSwitch.guardian(), guardian);
        (bool isQueued, uint256 timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);

        assertEq(INavFeed(address(navFeed)).maturity(), IPendlePT(pendlePT).expiry());
        assertEq(INavFeed(address(navFeed)).decimals(), 18);
    }

    function test_updateAt_NAVFeed() public {
        INavFeed nav = INavFeed(address(navFeed));
        vm.warp(nav.maturity() - 365 days);
        uint256 discount = nav.getDiscount(365 days);
        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = navFeed.latestRoundData();
        assertEq(uint(price), 1 ether - discount);
        assertEq(startedAt, 0);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }
    function test_NavDiscount() public {
        INavFeed nav = INavFeed(address(navFeed));
        
        uint256 discount = nav.getDiscount(365 days);
        assertEq(discount, baseDiscount);
        // 1 year before maturity
        vm.warp(nav.maturity() - 365 days);
        assertEq(uint(feedSwitch.latestAnswer()), 1 ether - discount);

        discount = nav.getDiscount(365 days / 2);
        // 6 months before maturity
        vm.warp(block.timestamp + 365 days / 2);
        assertEq(discount, baseDiscount / 2);
        assertEq(uint(feedSwitch.latestAnswer()), 1 ether - discount);

        discount = nav.getDiscount(0);
        // At maturity
        vm.warp(nav.maturity());
        assertEq(discount, 0);
        assertNotEq(uint(feedSwitch.latestAnswer()), 1 ether - discount);
        // Already uses after maturity feed
        assertEq(uint(feedSwitch.latestAnswer()), uint(afterMaturityFeed.latestAnswer()));    
    }

    function test_InitiateFeedSwitch() public {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(
            feedSwitch.switchCompletedAt(),
            block.timestamp + feedSwitch.timelockPeriod()
        );
        (bool isQueued, uint256 timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, true);
        assertEq(timeLeft, feedSwitch.timelockPeriod());
    }

    function test_Fail_InitiateFeedSwitchNotGuardian() public {
        vm.expectRevert(FeedSwitch.NotGuardian.selector);
        feedSwitch.initiateFeedSwitch();
    }

    function test_SwitchFeed_before_maturity() public {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        (,int256 navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );
        (bool isQueued, uint256 timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, true);
        assertEq(timeLeft, feedSwitch.timelockPeriod());

        vm.warp(block.timestamp + 0.5 days);
        int256 price = feedSwitch.latestAnswer();
        (,navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(uint(price), uint(navFeedPrice), "initial feed");
        // Not yet switched
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, true);
        assertEq(timeLeft, feedSwitch.timelockPeriod() - 0.5 days);

        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );

        // After switch, not queued anymore
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);
    }

    function test_SwitchFeed_after_maturity_after_switch() public {
        (,int256 navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );
        (bool isQueued, uint256 timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);
        vm.warp(IPendlePT(pendlePT).expiry() + 1);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(afterMaturityFeed.latestAnswer())
        );
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);
    }

    function test_SwitchFeed_after_maturity() public {
        (,int256 navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );
        (bool isQueued, uint256 timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);

        vm.warp(IPendlePT(pendlePT).expiry() + 1);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(afterMaturityFeed.latestAnswer())
        );
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);
    }

    function test_SwitchFeed_before_maturity_and_after_maturity() public {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        (,int256 navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );
        (bool isQueued, uint256 timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, true);
        assertEq(timeLeft, feedSwitch.timelockPeriod());

        // Before Maturity
        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );

        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);

        vm.warp(IPendlePT(pendlePT).expiry() + 1);
        // After Maturity
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(afterMaturityFeed.latestAnswer())
        );
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);
    }

    function test_Cancel_feed_switch() public {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp + 18 hours);
        (,int256 navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );
        vm.warp(block.timestamp + 0.5 days);

        (bool isQueued, uint timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, true);
        assertEq(timeLeft, feedSwitch.timelockPeriod() - 0.5 days);

        // Cancel the feed switch
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), 0);
        (,navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice),
            "before feed switch"
        );
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(feedSwitch.switchCompletedAt(), 0);
        (,navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);
    }

    function test_Cancel_feed_switch_and_reswitch() public {
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp + 18 hours);
        (,int256 navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );
        vm.warp(block.timestamp + 0.5 days);
        (bool isQueued, uint256 timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, true);
        assertEq(timeLeft, feedSwitch.timelockPeriod() - 0.5 days);

        // Cancel the feed switch
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), 0);
        (,navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice),
            "before feed switch"
        );
        assertEq(feedSwitch.switchCompletedAt(), 0);
        // Not queued anymore
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);

        // After the feed is canceled, it keeps using the navFeed
        vm.warp(block.timestamp + 1 days);
        (,navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);
        // Initiate a feed switch again
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp + 18 hours);
        (,navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );

        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, true);
        assertEq(timeLeft, feedSwitch.timelockPeriod());

        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );
        // Feed switched so not queued anymore
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);
    }

    function test_Cancel_feed_switch_with_beforeMaturityFeed_and_reswitch()
        public
    {
        // Switch feed to beforeMaturityFeed
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp + 18 hours);
        (,int256 navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );
        (bool isQueued, uint256 timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, true);
        assertEq(timeLeft, feedSwitch.timelockPeriod());

        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);

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
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, true);
        assertEq(timeLeft, feedSwitch.timelockPeriod() - 0.5 days);

        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), 0);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);
        // Initiate a feed switch again
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(feedSwitch.switchCompletedAt(), block.timestamp + 18 hours);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, true);
        assertEq(timeLeft, feedSwitch.timelockPeriod());

        vm.warp(block.timestamp + 1 days);
        (,navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);
    }

    function test_SwitchFeed_twice_before_maturity() public {
        // Previous Feed is not initialized and current feed is navFeed
        assertEq(address(feedSwitch.previousFeed()), address(0));
        assertEq(address(feedSwitch.feed()), address(navFeed));
        (,int256 navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );
        // Initiate a feed switch
        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        // Feed switch initiated
        assertEq(address(feedSwitch.previousFeed()), address(navFeed));
        assertEq(address(feedSwitch.feed()), address(beforeMaturityFeed));
        // Before timelock period, navFeed is still the one used
        (,navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );
        (bool isQueued, uint timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, true);
        assertEq(timeLeft, feedSwitch.timelockPeriod());

        // After timelock period, beforeMaturityFeed is used
        vm.warp(block.timestamp + 1 days);
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);

        // After the switch is completed, the feed is switched back to navFeed
        assertEq(address(feedSwitch.previousFeed()), address(navFeed));
        assertEq(address(feedSwitch.feed()), address(beforeMaturityFeed));

        vm.prank(guardian);
        feedSwitch.initiateFeedSwitch();
        assertEq(
            address(feedSwitch.previousFeed()),
            address(beforeMaturityFeed)
        );
        assertEq(address(feedSwitch.feed()), address(navFeed));
        // Before timelock period, beforeMaturityFeed is still the one used
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(beforeMaturityFeed.latestAnswer())
        );
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, true);
        assertEq(timeLeft, feedSwitch.timelockPeriod());

        vm.warp(block.timestamp + 1 days);
        // After timelock period, navFeed is used
        (,navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(
            uint(feedSwitch.latestAnswer()),
            uint(navFeedPrice)
        );
        (isQueued, timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);
    }

    function test_Fail_initiateFeedSwitch_after_maturity() public {
        vm.warp(IPendlePT(pendlePT).expiry() + 1);
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
        (,int256 navFeedPrice,, uint256 updatedAtNav,) = navFeed.latestRoundData();
     
        assertEq(updatedAt, updatedAtNav);
        assertEq(uint(price), uint(navFeedPrice));
    }

    function test_LatestAnswer() public view {
        int256 price = feedSwitch.latestAnswer();
        (,int256 navFeedPrice,,,) = navFeed.latestRoundData();
        assertEq(uint(price), uint(navFeedPrice));
    }

    function test_Decimals() public view {
        uint8 decimals = feedSwitch.decimals();
        assertEq(decimals, 18);
    }

    function test_isFeedSwitchQueued() public view {
        (bool isQueued, uint256 timeLeft) = feedSwitch.isFeedSwitchQueued();
        assertEq(isQueued, false);
        assertEq(timeLeft, 0);
    }

    function test_Deploy_Revert_Wrong_Decimals() public {
        MockFeed wrongDecimalsFeed = new MockFeed(8, 1e18);
        vm.expectRevert(FeedSwitch.FeedDecimalsMismatch.selector);
        FeedSwitch feedSwitch2 = new FeedSwitch(
            address(wrongDecimalsFeed),
            address(beforeMaturityFeed),
            address(afterMaturityFeed),
            18 hours,
            pendlePT,
            guardian
        );

        vm.expectRevert(FeedSwitch.FeedDecimalsMismatch.selector);
        feedSwitch2 = new FeedSwitch(
            address(navFeed),
            address(wrongDecimalsFeed),
            address(afterMaturityFeed),
            18 hours,
            pendlePT,
            guardian
        );

        vm.expectRevert(FeedSwitch.FeedDecimalsMismatch.selector);
        feedSwitch2 = new FeedSwitch(
            address(navFeed),
            address(beforeMaturityFeed),
            address(wrongDecimalsFeed),
            18 hours,
            pendlePT,
            guardian
        );
    }

    function test_Deploy_maturity_in_past() public {
        MockPendlePT MockPendlePT = new MockPendlePT();
        vm.expectRevert(FeedSwitch.MaturityInPast.selector);
        FeedSwitch feedSwitch2 = new FeedSwitch(
            address(navFeed),
            address(beforeMaturityFeed),
            address(afterMaturityFeed),
            18 hours,
            address(MockPendlePT),
            guardian
        );
    }
}
