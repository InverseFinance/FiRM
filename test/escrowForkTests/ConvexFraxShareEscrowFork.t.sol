// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/escrows/ConvexFraxShareEscrow.sol";

contract ConvexFraxShareEscrowForkTest is Test{

    address market = address(0xA);
    address beneficiary = address(0xB);
    address friend = address(0xC);
    address holder = address(0xD);
    IERC20 cvxFxs = IERC20(0xFEEf77d3f69374f66429C91d732A244f074bdf74);
    IERC20 cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 fxs = IERC20(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    ICvxFxsStakingWrapper stakingWrapper = ICvxFxsStakingWrapper(0x49b4d1dF40442f0C31b1BbAEA3EDE7c38e37E31a);
        
    ConvexFraxShareEscrow escrow;


    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        deal(address(cvxFxs), holder, 1 ether);
        escrow = new ConvexFraxShareEscrow();
        vm.startPrank(market, market);
        escrow.initialize(cvxFxs, beneficiary);
        vm.stopPrank();
    }

    function testOnDeposit_successful_whenContractHoldsCvxFxs() public {
        uint balanceBefore = escrow.balance();
        uint stakedBalanceBefore = stakingWrapper.balanceOf(address(escrow));
        
        vm.prank(holder, holder);
        cvxFxs.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        assertEq(escrow.balance(), balanceBefore + 1 ether);
        assertEq(stakingWrapper.balanceOf(address(escrow)), stakedBalanceBefore + 1 ether);
    }

    function testPay_successful_whenContractHasStakedCvxFxs() public {
        vm.prank(holder, holder);
        cvxFxs.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        uint balanceBefore = escrow.balance();
        uint stakedBalanceBefore = stakingWrapper.balanceOf(address(escrow));
        uint beneficiaryBalanceBefore = cvxFxs.balanceOf(beneficiary);

        vm.prank(market, market);
        escrow.pay(beneficiary, 1 ether);


        assertEq(escrow.balance(), balanceBefore - 1 ether);
        assertEq(stakingWrapper.balanceOf(address(escrow)), stakedBalanceBefore - 1 ether);
        assertEq(cvxFxs.balanceOf(beneficiary), beneficiaryBalanceBefore + 1 ether);
    }

    function testPay_failWithONLYMARKET_whenCalledByNonMarket() public {
        vm.prank(holder, holder);
        cvxFxs.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.prank(holder, holder);
        vm.expectRevert("ONLY MARKET");
        escrow.pay(beneficiary, 1 ether);
    }

    function testClaim_successful_whenCalledByBeneficiary() public {
        uint fxsBalanceBefore = fxs.balanceOf(beneficiary);
        uint cvxBalanceBefore = cvx.balanceOf(beneficiary);
        vm.prank(holder, holder);
        cvxFxs.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.claim();

        assertGt(fxs.balanceOf(beneficiary), fxsBalanceBefore);
        assertGt(cvx.balanceOf(beneficiary), cvxBalanceBefore);
    }

    function testClaimTo_successful_whenCalledByBeneficiary() public {
        uint fxsBalanceBefore = fxs.balanceOf(friend);
        uint cvxBalanceBefore = cvx.balanceOf(friend);
        vm.prank(holder, holder);
        cvxFxs.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.claimTo(friend);

        assertGt(fxs.balanceOf(friend), fxsBalanceBefore);
        assertGt(cvx.balanceOf(friend), cvxBalanceBefore);
    }

    function testClaimTo_successful_whenCalledByAllowlistedAddress() public {
        uint fxsBalanceBefore = fxs.balanceOf(beneficiary);
        uint cvxBalanceBefore = cvx.balanceOf(beneficiary);
        vm.prank(holder, holder);
        cvxFxs.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.allowClaimOnBehalf(friend);
        vm.prank(friend);
        escrow.claimTo(beneficiary);

        assertGt(fxs.balanceOf(beneficiary), fxsBalanceBefore);
        assertGt(cvx.balanceOf(beneficiary), cvxBalanceBefore);
    }

    function testClaimTo_fails_whenAllowlistedAddressIsDisallowed() public {
        vm.prank(holder, holder);
        cvxFxs.transfer(address(escrow), 1 ether);
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
        cvxFxs.transfer(address(escrow), 1 ether);
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
}
