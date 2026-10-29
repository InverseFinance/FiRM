// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ConvexEscrow} from "src/escrows/ConvexEscrow.sol";
import {LegacyConvexEscrow} from "test/fixtures/LegacyConvexEscrow.sol";
import {Market, IDolaBorrowingRights, IOracle} from "src/Market.sol";
import {IERC20 as IMarketERC20} from "src/interfaces/IERC20.sol";
import {
    CvxRecoveryToken,
    CvxSecondaryPoolMock,
    CvxOuterPoolMock,
    CvxMarketSupportMock
} from "test/mocks/CvxRecoveryMocks.sol";

contract ConvexEscrowRecoveryTest is Test {
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant CVXCRV = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address constant OUTER = 0xCF50b810E57Ac33B91dCF525C6ddd9881B139332;
    address constant SECONDARY = 0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e;
    address constant DOLA = 0x865377367054516e17014CcdED1e7d814EDC9ce4;
    address constant USER = address(0xBEEF);
    address constant FRIEND = address(0xCAFE);
    address constant ATTACKER = address(0xBAD);

    ConvexEscrow escrow;
    CvxOuterPoolMock outer = CvxOuterPoolMock(OUTER);
    CvxSecondaryPoolMock secondary = CvxSecondaryPoolMock(SECONDARY);
    CvxRecoveryToken cvx = CvxRecoveryToken(CVX);
    CvxRecoveryToken cvxcrv = CvxRecoveryToken(CVXCRV);

    function setUp() public {
        // Fresh deterministic chain only: install mocks at the escrow's fixed dependencies.
        CvxRecoveryToken token = new CvxRecoveryToken();
        vm.etch(CVX, address(token).code);
        vm.etch(CVXCRV, address(token).code);
        vm.etch(DOLA, address(token).code);
        vm.etch(SECONDARY, address(new CvxSecondaryPoolMock()).code);
        vm.etch(OUTER, address(new CvxOuterPoolMock()).code);
        cvxcrv.mint(OUTER, 1e30);
        escrow = new ConvexEscrow();
        escrow.initialize(CVX, USER);
        cvx.mint(address(escrow), 100 ether);
        escrow.onDeposit();
    }

    function lock(address account, uint256 amount) internal {
        outer.setEarned(account, amount);
        vm.prank(ATTACKER);
        outer.getReward(account, false, true);
    }

    function assertRecovered(uint256 expected, address recipient) internal view {
        assertEq(secondary.balanceOf(address(escrow)), 0);
        assertEq(cvxcrv.balanceOf(address(escrow)), 0);
        assertEq(cvxcrv.balanceOf(recipient), expected);
        assertEq(escrow.balance(), 100 ether);
        assertEq(outer.balanceOf(address(escrow)), 100 ether);
        assertFalse(outer.lastStake());
        assertFalse(secondary.lastClaim());
    }

    function testLegacyAllClaimsLeaveSecondaryStakeLocked() public {
        LegacyConvexEscrow legacy = new LegacyConvexEscrow();
        legacy.initialize(CVX, USER);
        lock(address(legacy), 7 ether);
        vm.startPrank(USER);
        legacy.claim();
        legacy.claimTo(USER);
        legacy.claimTo(USER, new address[](0));
        vm.stopPrank();
        assertEq(cvxcrv.balanceOf(USER), 0);
        assertEq(secondary.balanceOf(address(legacy)), 7 ether);
        vm.prank(USER);
        vm.expectRevert();
        secondary.withdraw(7 ether, false);
    }

    function testClaimRecoversWithZeroOuterRewards() public {
        lock(address(escrow), 7 ether);
        assertEq(outer.earned(address(escrow)), 0);
        vm.prank(USER);
        escrow.claim();
        assertRecovered(7 ether, USER);
    }

    function testClaimToRecoversMixedLiquidStakedAndNewRewards() public {
        lock(address(escrow), 7 ether);
        cvxcrv.mint(address(escrow), 3 ether);
        outer.setEarned(address(escrow), 2 ether);
        vm.prank(USER);
        escrow.claimTo(FRIEND);
        assertRecovered(12 ether, FRIEND);
    }

    function testExtraRewardClaimRecoversSecondaryAndPreservesExtraRewardFlow() public {
        CvxRecoveryToken extra = new CvxRecoveryToken();
        extra.mint(OUTER, 1 ether);
        outer.setExtraToken(address(extra));
        lock(address(escrow), 7 ether);
        address[] memory extras = new address[](1);
        extras[0] = address(extra);
        vm.prank(USER);
        escrow.claimTo(FRIEND, extras);
        assertRecovered(7 ether, FRIEND);
        assertEq(extra.balanceOf(FRIEND), 1 ether);
    }

    function testRepeatedExternalStakingRemainsRecoverable() public {
        lock(address(escrow), 7 ether);
        vm.prank(USER);
        escrow.claim();
        lock(address(escrow), 2 ether);
        vm.prank(USER);
        escrow.claim();
        assertRecovered(9 ether, USER);
        assertEq(secondary.withdrawalCalls(), 2);
    }

    function testZeroSecondaryStakeDoesNotCallZeroWithdrawal() public {
        outer.setEarned(address(escrow), 2 ether);
        vm.prank(USER);
        escrow.claim();
        assertRecovered(2 ether, USER);
        assertEq(secondary.withdrawalCalls(), 0);
    }

    function testAllowlistedClaimCanRecoverToAuthorizedDestination() public {
        lock(address(escrow), 7 ether);
        vm.prank(USER);
        escrow.allowClaimOnBehalf(FRIEND);
        vm.prank(FRIEND);
        escrow.claimTo(USER);
        assertRecovered(7 ether, USER);
    }

    function testAllowlistedClaimPreservesExistingClaimCallerDestination() public {
        lock(address(escrow), 7 ether);
        vm.prank(USER);
        escrow.allowClaimOnBehalf(FRIEND);
        vm.prank(FRIEND);
        escrow.claim();
        assertRecovered(7 ether, FRIEND);
    }

    function testUnauthorizedClaimsCannotRecoverOrRedirectRewards() public {
        lock(address(escrow), 7 ether);
        vm.startPrank(ATTACKER);
        vm.expectRevert("ONLY BENEFICIARY OR ALLOWED");
        escrow.claim();
        vm.expectRevert("ONLY BENEFICIARY OR ALLOWED");
        escrow.claimTo(ATTACKER);
        vm.expectRevert("ONLY BENEFICIARY OR ALLOWED");
        escrow.claimTo(ATTACKER, new address[](0));
        vm.stopPrank();
        assertEq(secondary.balanceOf(address(escrow)), 7 ether);
        assertEq(cvxcrv.balanceOf(ATTACKER), 0);
    }

    function testRevokedClaimerCannotRecover() public {
        lock(address(escrow), 7 ether);
        vm.startPrank(USER);
        escrow.allowClaimOnBehalf(FRIEND);
        escrow.disallowClaimOnBehalf(FRIEND);
        vm.stopPrank();
        vm.prank(FRIEND);
        vm.expectRevert("ONLY BENEFICIARY OR ALLOWED");
        escrow.claimTo(USER);
        assertEq(secondary.balanceOf(address(escrow)), 7 ether);
    }

    function testCollateralCannotBeClaimedAsAnExtraReward() public {
        outer.setExtraToken(CVX);
        cvx.mint(OUTER, 1 ether);
        address[] memory extras = new address[](1);
        extras[0] = CVX;
        vm.prank(USER);
        vm.expectRevert("CANT CLAIM COLLATERAL");
        escrow.claimTo(USER, extras);
        assertEq(escrow.balance(), 100 ether);
        assertEq(cvx.balanceOf(USER), 0);
    }

    function testWrongExtraArrayCannotConsumeRewards() public {
        lock(address(escrow), 7 ether);
        vm.prank(USER);
        vm.expectRevert("UNEQUAL ARRAY");
        escrow.claimTo(USER, new address[](1));
        assertEq(secondary.balanceOf(address(escrow)), 7 ether);
    }

    function testSecondaryWithdrawalFailureRevertsAtomically() public {
        lock(address(escrow), 7 ether);
        outer.setEarned(address(escrow), 2 ether);
        secondary.setFailWithdraw(true);
        vm.prank(USER);
        vm.expectRevert("SECONDARY WITHDRAW FAILED");
        escrow.claim();
        assertEq(outer.earned(address(escrow)), 2 ether);
        assertEq(secondary.balanceOf(address(escrow)), 7 ether);
        assertEq(cvxcrv.balanceOf(USER), 0);
    }

    function testFalseRewardTokenTransferReverts() public {
        cvxcrv.mint(address(escrow), 3 ether);
        cvxcrv.setFailTransfers(true);
        vm.prank(USER);
        vm.expectRevert();
        escrow.claim();
        assertEq(cvxcrv.balanceOf(address(escrow)), 3 ether);
    }

    function testDepositAndMarketOnlyPaymentRemainIndependentOfRewards() public {
        lock(address(escrow), 7 ether);
        cvx.mint(address(escrow), 10 ether);
        vm.prank(ATTACKER);
        escrow.onDeposit();
        vm.prank(USER);
        vm.expectRevert("ONLY MARKET");
        escrow.pay(USER, 1 ether);
        escrow.pay(USER, 110 ether);
        assertEq(cvx.balanceOf(USER), 110 ether);
        assertEq(escrow.balance(), 0);
        assertEq(secondary.balanceOf(address(escrow)), 7 ether);
        vm.prank(USER);
        escrow.claim();
        assertEq(cvxcrv.balanceOf(USER), 7 ether);
    }

    function testInitializeRemainsOneShot() public {
        vm.expectRevert("ALREADY INITIALIZED");
        escrow.initialize(CVX, ATTACKER);
        assertEq(escrow.beneficiary(), USER);
        assertEq(escrow.market(), address(this));
    }

    function testFuzzRecoveryConservesRewards(uint96 locked, uint96 liquid, uint96 pending) public {
        uint256 lockedAmount = bound(locked, 1, 1e24);
        uint256 liquidAmount = bound(liquid, 0, 1e24);
        uint256 pendingAmount = bound(pending, 0, 1e24);
        lock(address(escrow), lockedAmount);
        cvxcrv.mint(address(escrow), liquidAmount);
        outer.setEarned(address(escrow), pendingAmount);
        vm.prank(USER);
        escrow.claim();
        assertRecovered(lockedAmount + liquidAmount + pendingAmount, USER);
    }

    function newMarket(address implementation) internal returns (Market) {
        CvxMarketSupportMock support = new CvxMarketSupportMock();
        return new Market(
            address(this),
            address(this),
            address(this),
            implementation,
            IDolaBorrowingRights(address(support)),
            IMarketERC20(CVX),
            IOracle(address(support)),
            5000,
            100,
            500,
            true
        );
    }

    function depositTo(Market market, address user) internal returns (address) {
        cvx.mint(user, 100 ether);
        vm.startPrank(user);
        cvx.approve(address(market), 100 ether);
        market.deposit(100 ether);
        vm.stopPrank();
        return address(market.escrows(user));
    }

    function testNewMarketAdoptionDoesNotUpgradeLegacyMarketOrClones() public {
        LegacyConvexEscrow legacyImplementation = new LegacyConvexEscrow();
        Market oldMarket = newMarket(address(legacyImplementation));
        address oldClone = depositTo(oldMarket, USER);
        Market replacementMarket = newMarket(address(new ConvexEscrow()));
        address newClone = depositTo(replacementMarket, USER);
        address laterLegacyClone = depositTo(oldMarket, FRIEND);
        assertEq(oldMarket.escrowImplementation(), address(legacyImplementation));
        assertEq(keccak256(oldClone.code), keccak256(laterLegacyClone.code));
        assertTrue(keccak256(oldClone.code) != keccak256(newClone.code));
        lock(oldClone, 7 ether);
        lock(newClone, 5 ether);
        vm.startPrank(USER);
        LegacyConvexEscrow(oldClone).claim();
        ConvexEscrow(newClone).claim();
        vm.stopPrank();
        assertEq(secondary.balanceOf(oldClone), 7 ether);
        assertEq(secondary.balanceOf(newClone), 0);
        assertEq(cvxcrv.balanceOf(USER), 5 ether);
    }

    function testRecoveryPreservesRealMarketDebtAndExitedPositionCanStillClaim() public {
        Market market = newMarket(address(new ConvexEscrow()));
        address clone = depositTo(market, USER);
        CvxRecoveryToken(DOLA).mint(address(market), 100 ether);
        vm.prank(USER);
        market.borrow(20 ether);
        lock(clone, 7 ether);
        vm.prank(USER);
        ConvexEscrow(clone).claim();
        assertEq(market.debts(USER), 20 ether);
        assertEq(market.totalDebt(), 20 ether);
        assertEq(ConvexEscrow(clone).balance(), 100 ether);
        lock(clone, 2 ether);
        vm.startPrank(USER);
        CvxRecoveryToken(DOLA).approve(address(market), 20 ether);
        market.repay(USER, 20 ether);
        market.withdrawMax();
        ConvexEscrow(clone).claim();
        vm.stopPrank();
        assertEq(market.debts(USER), 0);
        assertEq(ConvexEscrow(clone).balance(), 0);
        assertEq(cvx.balanceOf(USER), 100 ether);
        assertEq(cvxcrv.balanceOf(USER), 9 ether);
        assertEq(secondary.balanceOf(clone), 0);
    }

    function testProtectiveBatchCallPaysBothLiveAndExitedLegacyEscrows() public {
        Market legacyMarket = newMarket(address(new LegacyConvexEscrow()));
        address liveClone = depositTo(legacyMarket, USER);
        address exitedClone = depositTo(legacyMarket, FRIEND);
        vm.prank(FRIEND);
        legacyMarket.withdrawMax();
        lock(exitedClone, 3 ether); // Already locked principal remains separate.
        outer.setEarned(liveClone, 7 ether);
        outer.setEarned(exitedClone, 5 ether);
        vm.startPrank(ATTACKER);
        outer.getReward(liveClone, false, false);
        outer.getReward(exitedClone, false, false);
        vm.stopPrank();
        assertEq(cvxcrv.balanceOf(liveClone), 7 ether);
        assertEq(cvxcrv.balanceOf(exitedClone), 5 ether);
        assertEq(cvxcrv.balanceOf(ATTACKER), 0);
        assertEq(secondary.balanceOf(liveClone), 0);
        assertEq(secondary.balanceOf(exitedClone), 3 ether);
        assertEq(LegacyConvexEscrow(liveClone).balance(), 100 ether);
        assertEq(LegacyConvexEscrow(exitedClone).balance(), 0);
        assertEq(legacyMarket.debts(USER), 0);
        assertEq(legacyMarket.debts(FRIEND), 0);
        vm.prank(FRIEND);
        LegacyConvexEscrow(exitedClone).claim();
        assertEq(cvxcrv.balanceOf(FRIEND), 5 ether);
        assertEq(secondary.balanceOf(exitedClone), 3 ether);
    }
}
