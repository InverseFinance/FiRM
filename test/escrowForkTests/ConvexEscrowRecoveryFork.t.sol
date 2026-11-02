// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ConvexEscrow, ICvxCrvRewardPoolRecovery} from "src/escrows/ConvexEscrow.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ICvxRecoveryForkPool {
    function earned(address) external view returns (uint256);
    function getReward(address, bool, bool) external;
    function cvxCrvRewards() external view returns (address);
    function balanceOf(address) external view returns (uint256);
}

contract ConvexEscrowRecoveryForkTest is Test {
    uint256 constant PINNED_BLOCK = 25_854_482;
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant CVXCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address constant OUTER = 0xCF50b810E57Ac33B91dCF525C6ddd9881B139332;
    address constant SECONDARY = 0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e;
    address constant USER = address(0xBEEF);
    address constant THIRD_PARTY = address(0xBAD);

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), PINNED_BLOCK);
        assertEq(ICvxRecoveryForkPool(OUTER).cvxCrvRewards(), SECONDARY);
    }

    function stakedEscrow() internal returns (ConvexEscrow escrow, uint256 staked) {
        escrow = new ConvexEscrow();
        escrow.initialize(CVX, USER);
        deal(CVX, address(escrow), 1_000 ether);
        escrow.onDeposit();
        vm.warp(block.timestamp + 1 hours);
        assertGt(ICvxRecoveryForkPool(OUTER).earned(address(escrow)), 0);
        vm.prank(THIRD_PARTY);
        ICvxRecoveryForkPool(OUTER).getReward(address(escrow), false, true);
        staked = ICvxCrvRewardPoolRecovery(SECONDARY).balanceOf(address(escrow));
        assertGt(staked, 0);
        assertEq(ICvxRecoveryForkPool(OUTER).earned(address(escrow)), 0);
    }

    function assertCollateralUnchanged(ConvexEscrow escrow) internal view {
        assertEq(escrow.balance(), 1_000 ether);
        assertEq(ICvxRecoveryForkPool(OUTER).balanceOf(address(escrow)), 1_000 ether);
    }

    function testOptInRecoversActualSecondaryStakeWithZeroOuterRewards() public {
        (ConvexEscrow escrow, uint256 staked) = stakedEscrow();
        uint256 before = IERC20(CVXCRV).balanceOf(USER);
        vm.prank(USER);
        escrow.claim(true);
        assertEq(ICvxCrvRewardPoolRecovery(SECONDARY).balanceOf(address(escrow)), 0);
        assertEq(IERC20(CVXCRV).balanceOf(USER) - before, staked);
        assertCollateralUnchanged(escrow);
    }

    function testDefaultClaimLeavesSecondaryStakeAvailableForRecovery() public {
        (ConvexEscrow escrow, uint256 staked) = stakedEscrow();
        vm.warp(block.timestamp + 1 hours);
        uint256 before = IERC20(CVXCRV).balanceOf(USER);
        vm.prank(USER);
        escrow.claim();
        uint256 liquidClaimed = IERC20(CVXCRV).balanceOf(USER) - before;
        assertGt(liquidClaimed, 0);
        assertEq(ICvxCrvRewardPoolRecovery(SECONDARY).balanceOf(address(escrow)), staked);
        vm.prank(USER);
        escrow.claim(true);
        assertEq(ICvxCrvRewardPoolRecovery(SECONDARY).balanceOf(address(escrow)), 0);
        assertEq(IERC20(CVXCRV).balanceOf(USER) - before, liquidClaimed + staked);
        assertCollateralUnchanged(escrow);
    }

    function testRevertingSecondaryWithdrawalDoesNotBlockNormalClaim() public {
        (ConvexEscrow escrow, uint256 staked) = stakedEscrow();
        vm.warp(block.timestamp + 1 hours);
        uint256 before = IERC20(CVXCRV).balanceOf(USER);
        bytes memory failure = abi.encodeWithSignature("Error(string)", "SECONDARY UNAVAILABLE");
        vm.mockCallRevert(SECONDARY, abi.encodeWithSignature("withdraw(uint256,bool)", staked, false), failure);
        vm.prank(USER);
        vm.expectRevert(failure);
        escrow.claim(true);
        assertGt(ICvxRecoveryForkPool(OUTER).earned(address(escrow)), 0);
        vm.prank(USER);
        escrow.claimTo(USER);
        uint256 liquidClaimed = IERC20(CVXCRV).balanceOf(USER) - before;
        assertGt(liquidClaimed, 0);
        assertEq(ICvxCrvRewardPoolRecovery(SECONDARY).balanceOf(address(escrow)), staked);
        vm.clearMockedCalls();
        vm.prank(USER);
        escrow.claim(true);
        assertEq(ICvxCrvRewardPoolRecovery(SECONDARY).balanceOf(address(escrow)), 0);
        assertEq(IERC20(CVXCRV).balanceOf(USER) - before, liquidClaimed + staked);
        assertCollateralUnchanged(escrow);
    }
}
