// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Clones} from "openzeppelin-contracts/contracts/proxy/Clones.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20, SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {StakingRewardsEscrow} from "src/escrows/StakingRewardsEscrow.sol";
import {IStakingRewards} from "src/interfaces/IStakingRewards.sol";
import {StakingRewardsFixture} from "test/mocks/StakingRewardsFixture.sol";
import {FiRMBaseTest} from "test/FiRMBaseTest.sol";
import {Market, IDolaBorrowingRights, IOracle} from "src/Market.sol";
import {IERC20 as MarketIERC20} from "src/interfaces/IERC20.sol";

/// @dev Exact-transfer token with configurable failures and callbacks for escrow tests.
contract EscrowTestToken is ERC20 {
    bool public failTransfers;
    address public failingSender;
    bool public returnFalse;
    bool public returnNothing;
    bool public requireZeroApproval;
    address public callbackSender;
    address public callbackTarget;
    bytes public callbackData;
    bool public callbackSucceeded;
    bytes public callbackResult;

    constructor() ERC20("Escrow test token", "TEST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setTransferFailure(bool fail, address sender, bool falseReturn) external {
        failTransfers = fail;
        failingSender = sender;
        returnFalse = falseReturn;
    }

    function setReturnNothing(bool enabled) external {
        returnNothing = enabled;
    }

    function setRequireZeroApproval(bool enabled) external {
        requireZeroApproval = enabled;
    }

    function setAllowance(address owner, address spender, uint256 amount) external {
        _approve(owner, spender, amount);
    }

    function setCallback(address sender, address target, bytes calldata data) external {
        callbackSender = sender;
        callbackTarget = target;
        callbackData = data;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (failTransfers && (failingSender == address(0) || failingSender == msg.sender)) {
            if (returnFalse) return false;
            revert("TRANSFER FAILED");
        }
        super.transfer(to, amount);
        _callback();
        if (returnNothing) {
            assembly {
                return(0, 0)
            }
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        super.transferFrom(from, to, amount);
        _callback();
        if (returnNothing) {
            assembly {
                return(0, 0)
            }
        }
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        if (requireZeroApproval && amount != 0) require(allowance(msg.sender, spender) == 0, "RESET APPROVAL");
        super.approve(spender, amount);
        _callback();
        if (returnNothing) {
            assembly {
                return(0, 0)
            }
        }
        return true;
    }

    function _callback() internal {
        if (callbackTarget == address(0) || msg.sender != callbackSender) return;
        address target = callbackTarget;
        callbackTarget = address(0);
        (callbackSucceeded, callbackResult) = target.call(callbackData);
    }
}

/// @dev Standard ERC-4626 accounting and transfers, with no custom staking behavior.
contract EscrowTestVault is ERC4626 {
    constructor(IERC20 asset_) ERC20("Staked reward", "sGOV") ERC4626(asset_) {}
}

contract StakingRewardsEscrowTest is Test {
    uint256 constant DURATION = 1000;
    uint256 constant FUNDING = 1000 ether;
    address constant MARKET = address(0xA);
    address constant BENEFICIARY = address(0xB);
    address constant FRIEND = address(0xC);
    address constant RECIPIENT = address(0xD);

    EscrowTestToken collateral;
    EscrowTestToken reward;
    StakingRewardsFixture pool;
    EscrowTestVault vault;
    StakingRewardsEscrow implementation;
    StakingRewardsEscrow escrow;

    event AllowClaim(address indexed allowedAddress, bool allowed);

    function setUp() public {
        vm.warp(1 days);
        collateral = new EscrowTestToken();
        reward = new EscrowTestToken();
        vault = new EscrowTestVault(reward);
        pool = new StakingRewardsFixture(address(collateral), address(reward), address(this), DURATION);
        implementation = new StakingRewardsEscrow(address(pool), address(vault));
        escrow = _clone(BENEFICIARY);
    }

    function _clone(address beneficiary) internal returns (StakingRewardsEscrow instance) {
        instance = StakingRewardsEscrow(Clones.clone(address(implementation)));
        vm.prank(MARKET);
        instance.initialize(collateral, beneficiary);
    }

    function _stake(uint256 amount) internal {
        collateral.mint(address(escrow), amount);
        escrow.onDeposit();
    }

    function _fund() internal {
        reward.mint(address(pool), FUNDING);
        pool.notifyRewardAmount(FUNDING);
    }

    function _pay(uint256 amount) internal {
        vm.prank(MARKET);
        escrow.pay(RECIPIENT, amount);
    }

    function _seedVaultWithYield() internal {
        reward.mint(address(this), 100 ether);
        reward.approve(address(vault), 100 ether);
        vault.deposit(100 ether, address(this));
        reward.mint(address(vault), 100 ether);
    }

    function _assertReentrancyBlocked(EscrowTestToken token) internal view {
        assertFalse(token.callbackSucceeded());
        assertEq(token.callbackResult(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
    }

    function testInitializeClone() public view {
        assertEq(escrow.market(), MARKET);
        assertEq(escrow.beneficiary(), BENEFICIARY);
        assertEq(address(escrow.token()), address(collateral));
        assertEq(address(escrow.rewardsToken()), address(reward));
        assertEq(address(escrow.stakingRewards()), address(pool));
        assertEq(address(escrow.sGOV()), address(vault));
        assertEq(collateral.allowance(address(escrow), address(pool)), type(uint256).max);
        assertEq(reward.allowance(address(escrow), address(vault)), type(uint256).max);
        assertEq(collateral.allowance(address(implementation), address(pool)), 0);
        assertEq(reward.allowance(address(implementation), address(vault)), 0);
    }

    function testCannotInitializeImplementationOrReinitializeClone() public {
        vm.expectRevert(StakingRewardsEscrow.AlreadyInitialized.selector);
        implementation.initialize(collateral, BENEFICIARY);
        vm.expectRevert(StakingRewardsEscrow.AlreadyInitialized.selector);
        escrow.initialize(collateral, FRIEND);
        assertEq(escrow.market(), MARKET);
        assertEq(escrow.beneficiary(), BENEFICIARY);
    }

    function testInitializeRejectsWrongTokenAndZeroBeneficiary() public {
        StakingRewardsEscrow instance = StakingRewardsEscrow(Clones.clone(address(implementation)));
        vm.expectRevert(StakingRewardsEscrow.InvalidToken.selector);
        instance.initialize(reward, BENEFICIARY);
        vm.expectRevert(StakingRewardsEscrow.InvalidToken.selector);
        instance.initialize(IERC20(address(0)), BENEFICIARY);
        vm.expectRevert(StakingRewardsEscrow.InvalidBeneficiary.selector);
        instance.initialize(collateral, address(0));
        assertEq(instance.market(), address(0));
        vm.prank(MARKET);
        instance.initialize(collateral, BENEFICIARY);
        assertEq(instance.market(), MARKET);
    }

    function testConstructorRejectsMissingPoolCode() public {
        vm.expectRevert(StakingRewardsEscrow.InvalidStakingRewards.selector);
        new StakingRewardsEscrow(address(0), address(vault));
        vm.expectRevert(StakingRewardsEscrow.InvalidStakingRewards.selector);
        new StakingRewardsEscrow(FRIEND, address(vault));
    }

    function testConstructorRejectsInvalidTokenConfiguration() public {
        vm.mockCall(address(pool), abi.encodeCall(IStakingRewards.stakingToken, ()), abi.encode(address(0)));
        vm.expectRevert(StakingRewardsEscrow.InvalidToken.selector);
        new StakingRewardsEscrow(address(pool), address(vault));
        vm.clearMockedCalls();
        vm.mockCall(address(pool), abi.encodeCall(IStakingRewards.rewardsToken, ()), abi.encode(address(0)));
        vm.expectRevert(StakingRewardsEscrow.InvalidToken.selector);
        new StakingRewardsEscrow(address(pool), address(vault));
        vm.mockCall(address(pool), abi.encodeCall(IStakingRewards.rewardsToken, ()), abi.encode(FRIEND));
        vm.expectRevert(StakingRewardsEscrow.InvalidToken.selector);
        new StakingRewardsEscrow(address(pool), address(vault));
    }

    function testConstructorRejectsIdenticalTokens() public {
        StakingRewardsFixture sameTokenPool =
            new StakingRewardsFixture(address(collateral), address(collateral), address(this), DURATION);
        vm.expectRevert(StakingRewardsEscrow.IdenticalTokens.selector);
        new StakingRewardsEscrow(address(sameTokenPool), address(vault));
    }

    function testInitializeHandlesZeroFirstApproval() public {
        StakingRewardsEscrow instance = StakingRewardsEscrow(Clones.clone(address(implementation)));
        collateral.setRequireZeroApproval(true);
        collateral.setAllowance(address(instance), address(pool), 1);
        reward.setRequireZeroApproval(true);
        reward.setAllowance(address(instance), address(vault), 1);
        vm.prank(MARKET);
        instance.initialize(collateral, BENEFICIARY);
        assertEq(collateral.allowance(address(instance), address(pool)), type(uint256).max);
        assertEq(reward.allowance(address(instance), address(vault)), type(uint256).max);
    }

    function testConstructorRejectsMissingVaultCode() public {
        vm.expectRevert(StakingRewardsEscrow.InvalidVault.selector);
        new StakingRewardsEscrow(address(pool), address(0));
        vm.expectRevert(StakingRewardsEscrow.InvalidVault.selector);
        new StakingRewardsEscrow(address(pool), FRIEND);
    }

    function testConstructorRejectsWrongVaultAsset() public {
        EscrowTestVault wrongVault = new EscrowTestVault(collateral);
        vm.expectRevert(StakingRewardsEscrow.InvalidVault.selector);
        new StakingRewardsEscrow(address(pool), address(wrongVault));
    }

    function testNoReturnTokensCanInitializeStakePayAndClaim() public {
        collateral.setReturnNothing(true);
        reward.setReturnNothing(true);
        escrow = _clone(BENEFICIARY);
        _stake(10 ether);
        _fund();
        vm.warp(block.timestamp + DURATION);
        _pay(10 ether);
        vm.prank(BENEFICIARY);
        escrow.claim();
        assertEq(collateral.balanceOf(RECIPIENT), 10 ether);
        assertEq(reward.balanceOf(BENEFICIARY), FUNDING);
    }

    function testOnDepositIsPermissionlessAndIncludesDirectTransfers() public {
        collateral.mint(FRIEND, 7 ether);
        vm.prank(FRIEND);
        collateral.transfer(address(escrow), 7 ether);
        assertEq(escrow.balance(), 7 ether);
        vm.prank(FRIEND);
        escrow.onDeposit();
        assertEq(collateral.balanceOf(address(escrow)), 0);
        assertEq(pool.balanceOf(address(escrow)), 7 ether);
        assertEq(escrow.balance(), 7 ether);
    }

    function testZeroDepositDoesNotCallStake() public {
        vm.mockCallRevert(address(pool), abi.encodeWithSelector(IStakingRewards.stake.selector), "UNEXPECTED STAKE");
        escrow.onDeposit();
        assertEq(escrow.balance(), 0);
    }

    function testBalanceIncludesIdleAndStakedButExcludesRewards() public {
        _stake(10 ether);
        collateral.mint(address(escrow), 3 ether);
        _fund();
        reward.mint(address(escrow), 5 ether);
        vm.warp(block.timestamp + 100);
        assertEq(escrow.balance(), 13 ether);
        assertEq(escrow.claimable(), 105 ether);
    }

    function testPayUsesIdleCollateralWithoutCallingPool() public {
        _stake(10 ether);
        collateral.mint(address(escrow), 4 ether);
        vm.mockCallRevert(
            address(pool), abi.encodeWithSelector(IStakingRewards.withdraw.selector), "UNEXPECTED WITHDRAW"
        );
        _pay(3 ether);
        assertEq(collateral.balanceOf(RECIPIENT), 3 ether);
        assertEq(pool.balanceOf(address(escrow)), 10 ether);
        assertEq(collateral.balanceOf(address(escrow)), 1 ether);
        assertEq(escrow.balance(), 11 ether);
    }

    function testPayWithdrawsOnlyTheShortfall() public {
        _stake(10 ether);
        collateral.mint(address(escrow), 3 ether);
        vm.expectCall(address(pool), abi.encodeCall(IStakingRewards.withdraw, (4 ether)), 1);
        _pay(7 ether);
        assertEq(collateral.balanceOf(RECIPIENT), 7 ether);
        assertEq(pool.balanceOf(address(escrow)), 6 ether);
        assertEq(collateral.balanceOf(address(escrow)), 0);
        assertEq(escrow.balance(), 6 ether);
    }

    function testPayFullBalanceAndZeroPayments() public {
        _stake(10 ether);
        collateral.mint(address(escrow), 3 ether);
        _pay(13 ether);
        assertEq(escrow.balance(), 0);
        assertEq(pool.balanceOf(address(escrow)), 0);
        assertEq(collateral.balanceOf(RECIPIENT), 13 ether);
        vm.mockCallRevert(
            address(pool), abi.encodeWithSelector(IStakingRewards.withdraw.selector), "UNEXPECTED WITHDRAW"
        );
        collateral.setTransferFailure(true, address(0), false);
        _pay(0);
    }

    function testPayRejectsUnauthorizedCallersIncludingBeneficiaryAndClaimer() public {
        _stake(10 ether);
        vm.prank(BENEFICIARY);
        escrow.allowClaimOnBehalf(FRIEND);
        vm.startPrank(BENEFICIARY);
        vm.expectRevert(StakingRewardsEscrow.OnlyMarket.selector);
        escrow.pay(BENEFICIARY, 1 ether);
        vm.stopPrank();
        vm.startPrank(FRIEND);
        vm.expectRevert(StakingRewardsEscrow.OnlyMarket.selector);
        escrow.pay(FRIEND, 0);
        vm.stopPrank();
        assertEq(escrow.balance(), 10 ether);
    }

    function testPayInsufficientCollateralRevertsAtomically() public {
        _stake(10 ether);
        collateral.mint(address(escrow), 3 ether);
        vm.expectRevert();
        _pay(14 ether);
        assertEq(escrow.balance(), 13 ether);
        assertEq(pool.balanceOf(address(escrow)), 10 ether);
        assertEq(collateral.balanceOf(RECIPIENT), 0);
    }

    function testPayTransferFailureRollsBackUnstaking() public {
        _stake(10 ether);
        collateral.setTransferFailure(true, address(escrow), true);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(collateral)));
        _pay(4 ether);
        assertEq(pool.balanceOf(address(escrow)), 10 ether);
        assertEq(escrow.balance(), 10 ether);
        assertEq(collateral.balanceOf(RECIPIENT), 0);
    }

    function testFuzzPayPreservesCollateralAccounting(uint96 staked, uint96 idle, uint96 payment) public {
        _stake(staked);
        collateral.mint(address(escrow), idle);
        uint256 total = uint256(staked) + idle;
        uint256 amount = bound(uint256(payment), 0, total);
        _pay(amount);
        assertEq(escrow.balance(), total - amount);
        assertEq(collateral.balanceOf(RECIPIENT), amount);
        assertEq(pool.balanceOf(address(escrow)), amount > idle ? uint256(staked) - (amount - idle) : staked);
    }

    function testClaimAccruesRewardsWithoutChangingCollateral() public {
        _stake(10 ether);
        _fund();
        collateral.mint(address(escrow), 3 ether);
        reward.mint(address(escrow), 7 ether);
        vm.warp(block.timestamp + 100);
        assertEq(escrow.claimable(), 107 ether);
        vm.prank(BENEFICIARY);
        escrow.claim();
        assertEq(reward.balanceOf(BENEFICIARY), 107 ether);
        assertEq(reward.balanceOf(address(escrow)), 0);
        assertEq(escrow.claimable(), 0);
        assertEq(escrow.balance(), 13 ether);
        assertEq(pool.balanceOf(address(escrow)), 10 ether);
        vm.prank(BENEFICIARY);
        escrow.claim();
        assertEq(reward.balanceOf(BENEFICIARY), 107 ether);
        vm.warp(block.timestamp + 100);
        vm.prank(BENEFICIARY);
        escrow.claim();
        assertEq(reward.balanceOf(BENEFICIARY), 207 ether);
    }

    function testClaimToChosenRecipientAndHeldRewardsWithoutStake() public {
        reward.mint(address(escrow), 7 ether);
        vm.prank(BENEFICIARY);
        escrow.claimTo(RECIPIENT);
        assertEq(reward.balanceOf(RECIPIENT), 7 ether);
        assertEq(reward.balanceOf(BENEFICIARY), 0);
        assertEq(escrow.claimable(), 0);
    }

    function testClaimRejectsZeroRecipientWithoutConsumingRewards() public {
        _stake(10 ether);
        _fund();
        vm.warp(block.timestamp + 100);
        vm.prank(BENEFICIARY);
        vm.expectRevert(StakingRewardsEscrow.InvalidRecipient.selector);
        escrow.claimTo(address(0));
        assertEq(escrow.claimable(), 100 ether);
    }

    function testClaimRejectsUnauthorizedCallers() public {
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiary.selector);
        escrow.claim();
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiaryOrAllowlist.selector);
        escrow.claimTo(RECIPIENT);
        vm.prank(MARKET);
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiaryOrAllowlist.selector);
        escrow.claimTo(MARKET);
    }

    function testAllowlistGrantsAndRevokesClaimTo() public {
        reward.mint(address(escrow), 7 ether);
        vm.prank(BENEFICIARY);
        vm.expectEmit(true, false, false, true, address(escrow));
        emit AllowClaim(FRIEND, true);
        escrow.allowClaimOnBehalf(FRIEND);
        assertTrue(escrow.allowlist(FRIEND));
        vm.startPrank(FRIEND);
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiary.selector);
        escrow.claim();
        escrow.claimTo(RECIPIENT);
        vm.stopPrank();
        assertEq(reward.balanceOf(RECIPIENT), 7 ether);
        vm.prank(BENEFICIARY);
        vm.expectEmit(true, false, false, true, address(escrow));
        emit AllowClaim(FRIEND, false);
        escrow.disallowClaimOnBehalf(FRIEND);
        assertFalse(escrow.allowlist(FRIEND));
        vm.prank(FRIEND);
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiaryOrAllowlist.selector);
        escrow.claimTo(RECIPIENT);
    }

    function testOnlyBeneficiaryCanChangeAllowlist() public {
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiary.selector);
        escrow.allowClaimOnBehalf(FRIEND);
        vm.prank(BENEFICIARY);
        escrow.allowClaimOnBehalf(FRIEND);
        vm.startPrank(FRIEND);
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiary.selector);
        escrow.allowClaimOnBehalf(RECIPIENT);
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiary.selector);
        escrow.disallowClaimOnBehalf(FRIEND);
        vm.stopPrank();
    }

    function testPartialAndFullWithdrawalPreserveEarnedRewards() public {
        _stake(10 ether);
        _fund();
        vm.warp(block.timestamp + 100);
        _pay(4 ether);
        assertEq(pool.rewards(address(escrow)), 100 ether);
        assertEq(reward.balanceOf(address(escrow)), 0);
        vm.warp(block.timestamp + 300);
        _pay(6 ether);
        assertEq(escrow.balance(), 0);
        assertEq(escrow.claimable(), 400 ether);
        vm.warp(block.timestamp + DURATION);
        assertEq(escrow.claimable(), 400 ether);
        vm.prank(BENEFICIARY);
        escrow.claim();
        assertEq(reward.balanceOf(BENEFICIARY), 400 ether);
    }

    function testRewardTransferFailureDoesNotBlockWithdrawals() public {
        _stake(10 ether);
        _fund();
        vm.warp(block.timestamp + 100);
        reward.setTransferFailure(true, address(0), false);
        vm.prank(BENEFICIARY);
        vm.expectRevert("TRANSFER FAILED");
        escrow.claim();
        _pay(10 ether);
        assertEq(collateral.balanceOf(RECIPIENT), 10 ether);
        assertEq(escrow.balance(), 0);
        assertEq(escrow.claimable(), 100 ether);
        reward.setTransferFailure(false, address(0), false);
        vm.prank(BENEFICIARY);
        escrow.claim();
        assertEq(reward.balanceOf(BENEFICIARY), 100 ether);
    }

    function testForwardingFailureRollsBackPoolClaim() public {
        _stake(10 ether);
        _fund();
        vm.warp(block.timestamp + 100);
        reward.setTransferFailure(true, address(escrow), true);
        vm.prank(BENEFICIARY);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(reward)));
        escrow.claim();
        assertEq(escrow.claimable(), 100 ether);
        assertEq(reward.balanceOf(address(pool)), FUNDING);
        assertEq(reward.balanceOf(address(escrow)), 0);
        assertEq(escrow.balance(), 10 ether);
    }

    function testClonesHaveIndependentCollateralRewardsAndPermissions() public {
        StakingRewardsEscrow other = _clone(FRIEND);
        _stake(10 ether);
        collateral.mint(address(other), 30 ether);
        other.onDeposit();
        _fund();
        vm.prank(BENEFICIARY);
        escrow.allowClaimOnBehalf(RECIPIENT);
        assertFalse(other.allowlist(RECIPIENT));
        vm.warp(block.timestamp + DURATION);
        assertEq(escrow.claimable(), 250 ether);
        assertEq(other.claimable(), 750 ether);
        vm.prank(RECIPIENT);
        escrow.claimTo(BENEFICIARY);
        vm.prank(FRIEND);
        other.claim();
        _pay(10 ether);
        assertEq(escrow.balance(), 0);
        assertEq(other.balance(), 30 ether);
        assertEq(reward.balanceOf(BENEFICIARY), 250 ether);
        assertEq(reward.balanceOf(FRIEND), 750 ether);
    }

    function testClaimAndStakeAccruesRewardsAndIncludesHeldBalance() public {
        _stake(10 ether);
        collateral.mint(address(escrow), 3 ether);
        _fund();
        reward.mint(address(escrow), 7 ether);
        vm.warp(block.timestamp + 100);
        vm.expectCall(address(vault), abi.encodeCall(ERC4626.deposit, (107 ether, RECIPIENT)));
        vm.prank(BENEFICIARY);
        uint256 shares = escrow.claimAndStake(RECIPIENT, 107 ether);
        assertEq(shares, 107 ether);
        assertEq(vault.balanceOf(RECIPIENT), shares);
        assertEq(vault.balanceOf(address(escrow)), 0);
        assertEq(vault.balanceOf(BENEFICIARY), 0);
        assertEq(vault.totalAssets(), 107 ether);
        assertEq(reward.balanceOf(address(pool)), 900 ether);
        assertEq(reward.balanceOf(address(escrow)), 0);
        assertEq(reward.balanceOf(RECIPIENT), 0);
        assertEq(escrow.claimable(), 0);
        assertEq(escrow.balance(), 13 ether);
        assertEq(pool.balanceOf(address(escrow)), 10 ether);

        vm.warp(block.timestamp + 100);
        vm.prank(BENEFICIARY);
        assertEq(escrow.claimAndStake(RECIPIENT, 100 ether), 100 ether);
        assertEq(vault.balanceOf(RECIPIENT), 207 ether);
        assertEq(escrow.claimable(), 0);
    }

    function testClaimAndStakeAllowlistAndRevocation() public {
        reward.mint(address(escrow), 7 ether);
        vm.prank(FRIEND);
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiaryOrAllowlist.selector);
        escrow.claimAndStake(RECIPIENT, 0);
        vm.prank(MARKET);
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiaryOrAllowlist.selector);
        escrow.claimAndStake(RECIPIENT, 0);

        vm.prank(BENEFICIARY);
        escrow.allowClaimOnBehalf(FRIEND);
        vm.prank(FRIEND);
        assertEq(escrow.claimAndStake(FRIEND, 7 ether), 7 ether);
        assertEq(vault.balanceOf(FRIEND), 7 ether);
        assertEq(escrow.balance(), 0);

        reward.mint(address(escrow), 3 ether);
        vm.prank(BENEFICIARY);
        escrow.disallowClaimOnBehalf(FRIEND);
        vm.prank(FRIEND);
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiaryOrAllowlist.selector);
        escrow.claimAndStake(RECIPIENT, 0);
        assertEq(escrow.claimable(), 3 ether);
    }

    function testClaimAndStakeRejectsZeroReceiverBeforeClaiming() public {
        _stake(10 ether);
        _fund();
        vm.warp(block.timestamp + 100);
        vm.mockCallRevert(address(pool), abi.encodeCall(IStakingRewards.getReward, ()), "UNEXPECTED CLAIM");
        vm.prank(BENEFICIARY);
        vm.expectRevert(StakingRewardsEscrow.InvalidRecipient.selector);
        escrow.claimAndStake(address(0), 0);
        assertEq(escrow.claimable(), 100 ether);
    }

    function testClaimAndStakeZeroRewardsSkipsDepositAndEnforcesMinimum() public {
        vm.mockCallRevert(address(vault), abi.encodeWithSelector(ERC4626.deposit.selector), "UNEXPECTED DEPOSIT");
        vm.prank(BENEFICIARY);
        assertEq(escrow.claimAndStake(RECIPIENT, 0), 0);
        vm.prank(BENEFICIARY);
        vm.expectRevert(StakingRewardsEscrow.InsufficientShares.selector);
        escrow.claimAndStake(RECIPIENT, 1);
        assertEq(vault.totalSupply(), 0);
    }

    function testClaimAndStakeNonUnitSharePriceAndExactMinimum() public {
        _seedVaultWithYield();
        reward.mint(address(escrow), 100 ether);
        uint256 expectedShares = vault.previewDeposit(100 ether);
        assertLt(expectedShares, 100 ether);
        vm.prank(BENEFICIARY);
        uint256 shares = escrow.claimAndStake(RECIPIENT, expectedShares);
        assertEq(shares, expectedShares);
        assertEq(vault.balanceOf(RECIPIENT), expectedShares);
        assertEq(vault.totalAssets(), 300 ether);
        assertEq(escrow.claimable(), 0);
    }

    function testClaimAndStakeInsufficientSharesRollsBackClaimAndDeposit() public {
        _seedVaultWithYield();
        _stake(10 ether);
        _fund();
        reward.mint(address(escrow), 7 ether);
        vm.warp(block.timestamp + 100);
        uint256 expectedShares = vault.previewDeposit(107 ether);
        uint256 supplyBefore = vault.totalSupply();
        vm.prank(BENEFICIARY);
        vm.expectRevert(StakingRewardsEscrow.InsufficientShares.selector);
        escrow.claimAndStake(RECIPIENT, expectedShares + 1);
        assertEq(escrow.claimable(), 107 ether);
        assertEq(pool.earned(address(escrow)), 100 ether);
        assertEq(reward.balanceOf(address(pool)), FUNDING);
        assertEq(reward.balanceOf(address(escrow)), 7 ether);
        assertEq(vault.balanceOf(RECIPIENT), 0);
        assertEq(vault.totalSupply(), supplyBefore);
        assertEq(vault.totalAssets(), 200 ether);
        assertEq(escrow.balance(), 10 ether);
    }

    function testClaimAndStakeZeroMinimumAcceptsVaultOutput() public {
        _seedVaultWithYield();
        reward.mint(address(escrow), 100 ether);
        uint256 expectedShares = vault.previewDeposit(100 ether);
        vm.prank(BENEFICIARY);
        assertEq(escrow.claimAndStake(RECIPIENT, 0), expectedShares);
        assertEq(vault.balanceOf(RECIPIENT), expectedShares);
    }

    function testClaimAndStakeDepositFailureRollsBackPoolClaim() public {
        _stake(10 ether);
        _fund();
        vm.warp(block.timestamp + 100);
        vm.mockCallRevert(address(vault), abi.encodeWithSelector(ERC4626.deposit.selector), "DEPOSIT FAILED");
        vm.prank(BENEFICIARY);
        vm.expectRevert("DEPOSIT FAILED");
        escrow.claimAndStake(RECIPIENT, 0);
        assertEq(escrow.claimable(), 100 ether);
        assertEq(reward.balanceOf(address(pool)), FUNDING);
        assertEq(reward.balanceOf(address(escrow)), 0);
        assertEq(vault.balanceOf(RECIPIENT), 0);
        assertEq(escrow.balance(), 10 ether);
        _pay(10 ether);
        assertEq(collateral.balanceOf(RECIPIENT), 10 ether);
    }

    function testClaimAndStakeRewardTransferFailurePreservesRewards() public {
        _stake(10 ether);
        _fund();
        vm.warp(block.timestamp + 100);
        reward.setTransferFailure(true, address(pool), true);
        vm.prank(BENEFICIARY);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(reward)));
        escrow.claimAndStake(RECIPIENT, 0);
        assertEq(escrow.claimable(), 100 ether);
        assertEq(reward.balanceOf(address(pool)), FUNDING);
        assertEq(vault.totalSupply(), 0);
    }

    function testClaimAndStakeTransferFromFailureRollsBackPoolClaim() public {
        _stake(10 ether);
        _fund();
        vm.warp(block.timestamp + 100);
        vm.mockCall(
            address(reward),
            abi.encodeCall(IERC20.transferFrom, (address(escrow), address(vault), 100 ether)),
            abi.encode(false)
        );
        vm.prank(BENEFICIARY);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(reward)));
        escrow.claimAndStake(RECIPIENT, 0);
        assertEq(escrow.claimable(), 100 ether);
        assertEq(reward.balanceOf(address(pool)), FUNDING);
        assertEq(reward.balanceOf(address(escrow)), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
    }

    function testNoReturnTokensCanClaimAndStakeAfterFullWithdrawal() public {
        collateral.setReturnNothing(true);
        reward.setReturnNothing(true);
        escrow = _clone(BENEFICIARY);
        _stake(10 ether);
        _fund();
        vm.warp(block.timestamp + 100);
        _pay(10 ether);
        assertEq(escrow.balance(), 0);
        vm.prank(BENEFICIARY);
        assertEq(escrow.claimAndStake(RECIPIENT, 100 ether), 100 ether);
        assertEq(vault.balanceOf(RECIPIENT), 100 ether);
        assertEq(escrow.claimable(), 0);
    }

    function testClaimAndStakeClonesHaveIndependentRewardsAndPermissions() public {
        StakingRewardsEscrow other = _clone(FRIEND);
        _stake(10 ether);
        collateral.mint(address(other), 30 ether);
        other.onDeposit();
        _fund();
        vm.warp(block.timestamp + DURATION);
        vm.prank(BENEFICIARY);
        escrow.allowClaimOnBehalf(RECIPIENT);
        assertFalse(other.allowlist(RECIPIENT));
        vm.prank(RECIPIENT);
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiaryOrAllowlist.selector);
        other.claimAndStake(RECIPIENT, 0);
        vm.prank(RECIPIENT);
        assertEq(escrow.claimAndStake(BENEFICIARY, 250 ether), 250 ether);
        assertEq(other.claimable(), 750 ether);
        assertEq(other.balance(), 30 ether);
        vm.prank(FRIEND);
        assertEq(other.claimAndStake(FRIEND, 750 ether), 750 ether);
        assertEq(vault.balanceOf(BENEFICIARY), 250 ether);
        assertEq(vault.balanceOf(FRIEND), 750 ether);
        assertEq(escrow.claimable(), 0);
        assertEq(other.claimable(), 0);
    }

    function testClaimAndStakeBlocksReentrancyDuringClaimAndDeposit() public {
        _stake(10 ether);
        _fund();
        vm.prank(BENEFICIARY);
        escrow.allowClaimOnBehalf(address(reward));
        vm.warp(block.timestamp + 100);
        reward.setCallback(
            address(pool), address(escrow), abi.encodeCall(StakingRewardsEscrow.claimAndStake, (FRIEND, 0))
        );
        vm.prank(BENEFICIARY);
        escrow.claimAndStake(RECIPIENT, 100 ether);
        _assertReentrancyBlocked(reward);

        vm.warp(block.timestamp + 100);
        reward.setCallback(address(vault), address(escrow), abi.encodeCall(StakingRewardsEscrow.claimTo, (FRIEND)));
        vm.prank(BENEFICIARY);
        escrow.claimAndStake(RECIPIENT, 100 ether);
        _assertReentrancyBlocked(reward);

        vm.warp(block.timestamp + 100);
        reward.setCallback(address(vault), address(escrow), abi.encodeCall(StakingRewardsEscrow.onDeposit, ()));
        vm.prank(BENEFICIARY);
        escrow.claimAndStake(RECIPIENT, 100 ether);
        _assertReentrancyBlocked(reward);
        assertEq(vault.balanceOf(RECIPIENT), 300 ether);
        assertEq(vault.balanceOf(FRIEND), 0);
        assertEq(reward.balanceOf(FRIEND), 0);
        assertEq(escrow.balance(), 10 ether);
    }

    function testClaimToBlocksReentrancyIntoClaimAndStake() public {
        _stake(10 ether);
        _fund();
        vm.prank(BENEFICIARY);
        escrow.allowClaimOnBehalf(address(reward));
        vm.warp(block.timestamp + 100);
        reward.setCallback(
            address(pool), address(escrow), abi.encodeCall(StakingRewardsEscrow.claimAndStake, (FRIEND, 0))
        );
        vm.prank(BENEFICIARY);
        escrow.claimTo(RECIPIENT);
        _assertReentrancyBlocked(reward);
        assertEq(reward.balanceOf(RECIPIENT), 100 ether);
        assertEq(vault.totalSupply(), 0);
    }

    function testInitializeBlocksRewardApprovalReentrancy() public {
        StakingRewardsEscrow instance = StakingRewardsEscrow(Clones.clone(address(implementation)));
        reward.setCallback(address(instance), address(instance), abi.encodeCall(StakingRewardsEscrow.onDeposit, ()));
        vm.prank(MARKET);
        instance.initialize(collateral, BENEFICIARY);
        _assertReentrancyBlocked(reward);
        assertEq(reward.allowance(address(instance), address(vault)), type(uint256).max);
        assertEq(instance.market(), MARKET);
    }

    function testInitializeBlocksApprovalReentrancy() public {
        StakingRewardsEscrow instance = StakingRewardsEscrow(Clones.clone(address(implementation)));
        collateral.setCallback(address(instance), address(instance), abi.encodeCall(StakingRewardsEscrow.onDeposit, ()));
        vm.prank(MARKET);
        instance.initialize(collateral, BENEFICIARY);
        _assertReentrancyBlocked(collateral);
        assertEq(instance.market(), MARKET);
    }

    function testStakeBlocksTokenReentrancy() public {
        collateral.setCallback(address(pool), address(escrow), abi.encodeCall(StakingRewardsEscrow.onDeposit, ()));
        _stake(10 ether);
        _assertReentrancyBlocked(collateral);
        assertEq(escrow.balance(), 10 ether);
    }

    function testPayBlocksReentrancyDuringUnstakeAndTransfer() public {
        _stake(10 ether);
        collateral.setCallback(address(pool), address(escrow), abi.encodeCall(StakingRewardsEscrow.onDeposit, ()));
        _pay(4 ether);
        _assertReentrancyBlocked(collateral);
        collateral.setCallback(address(escrow), address(escrow), abi.encodeCall(StakingRewardsEscrow.onDeposit, ()));
        _pay(6 ether);
        _assertReentrancyBlocked(collateral);
        assertEq(collateral.balanceOf(RECIPIENT), 10 ether);
        assertEq(escrow.balance(), 0);
    }

    function testClaimBlocksCrossFunctionAndAuthorizedClaimReentrancy() public {
        _stake(10 ether);
        _fund();
        vm.warp(block.timestamp + 100);
        reward.setCallback(address(pool), address(escrow), abi.encodeCall(StakingRewardsEscrow.onDeposit, ()));
        vm.prank(BENEFICIARY);
        escrow.claim();
        _assertReentrancyBlocked(reward);
        vm.prank(BENEFICIARY);
        escrow.allowClaimOnBehalf(address(reward));
        vm.warp(block.timestamp + 100);
        reward.setCallback(address(escrow), address(escrow), abi.encodeCall(StakingRewardsEscrow.claimTo, (FRIEND)));
        vm.prank(BENEFICIARY);
        escrow.claim();
        _assertReentrancyBlocked(reward);
        assertEq(reward.balanceOf(BENEFICIARY), 200 ether);
        assertEq(reward.balanceOf(FRIEND), 0);
        assertEq(escrow.balance(), 10 ether);
    }
}

