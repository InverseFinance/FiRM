// SPDX-License-Identifier: UNLICENSED 
pragma solidity ^0.8.13; 
 
import "forge-std/Test.sol"; 
import {ConvexCurvePriceFeed} from "../../feeds/ConvexCurvePriceFeed.sol"; 

interface ICurvePool {
    function get_p() view external returns(uint);
    function price_oracle() view external returns(uint);
    function exchange(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns(uint);
}

interface IERC20 {
    function approve(address to, uint amount) external;
    function balanceOf(address holder) external returns(uint);
}

contract CvxCrvFeedFork is Test {

    ICurvePool curvePool = ICurvePool(0x971add32Ea87f10bD192671630be3BE8A11b8623);
    IERC20 cvxCrv = IERC20(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7);
    address cvxCrvHolder = 0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e;
    ConvexCurvePriceFeed feed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        feed = new ConvexCurvePriceFeed();
    }
    /**
    function testSwap7500000() public {
        swapXForY(cvxCrvHolder, 100_000 ether, 75);
    }
    function testEMA() public {
        emit log_named_uint("Price before", curvePool.get_p());
        emit log_named_uint("Swap amount", cvxCrv.balanceOf(cvxCrvHolder));
        swapAllForY(cvxCrvHolder);
        for(int secs; secs < 60*120; secs += 60){
            vm.warp(block.timestamp + 60);
            emit log_uint(curvePool.price_oracle());
        }
        emit log_named_uint("Price after", curvePool.get_p());
    }
    */

    function testSetMinCrvPerCvxCrvRatio_accessControl() public {
        vm.prank(feed.gov());
        uint newRatio = 10**18 - 10**17;
        feed.setMinCrvPerCvxCrvRatio(newRatio);
        assertEq(feed.minCrvPerCvxCrvRatio(), newRatio);

        vm.prank(feed.guardian());
        newRatio = 10**18 - 10**17*2;
        feed.setMinCrvPerCvxCrvRatio(newRatio);
        assertEq(feed.minCrvPerCvxCrvRatio(), newRatio);

        vm.prank(address(0xA));
        vm.expectRevert("ONLY GOV OR GUARDIAN");
        newRatio = 10**18 - 10**17*3;
        feed.setMinCrvPerCvxCrvRatio(newRatio);
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

    function swapXForY(address xHolder, uint amount, uint times) public {
        vm.startPrank(xHolder);
        cvxCrv.approve(address(curvePool), type(uint).max);
        for(uint i; i<times;i++){
            curvePool.exchange(1, 0, amount, 1);
            emit log_uint(curvePool.get_p());
        }
        vm.stopPrank();
    }

    function swapAllForY(address xHolder) public {
        vm.startPrank(xHolder);
        cvxCrv.approve(address(curvePool), type(uint).max);
        curvePool.exchange(1, 0, cvxCrv.balanceOf(xHolder), 1);
        vm.stopPrank();   
    }

}

