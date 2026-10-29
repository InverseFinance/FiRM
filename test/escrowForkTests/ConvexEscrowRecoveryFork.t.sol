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

interface ICvxRecoveryForkMarket {
    function escrows(address) external view returns (address);
    function debts(address) external view returns (uint256);
    function escrowImplementation() external view returns (address);
    function collateral() external view returns (address);
}

contract ConvexEscrowRecoveryForkTest is Test {
    uint256 constant PINNED_BLOCK = 25_854_482;
    address constant MARKET = 0xdc2265cBD15beD67b5F2c0B82e23FcE4a07ddF6b;
    address constant IMPLEMENTATION = 0xf2a2b6c1F47c75FFacDbF60B35F2Ed2d35f0a9C1;
    address constant LIVE_ESCROW = 0x12e353De6799B0C45630D025DB9565157539f954;
    address constant LIVE_USER = 0x01ac1386a47B460C9186Dc9662E533Fe5F3beDcA;
    address constant EXITED_ESCROW = 0x74eB6251728CfeDC0E866Ba42113Bcdd43128F04;
    address constant EXITED_USER = 0x8E99d4ecb0690b81C7eB818e1903023620d46AFf;
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant CVXCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address constant OUTER = 0xCF50b810E57Ac33B91dCF525C6ddd9881B139332;
    address constant SECONDARY = 0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e;
    address constant NEW_USER = address(0xBEEF);
    address constant ATTACKER = address(0xBAD);

    function setUp() public {
        // New tests written from verified interfaces, not executable gist code.
        vm.createSelectFork(vm.rpcUrl("mainnet"), PINNED_BLOCK);
        assertEq(ICvxRecoveryForkMarket(MARKET).escrowImplementation(), IMPLEMENTATION);
        assertEq(ICvxRecoveryForkMarket(MARKET).collateral(), CVX);
        assertEq(ICvxRecoveryForkPool(OUTER).cvxCrvRewards(), SECONDARY);
    }

    function bind(address user, address escrow) internal view {
        assertEq(ICvxRecoveryForkMarket(MARKET).escrows(user), escrow);
        assertEq(ConvexEscrow(escrow).market(), MARKET);
        assertEq(ConvexEscrow(escrow).beneficiary(), user);
        assertEq(
            keccak256(escrow.code),
            keccak256(abi.encodePacked(hex"363d3d373d3d3d363d73", IMPLEMENTATION, hex"5af43d82803e903d91602b57fd5bf3"))
        );
    }

    function testLegacyLiveCloneStillCannotRecoverSecondaryStake() public {
        bind(LIVE_USER, LIVE_ESCROW);
        uint256 collateralBefore = ConvexEscrow(LIVE_ESCROW).balance();
        uint256 debtBefore = ICvxRecoveryForkMarket(MARKET).debts(LIVE_USER);
        uint256 userBefore = IERC20(CVXCRV).balanceOf(LIVE_USER);
        uint256 liquidBefore = IERC20(CVXCRV).balanceOf(LIVE_ESCROW);
        assertGt(ICvxRecoveryForkPool(OUTER).earned(LIVE_ESCROW), 0);
        vm.prank(ATTACKER);
        ICvxRecoveryForkPool(OUTER).getReward(LIVE_ESCROW, false, true);
        uint256 locked = ICvxCrvRewardPoolRecovery(SECONDARY).balanceOf(LIVE_ESCROW);
        assertGt(locked, 0);
        vm.prank(LIVE_USER);
        ConvexEscrow(LIVE_ESCROW).claim();
        assertEq(ICvxCrvRewardPoolRecovery(SECONDARY).balanceOf(LIVE_ESCROW), locked);
        // Existing liquid rewards are claimable; the secondary stake remains locked.
        assertEq(IERC20(CVXCRV).balanceOf(LIVE_USER) - userBefore, liquidBefore);
        assertEq(IERC20(CVXCRV).balanceOf(LIVE_ESCROW), 0);
        assertEq(ConvexEscrow(LIVE_ESCROW).balance(), collateralBefore);
        assertEq(ICvxRecoveryForkMarket(MARKET).debts(LIVE_USER), debtBefore);
    }

    function testProtectiveClaimsReachLiveAndExitedClonesWithoutSecondaryStaking() public {
        bind(LIVE_USER, LIVE_ESCROW);
        bind(EXITED_USER, EXITED_ESCROW);
        assertEq(ConvexEscrow(EXITED_ESCROW).balance(), 0);
        assertEq(ICvxRecoveryForkMarket(MARKET).debts(EXITED_USER), 0);
        address[2] memory escrows = [LIVE_ESCROW, EXITED_ESCROW];
        address[2] memory users = [LIVE_USER, EXITED_USER];
        for (uint256 i; i < escrows.length; ++i) {
            address target = escrows[i];
            uint256 liquidBefore = IERC20(CVXCRV).balanceOf(target);
            uint256 secondaryBefore = ICvxCrvRewardPoolRecovery(SECONDARY).balanceOf(target);
            uint256 collateralBefore = ConvexEscrow(target).balance();
            uint256 debtBefore = ICvxRecoveryForkMarket(MARKET).debts(users[i]);
            assertGt(ICvxRecoveryForkPool(OUTER).earned(target), 0);
            vm.prank(ATTACKER);
            ICvxRecoveryForkPool(OUTER).getReward(target, false, false);
            assertGt(IERC20(CVXCRV).balanceOf(target), liquidBefore);
            assertEq(ICvxCrvRewardPoolRecovery(SECONDARY).balanceOf(target), secondaryBefore);
            assertEq(ConvexEscrow(target).balance(), collateralBefore);
            assertEq(ICvxRecoveryForkMarket(MARKET).debts(users[i]), debtBefore);
        }
        assertEq(IERC20(CVXCRV).balanceOf(ATTACKER), 0);
    }

    function testReplacementRecoversActualConvexStakeWithNoOuterRewards() public {
        ConvexEscrow replacement = new ConvexEscrow();
        replacement.initialize(CVX, NEW_USER);
        deal(CVX, address(replacement), 1_000 ether);
        replacement.onDeposit();
        vm.warp(block.timestamp + 1 hours);
        assertGt(ICvxRecoveryForkPool(OUTER).earned(address(replacement)), 0);
        vm.prank(ATTACKER);
        ICvxRecoveryForkPool(OUTER).getReward(address(replacement), false, true);
        uint256 locked = ICvxCrvRewardPoolRecovery(SECONDARY).balanceOf(address(replacement));
        uint256 userBefore = IERC20(CVXCRV).balanceOf(NEW_USER);
        assertGt(locked, 0);
        assertEq(ICvxRecoveryForkPool(OUTER).earned(address(replacement)), 0);
        vm.prank(NEW_USER);
        replacement.claim();
        assertEq(ICvxCrvRewardPoolRecovery(SECONDARY).balanceOf(address(replacement)), 0);
        assertEq(IERC20(CVXCRV).balanceOf(NEW_USER) - userBefore, locked);
        assertEq(replacement.balance(), 1_000 ether);
        assertEq(ICvxRecoveryForkPool(OUTER).balanceOf(address(replacement)), 1_000 ether);
    }
}
