// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/escrows/ConvexCurveEscrow.sol";

contract ConvexCurveEscrowForkTest is Test{

    address market = address(0xA);
    address beneficiary = address(0xB);
    address friend = address(0xC);
    address holder = address(0x50BE13b54f3EeBBe415d20250598D81280e56772);
    IERC20 cvxCrv = IERC20(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7);
    IERC20 threeCrv = IERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    IERC20 cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    ICvxCrvStakingWrapper stakingWrapper = ICvxCrvStakingWrapper(0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434);
        
    ConvexCurveEscrow escrow;


    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        
        escrow = new ConvexCurveEscrow();
        vm.startPrank(market, market);
        escrow.initialize(cvxCrv, beneficiary);
        vm.stopPrank();
    }

    function testOnDeposit_successful_whenContractHoldsCvxCrv() public {
        uint balanceBefore = escrow.balance();
        uint stakedBalanceBefore = stakingWrapper.balanceOf(address(escrow));
        
        vm.prank(holder, holder);
        cvxCrv.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        assertEq(escrow.balance(), balanceBefore + 1 ether);
        assertEq(stakingWrapper.balanceOf(address(escrow)), stakedBalanceBefore + 1 ether);
    }

    function testPay_successful_whenContractHasStakedCvxCrv() public {
        vm.prank(holder, holder);
        cvxCrv.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        uint balanceBefore = escrow.balance();
        uint stakedBalanceBefore = stakingWrapper.balanceOf(address(escrow));
        uint beneficiaryBalanceBefore = cvxCrv.balanceOf(beneficiary);

        vm.prank(market, market);
        escrow.pay(beneficiary, 1 ether);


        assertEq(escrow.balance(), balanceBefore - 1 ether);
        assertEq(stakingWrapper.balanceOf(address(escrow)), stakedBalanceBefore - 1 ether);
        assertEq(cvxCrv.balanceOf(beneficiary), beneficiaryBalanceBefore + 1 ether);
    }

    function testPay_failWithONLYMARKET_whenCalledByNonMarket() public {
        vm.prank(holder, holder);
        cvxCrv.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.prank(holder, holder);
        vm.expectRevert("ONLY MARKET");
        escrow.pay(beneficiary, 1 ether);
    }

    function testClaim_successful_whenCalledByBeneficiary() public {
        uint crvBalanceBefore = crv.balanceOf(beneficiary);
        uint cvxBalanceBefore = cvx.balanceOf(beneficiary);
        uint threeCrvBalanceBefore = threeCrv.balanceOf(beneficiary);
        vm.prank(holder, holder);
        cvxCrv.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.claim();

        assertGt(crv.balanceOf(beneficiary), crvBalanceBefore);
        assertGt(cvx.balanceOf(beneficiary), cvxBalanceBefore);
        assertEq(threeCrv.balanceOf(beneficiary), threeCrvBalanceBefore);
    }

    function testClaim_successful_whenRewardWeightSetTo5000() public {
        uint crvBalanceBefore = crv.balanceOf(beneficiary);
        uint cvxBalanceBefore = cvx.balanceOf(beneficiary);
        uint threeCrvBalanceBefore = threeCrv.balanceOf(beneficiary);
        vm.prank(holder, holder);
        cvxCrv.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        
        vm.startPrank(beneficiary);
        escrow.setRewardWeight(5000);
        vm.warp(block.timestamp + 14 days);
        escrow.claim();
        vm.stopPrank();

        assertGt(crv.balanceOf(beneficiary), crvBalanceBefore, "Crv balance did not increase");
        assertGt(cvx.balanceOf(beneficiary), cvxBalanceBefore, "Cvx balance did not increase");
        assertGt(threeCrv.balanceOf(beneficiary), threeCrvBalanceBefore, "Three curve balance did not increase");
    }

    function testClaim_successful_whenRewardWeightSetTo10000() public {
        uint crvBalanceBefore = crv.balanceOf(beneficiary);
        uint cvxBalanceBefore = cvx.balanceOf(beneficiary);
        uint threeCrvBalanceBefore = threeCrv.balanceOf(beneficiary);
        vm.prank(holder, holder);
        cvxCrv.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        
        vm.startPrank(beneficiary);
        escrow.setRewardWeight(10000);
        vm.warp(block.timestamp + 14 days);
        escrow.claim();
        vm.stopPrank();

        assertEq(crv.balanceOf(beneficiary), crvBalanceBefore);
        assertEq(cvx.balanceOf(beneficiary), cvxBalanceBefore);
        assertGt(threeCrv.balanceOf(beneficiary), threeCrvBalanceBefore, "Three curve balance did not increase");
    }

    function testClaimTo_successful_whenCalledByBeneficiary() public {
        uint crvBalanceBefore = crv.balanceOf(friend);
        uint cvxBalanceBefore = cvx.balanceOf(friend);
        uint threeCrvBalanceBefore = threeCrv.balanceOf(friend);
        vm.prank(holder, holder);
        cvxCrv.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.claimTo(friend);

        assertGt(crv.balanceOf(friend), crvBalanceBefore);
        assertGt(cvx.balanceOf(friend), cvxBalanceBefore);
        assertEq(threeCrv.balanceOf(friend), threeCrvBalanceBefore);
    }

    function testClaimTo_successful_whenCalledByAllowlistedAddress() public {
        uint crvBalanceBefore = crv.balanceOf(beneficiary);
        uint cvxBalanceBefore = cvx.balanceOf(beneficiary);
        uint threeCrvBalanceBefore = threeCrv.balanceOf(beneficiary);
        vm.prank(holder, holder);
        cvxCrv.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.allowClaimOnBehalf(friend);
        vm.prank(friend);
        escrow.claimTo(beneficiary);

        assertGt(crv.balanceOf(beneficiary), crvBalanceBefore);
        assertGt(cvx.balanceOf(beneficiary), cvxBalanceBefore);
        assertEq(threeCrv.balanceOf(beneficiary), threeCrvBalanceBefore);
    }

    function testClaimTo_fails_whenAllowlistedAddressIsDisallowed() public {
        vm.prank(holder, holder);
        cvxCrv.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.allowClaimOnBehalf(friend);
        vm.prank(friend);
        escrow.claimTo(beneficiary);
        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.disallowClaimOnBehalf(friend);
        vm.prank(friend);
        vm.expectRevert("ONLY BENEFICIARY OR ALLOWED");
        escrow.claimTo(beneficiary);
    }


    function testClaimTo_fails_whenCalledByNonAllowlistedAddress() public {
        vm.prank(holder, holder);
        cvxCrv.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(friend);
        vm.expectRevert("ONLY BENEFICIARY OR ALLOWED");
        escrow.claimTo(beneficiary);
    }

    function testAllowClaimOnBehalf_fails_whenCalledByNonBeneficiary() public {
        vm.prank(friend);
        vm.expectRevert("ONLY BENEFICIARY");
        escrow.allowClaimOnBehalf(friend);
    }

    function testDisallowClaimOnBehalf_fails_whenCalledByNonBeneficiary() public {
        vm.prank(friend);
        vm.expectRevert("ONLY BENEFICIARY");
        escrow.disallowClaimOnBehalf(friend);
    }

    function testSetRewardWeight_fails_whenCalledByNonBeneficiary() public {
        vm.prank(friend);
        vm.expectRevert("ONLY BENEFICIARY OR ALLOWED");
        escrow.setRewardWeight(10000);
    }

    function testSetRewardWeight_fails_whenSetOver10000() public {
        vm.prank(beneficiary);
        vm.expectRevert("WEIGHT > 10000");
        escrow.setRewardWeight(10001);
    }
}
