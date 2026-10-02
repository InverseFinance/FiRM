// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {PTDiscountedNAVFeed} from "src/feeds/PTDiscountedNAVFeed.sol";
import {ERC4626Feed} from "src/feeds/ERC4626Feed.sol";
import {ChainlinkBasePriceFeed, IChainlinkFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "forge-std/console.sol";

interface PendleSparkLinearDiscountOracleFactory {
      function createWithPt(address pt, uint256 baseDiscountPerYear) external returns (address);
}

interface INavFeed {
    function getDiscount(uint256 timeLeft) external view returns (uint256) ;
    function maturity() external view returns (uint256);
    function decimals() external view returns (uint8);
}

contract USDePTDiscountedNAVFeedTest is Test {
    PTDiscountedNAVFeed feed;
    ChainlinkBasePriceFeed USDeWrappedFeed;
    address USDeFeed = address(0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    address pendlePT = address(0xb7de5dFCb74d25c2f21841fbd6230355C50d9308); // PT sUSDe 29 May 25
    uint discountRate = 0.2 ether;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        USDeWrappedFeed = new ChainlinkBasePriceFeed(
            gov,
            USDeFeed,
            address(0),
            24 hours
        );
        feed = new PTDiscountedNAVFeed(
            address(USDeWrappedFeed),
            pendlePT,
            discountRate
        );
    }

    function test_decimals() public {
        assertEq(feed.underlyingFeed().decimals(), 18);
        assertEq(feed.decimals(), 18);
    }

    function test_description() public {
        string memory expected = string(
            abi.encodePacked(
                "USDe / USD with yearly discount rate of 200000000000000000"
            )
        );
        assertEq(feed.description(), expected);
    }

    function test_latestRoundData() public {
        (
            uint80 roundId,
            int256 discountedPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        (
            uint80 roundIdCl,
            int256 USDePrice,
            uint startedAtCl,
            uint updatedAtCl,
            uint80 answeredInRoundCl
        ) = USDeWrappedFeed.latestRoundData();
        assertEq(roundId, roundIdCl, "roundId not equal");
        assertEq(startedAt, startedAtCl, "start timestamp not equal");
        assertEq(updatedAt, updatedAtCl, "updated at not equal");
        assertEq(answeredInRound, answeredInRoundCl, "answered round not equal");
        
        if(block.timestamp > feed.maturity()){
            assertEq(discountedPrice, USDePrice, "discountedPrice not eq before maturity");
        } else {
            assertLt(discountedPrice, USDePrice, "discounted price not less after maturity");
        }
    }

    function test_latestAnswer() public {
        int256 USDePrice = USDeWrappedFeed.latestAnswer();
        int256 discountedPrice = feed.latestAnswer();

        if(block.timestamp < feed.maturity()){
            assertLt(discountedPrice, USDePrice);
        } else {
            assertEq(discountedPrice, USDePrice);
        }

        vm.warp(feed.maturity() + 1);

        USDePrice = USDeWrappedFeed.latestAnswer();
        discountedPrice = feed.latestAnswer();

        assertEq(discountedPrice, USDePrice);
    }

    function test_NAV_fuzzed(uint secondsBeforeMaturity) public {
        secondsBeforeMaturity = secondsBeforeMaturity % 1824 days; //5 years - 1 day
        uint256 maturity = feed.maturity();
        vm.warp(maturity - secondsBeforeMaturity);
        uint256 discount = feed.getDiscount();
        uint timeLeft = maturity - block.timestamp;
        uint expectedDiscount = discountRate * timeLeft / 365 days;
        int256 USDePrice = USDeWrappedFeed.latestAnswer();
        int256 discountedPrice = feed.latestAnswer();
        int256 expectedDiscountedPrice = USDePrice * int((1e18 - expectedDiscount)) / 1e18;
        
        assertApproxEqAbs(discount, expectedDiscount, 0.0001 ether);
        assertApproxEqAbs(feed.latestAnswer(), expectedDiscountedPrice, 0.00000001 ether);
        if(secondsBeforeMaturity > 12){
            assertLt(discountedPrice, USDePrice);
        }
    }

    function test_STALE_sUSDeFeed() public {
        vm.mockCall(
            address(USDeFeed),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 1.1e8, 0, 0, 0)
        );
        (
            uint80 roundId,
            int256 discountedPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        int256 USDePrice = USDeWrappedFeed.latestAnswer();
        assertEq(roundId, 0);
        assertLt(discountedPrice, USDePrice);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
    }

    function test_maturity_passed() public {
        vm.warp(feed.maturity() + 1);
        vm.expectRevert(PTDiscountedNAVFeed.MaturityPassed.selector);
        feed = new PTDiscountedNAVFeed(
            address(USDeWrappedFeed),
            pendlePT,
            discountRate
        );
    }
}
