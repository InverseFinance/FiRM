// SPDX-License-Identifier: UNLICENSED 
pragma solidity ^0.8.13; 
 
import "forge-std/Test.sol"; 
import {ConvexFraxSharePriceFeed} from "../../feeds/ConvexFraxSharePriceFeed.sol"; 

interface ICurvePool {
    function get_p() view external returns(uint);
    function price_oracle() view external returns(uint);
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns(uint);
}

interface IERC20 {
    function approve(address to, uint amount) external;
    function balanceOf(address holder) external returns(uint);
}

contract CvxFxsFeedFork is Test {

    ICurvePool curvePool = ICurvePool(0xc629a01eC23AB04E1050500A3717A2a5c0701497);
    IERC20 cvxFxs = IERC20(0xFEEf77d3f69374f66429C91d732A244f074bdf74);
    ConvexFraxSharePriceFeed feed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        feed = new ConvexFraxSharePriceFeed();
    }

    function testNominalCase() public {
        (uint80 clRoundId, int256 fxsUsdPrice, uint clStartedAt, uint clUpdatedAt,  uint80 clAnsweredInRound) = feed.fxsToUsd().latestRoundData();
        (uint80 roundId, int256 cvxFxsUsdPrice, uint startedAt, uint updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);

        uint256 ema_price = curvePool.price_oracle();
        assertEq(fxsUsdPrice * int256(ema_price) / 10**8, cvxFxsUsdPrice);
        assertGt(fxsUsdPrice * 10**10, cvxFxsUsdPrice);
        assertLt(fxsUsdPrice, cvxFxsUsdPrice);
    }

    function testPriceFloorCase() public {
        vm.prank(feed.gov());
        feed.setMinFxsPerCvxFxsRatio(10**18-1);
        (uint80 clRoundId, int256 fxsUsdPrice, uint clStartedAt, uint clUpdatedAt,  uint80 clAnsweredInRound) = feed.fxsToUsd().latestRoundData();
        (uint80 roundId, int256 cvxFxsUsdPrice, uint startedAt, uint updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);

        uint256 ema_price = curvePool.price_oracle();
        assertLt(fxsUsdPrice * int256(ema_price) / 10**8, cvxFxsUsdPrice);
        assertEq(fxsUsdPrice * (10**18-1) / 10**8, cvxFxsUsdPrice);
        assertGt(fxsUsdPrice * 10**18, cvxFxsUsdPrice);
        assertLt(fxsUsdPrice, cvxFxsUsdPrice);
    }

    function testSetMinFxsPerCvxFxsRatio_accessControl() public {
        vm.prank(feed.gov());
        uint newRatio = 10**18 - 10**17;
        feed.setMinFxsPerCvxFxsRatio(newRatio);
        assertEq(feed.minFxsPerCvxFxsRatio(), newRatio);

        vm.prank(feed.guardian());
        newRatio = 10**18 - 10**17*2;
        feed.setMinFxsPerCvxFxsRatio(newRatio);
        assertEq(feed.minFxsPerCvxFxsRatio(), newRatio);

        vm.prank(address(0xA));
        vm.expectRevert("ONLY GOV OR GUARDIAN");
        newRatio = 10**18 - 10**17*3;
        feed.setMinFxsPerCvxFxsRatio(newRatio);
    }

    function testSetGuardian_accessControl() public {
        vm.prank(feed.guardian());
        vm.expectRevert("ONLY GOV");
        feed.setGuardian(address(0xA));

        vm.prank(address(0xA));
        vm.expectRevert("ONLY GOV");
        feed.setGuardian(address(0xA));

        vm.prank(feed.gov());
        feed.setGuardian(address(0xA));
        assertEq(feed.guardian(), address(0xA));
    }

    function testSetGov_accessControl() public {
        vm.prank(feed.guardian());
        vm.expectRevert("ONLY GOV");
        feed.setGov(address(0xA));

        vm.prank(address(0xA));
        vm.expectRevert("ONLY GOV");
        feed.setGov(address(0xA));

        vm.prank(feed.gov());
        feed.setGov(address(0xA));
        assertEq(feed.gov(), address(0xA));
    }
}

