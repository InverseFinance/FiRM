// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {DromosEscrow, IDromosGauge} from "src/escrows/DromosEscrow.sol";

contract MockDromosToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}

contract MockDromosGauge is IDromosGauge {
    using SafeERC20 for IERC20;

    address public immutable stakingToken;
    address public immutable rewardToken;

    mapping(address account => uint256 amount) public balanceOf;
    mapping(address account => uint256 amount) public claimable;

    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = _stakingToken;
        rewardToken = _rewardToken;
    }

    function deposit(uint256 amount) external {
        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        IERC20(stakingToken).safeTransfer(msg.sender, amount);
    }

    function getReward(address account) external {
        uint256 amount = claimable[account];
        claimable[account] = 0;
        if (amount != 0) IERC20(rewardToken).safeTransfer(account, amount);
    }

    function setReward(address account, uint256 amount) external {
        claimable[account] = amount;
    }
}

contract DromosEscrowTest is Test {
    address internal constant MARKET = address(0xA);
    address internal constant BENEFICIARY = address(0xB);
    address internal constant CLAIMER = address(0xC);
    address internal constant RECEIVER = address(0xD);
    address internal constant OTHER = address(0xE);

    MockDromosToken internal collateral;
    MockDromosToken internal reward;
    MockDromosGauge internal gauge;
    DromosEscrow internal escrow;

    function setUp() public {
        collateral = new MockDromosToken("LP Token", "LP");
        reward = new MockDromosToken("Emission Token", "EMIT");
        gauge = new MockDromosGauge(address(collateral), address(reward));
        escrow = new DromosEscrow(address(gauge));

        vm.prank(MARKET);
        escrow.initialize(IERC20(address(collateral)), BENEFICIARY);
    }

    function testConstructorRejectsNonContractGauge() public {
        vm.expectRevert(DromosEscrow.InvalidGauge.selector);
        new DromosEscrow(address(0x1234));
    }

    function testConstructorRejectsZeroToken() public {
        MockDromosGauge invalidGauge = new MockDromosGauge(address(0), address(reward));

        vm.expectRevert(DromosEscrow.InvalidGauge.selector);
        new DromosEscrow(address(invalidGauge));
    }

    function testConstructorRejectsCollateralAsRewardToken() public {
        MockDromosGauge unsafeGauge = new MockDromosGauge(address(collateral), address(collateral));

        vm.expectRevert(DromosEscrow.UnsafeRewardToken.selector);
        new DromosEscrow(address(unsafeGauge));
    }

    function testInitializeSetsConfigurationAndApproval() public view {
        assertEq(address(escrow.gauge()), address(gauge));
        assertEq(address(escrow.rewardToken()), address(reward));
        assertEq(address(escrow.token()), address(collateral));
        assertEq(escrow.market(), MARKET);
        assertEq(escrow.beneficiary(), BENEFICIARY);
        assertEq(collateral.allowance(address(escrow), address(gauge)), type(uint256).max);
    }

    function testInitializeRejectsSecondInitialization() public {
        vm.expectRevert(DromosEscrow.AlreadyInitialized.selector);
        escrow.initialize(IERC20(address(collateral)), BENEFICIARY);
    }

    function testInitializeRejectsWrongCollateral() public {
        DromosEscrow freshEscrow = new DromosEscrow(address(gauge));
        MockDromosToken wrongToken = new MockDromosToken("Wrong", "WRONG");

        vm.expectRevert(DromosEscrow.WrongCollateral.selector);
        freshEscrow.initialize(IERC20(address(wrongToken)), BENEFICIARY);
    }

    function testOnDepositStakesEntireBalancePermissionlessly() public {
        collateral.mint(address(escrow), 10 ether);

        vm.prank(OTHER);
        escrow.onDeposit();

        assertEq(collateral.balanceOf(address(escrow)), 0);
        assertEq(gauge.balanceOf(address(escrow)), 10 ether);
        assertEq(escrow.balance(), 10 ether);
    }

    function testOnDepositWithZeroBalanceIsNoOp() public {
        escrow.onDeposit();

        assertEq(gauge.balanceOf(address(escrow)), 0);
        assertEq(escrow.balance(), 0);
    }

    function testOnDepositSupportsRepeatedDeposits() public {
        _deposit(4 ether);
        _deposit(6 ether);

        assertEq(gauge.balanceOf(address(escrow)), 10 ether);
        assertEq(escrow.balance(), 10 ether);
    }

    function testBalanceIncludesStakedAndUnstakedCollateral() public {
        _deposit(7 ether);
        collateral.mint(address(escrow), 3 ether);

        assertEq(escrow.balance(), 10 ether);
    }

    function testPayRejectsNonMarket() public {
        collateral.mint(address(escrow), 1 ether);

        vm.expectRevert(DromosEscrow.OnlyMarket.selector);
        escrow.pay(RECEIVER, 1 ether);
    }

    function testPayUsesUnstakedCollateralFirst() public {
        collateral.mint(address(escrow), 10 ether);

        vm.prank(MARKET);
        escrow.pay(RECEIVER, 6 ether);

        assertEq(collateral.balanceOf(RECEIVER), 6 ether);
        assertEq(collateral.balanceOf(address(escrow)), 4 ether);
        assertEq(gauge.balanceOf(address(escrow)), 0);
    }

    function testPayWithdrawsMissingCollateralFromGauge() public {
        _deposit(10 ether);

        vm.prank(MARKET);
        escrow.pay(RECEIVER, 6 ether);

        assertEq(collateral.balanceOf(RECEIVER), 6 ether);
        assertEq(gauge.balanceOf(address(escrow)), 4 ether);
        assertEq(escrow.balance(), 4 ether);
    }

    function testPayUsesMixedUnstakedAndStakedCollateral() public {
        _deposit(7 ether);
        collateral.mint(address(escrow), 3 ether);

        vm.prank(MARKET);
        escrow.pay(RECEIVER, 5 ether);

        assertEq(collateral.balanceOf(RECEIVER), 5 ether);
        assertEq(collateral.balanceOf(address(escrow)), 0);
        assertEq(gauge.balanceOf(address(escrow)), 5 ether);
    }

    function testPayCanWithdrawFullBalance() public {
        _deposit(10 ether);

        vm.prank(MARKET);
        escrow.pay(RECEIVER, 10 ether);

        assertEq(collateral.balanceOf(RECEIVER), 10 ether);
        assertEq(escrow.balance(), 0);
    }

    function testPayRevertsWhenAmountExceedsBalance() public {
        _deposit(10 ether);

        vm.prank(MARKET);
        vm.expectRevert();
        escrow.pay(RECEIVER, 11 ether);
    }

    function testPayDoesNotClaimEmissions() public {
        _deposit(10 ether);
        _setReward(2 ether);

        vm.prank(MARKET);
        escrow.pay(RECEIVER, 5 ether);

        assertEq(gauge.claimable(address(escrow)), 2 ether);
        assertEq(reward.balanceOf(address(escrow)), 0);
        assertEq(reward.balanceOf(BENEFICIARY), 0);
    }

    function testBeneficiaryCanClaimToSelf() public {
        _deposit(10 ether);
        _setReward(2 ether);

        vm.prank(BENEFICIARY);
        escrow.claim();

        assertEq(reward.balanceOf(BENEFICIARY), 2 ether);
        assertEq(reward.balanceOf(address(escrow)), 0);
        assertEq(gauge.claimable(address(escrow)), 0);
    }

    function testBeneficiaryCanClaimToReceiver() public {
        _deposit(10 ether);
        _setReward(2 ether);

        vm.prank(BENEFICIARY);
        escrow.claimTo(RECEIVER);

        assertEq(reward.balanceOf(RECEIVER), 2 ether);
    }

    function testAllowlistedClaimerCanClaimToReceiver() public {
        _deposit(10 ether);
        _setReward(2 ether);

        vm.prank(BENEFICIARY);
        escrow.setClaimer(CLAIMER, true);

        vm.prank(CLAIMER);
        escrow.claimTo(RECEIVER);

        assertEq(reward.balanceOf(RECEIVER), 2 ether);
    }

    function testRevokedClaimerCannotClaim() public {
        vm.startPrank(BENEFICIARY);
        escrow.setClaimer(CLAIMER, true);
        escrow.setClaimer(CLAIMER, false);
        vm.stopPrank();

        vm.prank(CLAIMER);
        vm.expectRevert(DromosEscrow.OnlyBeneficiaryOrAllowlist.selector);
        escrow.claimTo(RECEIVER);
    }

    function testUnauthorizedAddressCannotClaim() public {
        vm.prank(OTHER);
        vm.expectRevert(DromosEscrow.OnlyBeneficiaryOrAllowlist.selector);
        escrow.claimTo(RECEIVER);
    }

    function testOnlyBeneficiaryCanSetClaimer() public {
        vm.prank(OTHER);
        vm.expectRevert(DromosEscrow.OnlyBeneficiary.selector);
        escrow.setClaimer(CLAIMER, true);
    }

    function testClaimRejectsZeroReceiver() public {
        vm.prank(BENEFICIARY);
        vm.expectRevert(DromosEscrow.InvalidReceiver.selector);
        escrow.claimTo(address(0));
    }

    function testClaimRejectsEscrowReceiver() public {
        vm.prank(BENEFICIARY);
        vm.expectRevert(DromosEscrow.InvalidReceiver.selector);
        escrow.claimTo(address(escrow));
    }

    function testClaimWithNoRewardsIsNoOp() public {
        vm.prank(BENEFICIARY);
        escrow.claim();

        assertEq(reward.balanceOf(BENEFICIARY), 0);
    }

    function testRewardsRemainClaimableAfterFullWithdrawal() public {
        _deposit(10 ether);
        _setReward(2 ether);

        vm.prank(MARKET);
        escrow.pay(RECEIVER, 10 ether);

        vm.prank(BENEFICIARY);
        escrow.claim();

        assertEq(escrow.balance(), 0);
        assertEq(reward.balanceOf(BENEFICIARY), 2 ether);
    }

    function testClaimDoesNotReduceCollateralBalance() public {
        _deposit(10 ether);
        _setReward(2 ether);
        uint256 collateralBalance = escrow.balance();

        vm.prank(BENEFICIARY);
        escrow.claim();

        assertEq(escrow.balance(), collateralBalance);
        assertEq(reward.balanceOf(BENEFICIARY), 2 ether);
    }

    function _deposit(uint256 amount) internal {
        collateral.mint(address(escrow), amount);
        escrow.onDeposit();
    }

    function _setReward(uint256 amount) internal {
        reward.mint(address(gauge), amount);
        gauge.setReward(address(escrow), amount);
    }
}