contract StakingRewardsEscrowMarketTest is FiRMBaseTest {
    EscrowTestToken reward;
    StakingRewardsFixture pool;
    EscrowTestVault vault;
    StakingRewardsEscrow stakingImplementation;

    function setUp() public {
        initialize(replenishmentPriceBps, collateralFactorBps, replenishmentIncentiveBps, liquidationBonusBps, false);
        reward = new EscrowTestToken();
        vault = new EscrowTestVault(reward);
        pool = new StakingRewardsFixture(address(WETH), address(reward), address(this), 1000);
        stakingImplementation = new StakingRewardsEscrow(address(pool), address(vault));
        market = new Market(
            gov,
            address(fed),
            pauseGuardian,
            address(stakingImplementation),
            IDolaBorrowingRights(address(dbr)),
            MarketIERC20(address(WETH)),
            IOracle(address(oracle)),
            collateralFactorBps,
            replenishmentIncentiveBps,
            liquidationBonusBps,
            true
        );
        vm.prank(gov);
        dbr.addMarket(address(market));
        gibDOLA(address(market), 1_000_000 ether);
        gibDBR(user, 10_000 ether);
        gibWeth(user, 2 ether);
    }

    function _escrow(address account) internal view returns (StakingRewardsEscrow) {
        return StakingRewardsEscrow(address(market.escrows(account)));
    }

    function _depositAndBorrow() internal {
        vm.startPrank(user, user);
        WETH.approve(address(market), 2 ether);
        market.depositAndBorrow(2 ether, 2000 ether);
        vm.stopPrank();
    }

    function _fundAndAccrue() internal {
        reward.mint(address(pool), 1000 ether);
        pool.notifyRewardAmount(1000 ether);
        vm.warp(block.timestamp + 100);
        ethFeed.changeUpdatedAt(block.timestamp);
    }

    function testMarketDepositAndBorrowUsesCloneAndStakedCollateral() public {
        address predicted = address(market.predictEscrow(user));
        _depositAndBorrow();
        StakingRewardsEscrow instance = _escrow(user);
        assertEq(address(instance), predicted);
        assertEq(instance.market(), address(market));
        assertEq(instance.beneficiary(), user);
        assertEq(pool.balanceOf(address(instance)), 2 ether);
        assertEq(WETH.balanceOf(address(instance)), 0);
        assertEq(market.getCreditLimit(user), 3400 ether);
        assertEq(market.debts(user), 2000 ether);
        assertEq(DOLA.balanceOf(user), 2000 ether);
        _fundAndAccrue();
        assertEq(market.getCreditLimit(user), 3400 ether);
        vm.prank(user);
        instance.claim();
        assertEq(reward.balanceOf(user), 100 ether);
        assertEq(instance.balance(), 2 ether);
    }

    function testMarketDepositForAnotherBorrowerIsIsolated() public {
        vm.startPrank(user, user);
        WETH.approve(address(market), 2 ether);
        market.deposit(1 ether);
        market.deposit(user2, 1 ether);
        vm.stopPrank();
        StakingRewardsEscrow first = _escrow(user);
        StakingRewardsEscrow second = _escrow(user2);
        assertTrue(address(first) != address(second));
        assertEq(first.beneficiary(), user);
        assertEq(second.beneficiary(), user2);
        assertEq(pool.balanceOf(address(first)), 1 ether);
        assertEq(pool.balanceOf(address(second)), 1 ether);
        _fundAndAccrue();
        vm.prank(user2);
        second.claim();
        assertEq(reward.balanceOf(user2), 50 ether);
        assertEq(first.claimable(), 50 ether);
    }

    function testMarketCloneClaimAndStakePreservesCollateralAndCredit() public {
        _depositAndBorrow();
        _fundAndAccrue();
        StakingRewardsEscrow instance = _escrow(user);
        uint256 creditBefore = market.getCreditLimit(user);
        uint256 debtBefore = market.debts(user);
        vm.prank(user);
        uint256 shares = instance.claimAndStake(user2, 100 ether);
        assertEq(shares, 100 ether);
        assertEq(vault.balanceOf(user2), shares);
        assertEq(vault.balanceOf(user), 0);
        assertEq(vault.balanceOf(address(instance)), 0);
        assertEq(reward.balanceOf(address(instance)), 0);
        assertEq(instance.claimable(), 0);
        assertEq(instance.balance(), 2 ether);
        assertEq(pool.balanceOf(address(instance)), 2 ether);
        assertEq(market.getCreditLimit(user), creditBefore);
        assertEq(market.debts(user), debtBefore);
    }

    function testMarketPartialWithdrawalRepaymentAndFullWithdrawal() public {
        _depositAndBorrow();
        _fundAndAccrue();
        StakingRewardsEscrow instance = _escrow(user);
        vm.startPrank(user, user);
        market.withdraw(0.5 ether);
        assertEq(instance.balance(), 1.5 ether);
        assertEq(WETH.balanceOf(user), 0.5 ether);
        vm.expectRevert("Insufficient withdrawal limit");
        market.withdraw(1 ether);
        DOLA.approve(address(market), type(uint256).max);
        market.repayAndWithdraw(type(uint256).max, 1.5 ether);
        instance.claim();
        vm.stopPrank();
        assertEq(instance.balance(), 0);
        assertEq(pool.balanceOf(address(instance)), 0);
        assertEq(market.debts(user), 0);
        assertEq(WETH.balanceOf(user), 2 ether);
        assertEq(reward.balanceOf(user), 100 ether);
    }

    function testMarketWithdrawMaxWorksWhenRewardsFail() public {
        vm.startPrank(user, user);
        deposit(2 ether);
        vm.stopPrank();
        _fundAndAccrue();
        StakingRewardsEscrow instance = _escrow(user);
        reward.setTransferFailure(true, address(0), false);
        vm.startPrank(user, user);
        vm.expectRevert("TRANSFER FAILED");
        instance.claim();
        market.withdrawMax();
        vm.stopPrank();
        assertEq(WETH.balanceOf(user), 2 ether);
        assertEq(instance.balance(), 0);
        assertEq(instance.claimable(), 100 ether);
    }

    function testMarketLiquidationPaysLiquidatorAndGovernanceDespiteRewardFailure() public {
        _depositAndBorrow();
        _fundAndAccrue();
        reward.setTransferFailure(true, address(0), false);
        vm.prank(gov);
        market.setLiquidationFeeBps(100);
        ethFeed.changeAnswer(1000 ether);
        uint256 repayment = 1000 ether;
        gibDOLA(user2, repayment);
        uint256 govBalance = WETH.balanceOf(gov);
        vm.startPrank(user2, user2);
        DOLA.approve(address(market), repayment);
        market.liquidate(user, repayment);
        vm.stopPrank();
        StakingRewardsEscrow instance = _escrow(user);
        assertEq(WETH.balanceOf(user2), 1.01 ether);
        assertEq(WETH.balanceOf(gov) - govBalance, 0.01 ether);
        assertEq(instance.balance(), 0.98 ether);
        assertEq(pool.balanceOf(address(instance)), 0.98 ether);
        assertEq(market.debts(user), 1000 ether);
        assertEq(instance.claimable(), 100 ether);
        assertEq(reward.balanceOf(user2), 0);
        reward.setTransferFailure(false, address(0), false);
        vm.prank(user);
        instance.claim();
        assertEq(reward.balanceOf(user), 100 ether);
    }
}
