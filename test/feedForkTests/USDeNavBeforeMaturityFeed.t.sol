// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {USDeNavBeforeMaturityFeed} from "src/feeds/USDeNavBeforeMaturityFeed.sol";
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

contract USDeNavBeforeMaturityFeedTest is Test {
    USDeNavBeforeMaturityFeed feed;
    ChainlinkBasePriceFeed sUSDeWrappedFeed;
    address sUSDeFeed = address(0xFF3BC18cCBd5999CE63E788A1c250a88626aD099);
    IERC4626 sUSDe = IERC4626(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    PendleSparkLinearDiscountOracleFactory navFactory = PendleSparkLinearDiscountOracleFactory(0xA9A924A4BB95509F77868E086154C25e934F6171);
    address pendlePT = address(0xb7de5dFCb74d25c2f21841fbd6230355C50d9308); // PT sUSDe 29 May 25

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        sUSDeWrappedFeed = new ChainlinkBasePriceFeed(
            gov,
            sUSDeFeed,
            address(0),
            24 hours
        );
        address navFeed = navFactory.createWithPt(pendlePT, 0.2 ether); 
        feed = new USDeNavBeforeMaturityFeed(
            address(sUSDeWrappedFeed),
            address(sUSDe),
            navFeed
        );
    }

    function test_decimals() public {
        assertEq(feed.sUSDeFeed().decimals(), 18);
        assertEq(feed.sUSDe().decimals(), 18);
        assertEq(feed.decimals(), 18);
    }

    function test_description() public {
        string memory expected = string(
            abi.encodePacked(
                "USDe/USD Feed using sUSDe Chainlink feed and sUSDe/USDe rate with NAV"
            )
        );
        assertEq(feed.description(), expected);
    }

    function test_latestRoundData() public {
        (
            uint80 roundId,
            int256 USDeUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        (
            uint80 roundIdCl,
            int256 sUSDeUsdPrice,
            uint startedAtCl,
            uint updatedAtCl,
            uint80 answeredInRoundCl
        ) = sUSDeWrappedFeed.latestRoundData();
        assertEq(roundId, roundIdCl);
        assertEq(startedAt, startedAtCl);
        assertEq(updatedAt, updatedAtCl);
        assertEq(answeredInRound, answeredInRoundCl);

        int256 USDeUsdPriceEst = (sUSDeUsdPrice * 1e18) /
            int256(sUSDe.convertToAssets(1e18));
        (,int256 navDiscountedPrice,,,) = feed.navFeed().latestRoundData();
        int256 discountPrice = (USDeUsdPriceEst * navDiscountedPrice) / 1e18;
        assertEq(discountPrice, USDeUsdPrice);
    }

    function test_latestAnswer() public {
        int256 USDeUsdPrice = feed.latestAnswer();
        int256 USDeUsdPriceEst = (sUSDeWrappedFeed.latestAnswer() * 1e18) /
            int256(sUSDe.convertToAssets(1e18));
        (,int256 navDiscountedPrice,,,) = feed.navFeed().latestRoundData();
        int256 discountPrice = (USDeUsdPriceEst * navDiscountedPrice) / 1e18;
        assertEq(discountPrice, USDeUsdPrice);
    }

    function test_NAV() public {
        uint256 maturity = INavFeed(address(feed.navFeed())).maturity();
        vm.warp(maturity - 365 days/6); //2 months before expiry
        uint256 discount = INavFeed(address(feed.navFeed())).getDiscount(365 days/6);
        assertApproxEqAbs(discount, 0.0333 ether, 0.0001 ether);
        (,int256 navDiscountedPrice,,,) = feed.navFeed().latestRoundData();
        assertApproxEqAbs(navDiscountedPrice, 0.966666666 ether, 0.00000001 ether);
        int256 USDeUsdPrice = feed.latestAnswer();
        int256 USDeUsdPriceEst = (sUSDeWrappedFeed.latestAnswer() * 1e18) /
            int256(sUSDe.convertToAssets(1e18));
         int256 discountPrice = (USDeUsdPriceEst * navDiscountedPrice) / 1e18;
        assertEq(discountPrice, USDeUsdPrice);

        vm.warp(maturity - 365 days/12); //1 months before expiry
        uint256 discount2 = INavFeed(address(feed.navFeed())).getDiscount(365 days/12);
        assertApproxEqAbs(discount2, 0.016666666 ether, 0.0001 ether);
        (,int256 navDiscountedPrice2,,,) = feed.navFeed().latestRoundData();
        assertApproxEqAbs(navDiscountedPrice2, 0.983333333 ether, 0.00000001 ether);
        int256 USDeUsdPrice2 = feed.latestAnswer();
        int256 USDeUsdPriceEst2 = (sUSDeWrappedFeed.latestAnswer() * 1e18) /
            int256(sUSDe.convertToAssets(1e18));
         int256 discountPrice2 = (USDeUsdPriceEst2 * navDiscountedPrice2) / 1e18;
        assertEq(discountPrice2, USDeUsdPrice2);
        // Check if the discount is decreasing
        assertGt(discount, discount2);
        // Check if the price is increasing
        assertLt(navDiscountedPrice, navDiscountedPrice2);
        assertLt(USDeUsdPrice, USDeUsdPrice2);
        assertLt(discountPrice, discountPrice2);
    }
    function test_STALE_sUSDeFeed() public {
        vm.mockCall(
            address(sUSDeFeed),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 1.1e8, 0, 0, 0)
        );
        (
            uint80 roundId,
            int256 USDeUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        int256 USDeUsdPriceEst = (sUSDeWrappedFeed.latestAnswer() * 1e18) /
            int256(sUSDe.convertToAssets(1e18));
        (,int256 navDiscountedPrice,,,) = feed.navFeed().latestRoundData();
        int256 discountPrice = (USDeUsdPriceEst * navDiscountedPrice) / 1e18;
        assertEq(roundId, 0);
        assertEq(USDeUsdPrice, discountPrice);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
    }

    function test_maturity_passed() public {
        uint256 maturity = INavFeed(address(feed.navFeed())).maturity();
        vm.warp(maturity);
        address navFeed = navFactory.createWithPt(pendlePT, 0.2 ether); 
        vm.expectRevert(USDeNavBeforeMaturityFeed.MaturityPassed.selector);
        feed = new USDeNavBeforeMaturityFeed(
            address(sUSDeWrappedFeed),
            address(sUSDe),
            navFeed
        );
    }
}
