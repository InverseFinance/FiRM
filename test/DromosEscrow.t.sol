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

    error NotAuthorized();
    error ZeroAddress();
    error ZeroAmount();

    address public immutable stakingToken;
    MockDromosToken public immutable rewardToken;

    mapping(address account => uint256 amount) public balanceOf;
    mapping(address account => uint256 amount) public earned;

    uint256 public claimCalls;
    uint256 public depositCalls;
    uint256 public withdrawCalls;

    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = _stakingToken;
        rewardToken = MockDromosToken(_rewardToken);
    }

    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        depositCalls++;
        IERC20(stakingToken).safeTransferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        withdrawCalls++;

        // V2Gauge claims emissions to the caller before reducing its stake.
        _claimEmissions(msg.sender, msg.sender);

        balanceOf[msg.sender] -= amount;
        IERC20(stakingToken).safeTransfer(msg.sender, amount);
    }

    function claimEmissions(address account, address recipient) external {
        if (recipient == address(0)) revert ZeroAddress();
        if (msg.sender != account) revert NotAuthorized();

        _claimEmissions(account, recipient);
    }

    function setReward(address account, uint256 amount) external {
        earned[account] = amount;
    }

    function _claimEmissions(address account, address recipient) internal {
        claimCalls++;
        uint256 amount = earned[account];
        delete earned[account];
        if (amount != 0) rewardToken.mint(recipient, amount);
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

    event Claim(address indexed caller, address indexed receiver, uint256 amount);
    event SetClaimer(address indexed claimer, bool isAllowed);

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

    function testInitializeSetsConfigurationAndApproval() public view {
        assertEq(address(escrow.gauge()), address(gauge));
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

    function testInitializeRejectsZeroBeneficiary() public {
        DromosEscrow freshEscrow = new DromosEscrow(address(gauge));

        vm.prank(MARKET);
        vm.expectRevert(DromosEscrow.InvalidReceiver.selector);
        freshEscrow.initialize(IERC20(address(collateral)), address(0));
    }

    function testInitializeRejectsEscrowAsBeneficiary() public {
        DromosEscrow freshEscrow = new DromosEscrow(address(gauge));

        vm.prank(MARKET);
        vm.expectRevert(DromosEscrow.InvalidReceiver.selector);
        freshEscrow.initialize(IERC20(address(collateral)), address(freshEscrow));
    }

    function testOnDepositMarketStakesEntireBalanceForBeneficiaryOrigin() public {
        collateral.mint(address(escrow), 10 ether);

        vm.prank(MARKET, BENEFICIARY);
        escrow.onDeposit();

        assertEq(collateral.balanceOf(address(escrow)), 0);
        assertEq(gauge.balanceOf(address(escrow)), 10 ether);
        assertEq(escrow.balance(), 10 ether);
        assertEq(gauge.depositCalls(), 1);
    }

    function testOnDepositBeneficiaryCanStakeDirectly() public {
        collateral.mint(address(escrow), 10 ether);

        vm.prank(BENEFICIARY, BENEFICIARY);
        escrow.onDeposit();

        assertEq(gauge.balanceOf(address(escrow)), 10 ether);
    }

    function testOnDepositRejectsMarketCallWithNonBeneficiaryOrigin() public {
        collateral.mint(address(escrow), 10 ether);

        vm.prank(MARKET, OTHER);
        vm.expectRevert(DromosEscrow.OnlyBeneficiaryOrigin.selector);
        escrow.onDeposit();

        assertEq(collateral.balanceOf(address(escrow)), 10 ether);
        assertEq(gauge.balanceOf(address(escrow)), 0);
    }

    function testOnDepositRejectsUnauthorizedCaller() public {
        collateral.mint(address(escrow), 10 ether);

        vm.prank(OTHER, OTHER);
        vm.expectRevert(DromosEscrow.OnlyMarketOrBeneficiary.selector);
        escrow.onDeposit();
    }

    function testOnDepositRejectsIntermediaryWithBeneficiaryOrigin() public {
        collateral.mint(address(escrow), 10 ether);

        vm.prank(OTHER, BENEFICIARY);
        vm.expectRevert(DromosEscrow.OnlyMarketOrBeneficiary.selector);
        escrow.onDeposit();
    }

    function testOnDepositWithZeroBalanceIsNoOp() public {
        vm.prank(MARKET, BENEFICIARY);
        escrow.onDeposit();

        assertEq(gauge.balanceOf(address(escrow)), 0);
        assertEq(escrow.balance(), 0);
        assertEq(gauge.depositCalls(), 0);
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
        assertEq(gauge.claimCalls(), 0);
        assertEq(gauge.withdrawCalls(), 0);
    }

    function testPayWithdrawsMissingCollateralFromGauge() public {
        _deposit(10 ether);

        vm.prank(MARKET);
        escrow.pay(RECEIVER, 6 ether);

        assertEq(collateral.balanceOf(RECEIVER), 6 ether);
        assertEq(gauge.balanceOf(address(escrow)), 4 ether);
        assertEq(escrow.balance(), 4 ether);
        assertEq(gauge.claimCalls(), 2);
        assertEq(gauge.withdrawCalls(), 1);
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

        assertEq(gauge.earned(address(escrow)), 0);
        assertEq(gauge.claimCalls(), 0);
    }

    function testPayUsingUnstakedCollateralDoesNotClaimEmissions() public {
        collateral.mint(address(escrow), 10 ether);
        _setReward(2 ether);

        vm.prank(MARKET);
        escrow.pay(RECEIVER, 5 ether);

        assertEq(gauge.earned(address(escrow)), 2 ether);
        assertEq(reward.balanceOf(BENEFICIARY), 0);
        assertEq(gauge.claimCalls(), 0);
    }

    function testPayClaimsEmissionsToBeneficiaryBeforeWithdrawal() public {
        _deposit(10 ether);
        _setReward(2 ether);

        vm.expectEmit(true, true, false, true, address(escrow));
        emit Claim(MARKET, BENEFICIARY, 2 ether);
        vm.prank(MARKET);
        escrow.pay(RECEIVER, 5 ether);

        assertEq(gauge.earned(address(escrow)), 0);
        assertEq(reward.balanceOf(address(escrow)), 0);
        assertEq(reward.balanceOf(BENEFICIARY), 2 ether);
        assertEq(gauge.claimCalls(), 2);
    }

    function testBeneficiaryCanClaimToSelf() public {
        _deposit(10 ether);
        _setReward(2 ether);

        vm.prank(BENEFICIARY);
        escrow.claim();

        assertEq(reward.balanceOf(BENEFICIARY), 2 ether);
        assertEq(reward.balanceOf(address(escrow)), 0);
        assertEq(gauge.earned(address(escrow)), 0);
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

    function testSetClaimerEmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(escrow));
        emit SetClaimer(CLAIMER, true);

        vm.prank(BENEFICIARY);
        escrow.setClaimer(CLAIMER, true);

        assertTrue(escrow.allowlist(CLAIMER));
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

    function testUnauthorizedAddressCannotClaimToBeneficiary() public {
        vm.prank(OTHER);
        vm.expectRevert(DromosEscrow.OnlyBeneficiary.selector);
        escrow.claim();
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
        assertEq(gauge.claimCalls(), 1);
    }

    function testRewardsAreClaimedDuringFullWithdrawal() public {
        _deposit(10 ether);
        _setReward(2 ether);

        vm.prank(MARKET);
        escrow.pay(RECEIVER, 10 ether);

        assertEq(escrow.balance(), 0);
        assertEq(reward.balanceOf(BENEFICIARY), 2 ether);
        assertEq(reward.balanceOf(address(escrow)), 0);
        assertEq(gauge.earned(address(escrow)), 0);
        assertEq(gauge.claimCalls(), 2);
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

    function testGaugeRejectsClaimByNonAccount() public {
        _setReward(2 ether);

        vm.expectRevert(MockDromosGauge.NotAuthorized.selector);
        gauge.claimEmissions(address(escrow), RECEIVER);

        assertEq(gauge.earned(address(escrow)), 2 ether);
    }

    function _deposit(uint256 amount) internal {
        collateral.mint(address(escrow), amount);

        vm.prank(MARKET, BENEFICIARY);
        escrow.onDeposit();
    }

    function _setReward(uint256 amount) internal {
        gauge.setReward(address(escrow), amount);
    }
}
