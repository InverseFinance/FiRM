// SPDX-License-Identifier: UNLICENSED 
pragma solidity ^0.8.13; 
 
import "forge-std/Test.sol"; 
import {styCRVPriceFeed, I4626} from "src/feeds/styCRVPriceFeed.sol"; 

interface ICurvePool {
    function get_p() view external returns(uint);
    function price_oracle() view external returns(uint);
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns(uint);
}

interface IERC20 is I4626{
    function approve(address to, uint amount) external;
    function balanceOf(address holder) external returns(uint);
}

contract styCrvFeedFork is Test {

    ICurvePool curvePool = ICurvePool(0x453D92C7d4263201C69aACfaf589Ed14202d83a4);
    IERC20 styCrv = IERC20(0x27B5739e22ad9033bcBf192059122d163b60349D);
    address styCrvHolder = 0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e;
    styCRVPriceFeed feed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        feed = new styCRVPriceFeed();
        deal(styCrvHolder, address(styCrv), 1000 ether);
    }

    function testNominalCase() public {
        (uint80 clRoundId, int256 crvUsdPrice, uint clStartedAt, uint clUpdatedAt,  uint80 clAnsweredInRound) = feed.crvToUsd().latestRoundData();
        (uint80 roundId, int256 styCrvUsdPrice, uint startedAt, uint updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);

        uint256 ema_price = curvePool.price_oracle();
        uint ema_pps_adjusted = ema_price * styCrv.pricePerShare() / 10**18;
        assertEq(crvUsdPrice * int256(ema_pps_adjusted) / 10**8, styCrvUsdPrice);
        assertGt(crvUsdPrice * 10**10, styCrvUsdPrice * 10**18 / int(styCrv.pricePerShare()));
        assertLt(crvUsdPrice, styCrvUsdPrice);
    }

    function testPriceFloorCase() public {
        vm.prank(feed.gov());
        feed.setMinCrvPerstyCrvRatio(10**18-1);
        (uint80 clRoundId, int256 crvUsdPrice, uint clStartedAt, uint clUpdatedAt,  uint80 clAnsweredInRound) = feed.crvToUsd().latestRoundData();
        (uint80 roundId, int256 styCrvUsdPrice, uint startedAt, uint updatedAt, uint80 answeredInRound) = feed.latestRoundData();

        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);

        uint256 ema_price = curvePool.price_oracle();
        assertLt(crvUsdPrice * int256(ema_price) / 10**8, styCrvUsdPrice);
        assertEq(crvUsdPrice * (10**18-1) / 10**8, styCrvUsdPrice);
        assertGt(crvUsdPrice * 10**18, styCrvUsdPrice);
        assertLt(crvUsdPrice, styCrvUsdPrice);
    }

    function testSetMinCrvPerstyCRVRatio_accessControl() public {
        vm.prank(feed.gov());
        uint newRatio = 10**18 - 10**17;
        feed.setMinCrvPerstyCrvRatio(newRatio);
        assertEq(feed.minCrvPerstyCrvRatio(), newRatio);

        vm.prank(feed.guardian());
        newRatio = 10**18 - 10**17*2;
        feed.setMinCrvPerstyCrvRatio(newRatio);
        assertEq(feed.minCrvPerstyCrvRatio(), newRatio);

        vm.prank(address(0xA));
        vm.expectRevert("ONLY GOV OR GUARDIAN");
        newRatio = 10**18 - 10**17*3;
        feed.setMinCrvPerstyCrvRatio(newRatio);
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

