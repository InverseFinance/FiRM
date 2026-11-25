// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {DromosEscrow, IDromosGauge} from "src/escrows/DromosEscrow.sol";

contract MockDromosToken is ERC20 {
    /// @dev Models an address that cannot receive this token (blocklist, reverting hook, ...).
    address public blockedRecipient;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function setBlockedRecipient(address account) external {
        blockedRecipient = account;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (to != address(0) && to == blockedRecipient) revert("RECIPIENT_BLOCKED");
        super._update(from, to, value);
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


    /// @dev Records gauge-approval calls so tests can assert the escrow never makes one.
    uint256 public approveCalls;
    uint256 public setApprovalForAllCalls;

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

    /// @dev Gauge.withdrawFrom pays principal to msg.sender, so granting either of these to anyone would
    ///      let them drain the escrow's stake. Present only so tests can prove the escrow never calls them.
    function approve(address, uint256) external { approveCalls++; }
    function setApprovalForAll(address, bool) external { setApprovalForAllCalls++; }

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

/// @dev A contract beneficiary (Safe / DAO / ERC-4337 account). tx.origin is never this address.
contract MockContractBeneficiary {
    function stake(DromosEscrow escrow, uint256 amount) external {
        escrow.depositAndStake(amount);
    }

    function approve(IERC20 token, address spender, uint256 amount) external {
        token.approve(spender, amount);
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
    event Stake(address indexed caller, uint256 amount);

    function setUp() public {
        collateral = new MockDromosToken("LP Token", "LP");
        reward = new MockDromosToken("Emission Token", "EMIT");
        gauge = new MockDromosGauge(address(collateral), address(reward));
        escrow = new DromosEscrow(address(gauge), address(reward));

        vm.prank(MARKET);
        escrow.initialize(IERC20(address(collateral)), BENEFICIARY);
    }

    function testConstructorRejectsNonContractGauge() public {
        vm.expectRevert(DromosEscrow.InvalidGauge.selector);
        new DromosEscrow(address(0x1234), address(reward));
    }

    function testConstructorRejectsZeroToken() public {
        MockDromosGauge invalidGauge = new MockDromosGauge(address(0), address(reward));

        vm.expectRevert(DromosEscrow.InvalidGauge.selector);
        new DromosEscrow(address(invalidGauge), address(reward));
    }

    /// @dev Security-critical: `pay` forwards the escrow's whole rewardToken balance to the beneficiary,
    ///      so a rewardToken equal to the collateral would hand over the borrower's collateral.
    function testConstructorRejectsRewardTokenEqualToCollateral() public {
        vm.expectRevert(DromosEscrow.UnsafeRewardToken.selector);
        new DromosEscrow(address(gauge), address(collateral));
    }

    function testConstructorRejectsZeroRewardToken() public {
        vm.expectRevert(DromosEscrow.UnsafeRewardToken.selector);
        new DromosEscrow(address(gauge), address(0));
    }

    function testConstructorStoresRewardToken() public view {
        assertEq(address(escrow.rewardToken()), address(reward));
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
        DromosEscrow freshEscrow = new DromosEscrow(address(gauge), address(reward));
        MockDromosToken wrongToken = new MockDromosToken("Wrong", "WRONG");

        vm.expectRevert(DromosEscrow.WrongCollateral.selector);
        freshEscrow.initialize(IERC20(address(wrongToken)), BENEFICIARY);
    }

    function testInitializeRejectsZeroBeneficiary() public {
        DromosEscrow freshEscrow = new DromosEscrow(address(gauge), address(reward));

        vm.prank(MARKET);
        vm.expectRevert(DromosEscrow.InvalidReceiver.selector);
        freshEscrow.initialize(IERC20(address(collateral)), address(0));
    }

    function testInitializeRejectsEscrowAsBeneficiary() public {
        DromosEscrow freshEscrow = new DromosEscrow(address(gauge), address(reward));

        vm.prank(MARKET);
        vm.expectRevert(DromosEscrow.InvalidReceiver.selector);
        freshEscrow.initialize(IERC20(address(collateral)), address(freshEscrow));
    }

    function testOnDepositMarketStakesEntireBalanceIntoEmptyPosition() public {
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

    /// @dev Staking into an EMPTY position cannot cost anything, so the origin is irrelevant.
    function testOnDepositStakesIntoEmptyPositionRegardlessOfOrigin() public {
        collateral.mint(address(escrow), 10 ether);

        vm.prank(MARKET, OTHER);
        escrow.onDeposit();

        assertEq(gauge.balanceOf(address(escrow)), 10 ether, "staked");
        assertEq(collateral.balanceOf(address(escrow)), 0);
        assertEq(gauge.depositCalls(), 1);
    }

    /// @dev With a live position, staking would reset the penalty timer over the whole stake and
    ///      retroactively penalise banked emissions. Skip, and never revert.
    function testOnDepositSkipsStakingWhenPositionIsNotEmpty() public {
        _deposit(10 ether);
        collateral.mint(address(escrow), 5 ether);

        vm.prank(MARKET, BENEFICIARY);
        escrow.onDeposit();

        assertEq(gauge.balanceOf(address(escrow)), 10 ether, "stake untouched");
        assertEq(collateral.balanceOf(address(escrow)), 5 ether, "top-up left idle");
        assertEq(escrow.balance(), 15 ether, "still counted as collateral");
        assertEq(gauge.depositCalls(), 1, "no second gauge deposit");
    }

    /// @dev Even the beneficiary's own call is skipped: depositAndStake is the explicit opt-in.
    function testOnDepositSkipsForBeneficiaryWhenPositionIsNotEmpty() public {
        _deposit(10 ether);
        collateral.mint(address(escrow), 5 ether);

        vm.prank(BENEFICIARY, BENEFICIARY);
        escrow.onDeposit();

        assertEq(gauge.balanceOf(address(escrow)), 10 ether);
        assertEq(collateral.balanceOf(address(escrow)), 5 ether);
    }

    /// @dev Once pay() drains the position, auto-staking resumes.
    function testOnDepositResumesStakingAfterPositionIsFullyDrained() public {
        _deposit(10 ether);

        vm.prank(MARKET);
        escrow.pay(RECEIVER, 10 ether);
        assertEq(gauge.balanceOf(address(escrow)), 0, "drained");

        collateral.mint(address(escrow), 4 ether);
        vm.prank(MARKET, OTHER);
        escrow.onDeposit();

        assertEq(gauge.balanceOf(address(escrow)), 4 ether, "auto-staking resumed");
    }

    function testOnDepositRejectsUnauthorizedCaller() public {
        collateral.mint(address(escrow), 10 ether);

        vm.prank(OTHER, OTHER);
        vm.expectRevert(DromosEscrow.OnlyMarketOrBeneficiary.selector);
        escrow.onDeposit();
    }

    /// @dev The caller check still reverts. Staking no longer depends on tx.origin at all.
    function testOnDepositRejectsIntermediary() public {
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

    /// @dev Only the first tranche auto-stakes; later ones wait for depositAndStake.
    function testRepeatedDepositsOnlyAutoStakeIntoAnEmptyPosition() public {
        _deposit(4 ether);
        _deposit(6 ether);

        assertEq(gauge.balanceOf(address(escrow)), 4 ether, "first tranche staked");
        assertEq(collateral.balanceOf(address(escrow)), 6 ether, "second tranche idle");
        assertEq(escrow.balance(), 10 ether, "full collateral credited either way");

        vm.prank(BENEFICIARY);
        escrow.depositAndStake(0);

        assertEq(gauge.balanceOf(address(escrow)), 10 ether, "beneficiary opted in");
        assertEq(collateral.balanceOf(address(escrow)), 0);
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
        assertEq(gauge.claimCalls(), 1, "only the withdrawal's forced claim");
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

    /// @dev `pay` makes no claim of its own: the withdrawal force-claims to this escrow, and `pay`
    ///      forwards whatever arrived. One trip through the gauge's settlement chain, not two.
    function testPayForwardsEmissionsToBeneficiaryAfterWithdrawal() public {
        _deposit(10 ether);
        _setReward(2 ether);

        vm.prank(MARKET);
        escrow.pay(RECEIVER, 5 ether);

        assertEq(gauge.earned(address(escrow)), 0);
        assertEq(reward.balanceOf(address(escrow)), 0, "nothing left behind");
        assertEq(reward.balanceOf(BENEFICIARY), 2 ether, "forwarded to the beneficiary");
        assertEq(gauge.claimCalls(), 1, "a single settlement round-trip");
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
        assertEq(gauge.claimCalls(), 1);
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

    // ---------------------------------------------------------------
    // pay: the emissions claim must never block the collateral exit
    // ---------------------------------------------------------------

    /// @dev ACCEPTED RISK, pinned so the trade-off stays visible: the forward is a plain transfer, so a
    ///      beneficiary that cannot receive the emission token blocks its own withdrawal and liquidation.
    ///      Safe only because the Dromos emission token is protocol-controlled and has no blocklist.
    function testPayRevertsWhenBeneficiaryCannotReceiveEmissions() public {
        _deposit(10 ether);
        _setReward(2 ether);
        reward.setBlockedRecipient(BENEFICIARY);

        vm.prank(MARKET);
        vm.expectRevert(bytes("RECIPIENT_BLOCKED"));
        escrow.pay(RECEIVER, 6 ether);

        assertEq(escrow.balance(), 10 ether, "collateral present but undeliverable");
    }

    /// @dev Liquidation shape: two sequential pay() calls, both forwarding emissions.
    function testLiquidationShapedDoublePayForwardsEmissionsOnce() public {
        _deposit(10 ether);
        _setReward(2 ether);

        vm.startPrank(MARKET);
        escrow.pay(RECEIVER, 6 ether); // liquidator reward
        escrow.pay(OTHER, 2 ether); // liquidation fee
        vm.stopPrank();

        assertEq(collateral.balanceOf(RECEIVER), 6 ether);
        assertEq(collateral.balanceOf(OTHER), 2 ether);
        assertEq(escrow.balance(), 2 ether);
        assertEq(reward.balanceOf(BENEFICIARY), 2 ether, "forwarded by the first pay");
    }

    /// @dev The forward sends the escrow's whole rewardToken balance, so a later `pay` also carries out
    ///      anything donated or otherwise left sitting here.
    function testPayForwardAlsoCarriesOutPreExistingRewardBalance() public {
        _deposit(10 ether);
        reward.mint(address(escrow), 5 ether); // donated, or left by any earlier path
        _setReward(2 ether);

        vm.prank(MARKET);
        escrow.pay(RECEIVER, 3 ether);

        assertEq(reward.balanceOf(BENEFICIARY), 7 ether, "donation forwarded alongside emissions");
        assertEq(reward.balanceOf(address(escrow)), 0);
    }

    // ---------------------------------------------------------------
    // sweep
    // ---------------------------------------------------------------

    /// @dev `pay` only forwards when it unstakes, so a donation sitting in an escrow that never
    ///      withdraws is recovered by `sweep`.
    function testSweepRecoversDonatedRewardTokens() public {
        reward.mint(address(escrow), 4 ether);

        vm.prank(BENEFICIARY);
        escrow.sweep(IERC20(address(reward)), BENEFICIARY);

        assertEq(reward.balanceOf(BENEFICIARY), 4 ether);
        assertEq(reward.balanceOf(address(escrow)), 0);
    }

    function testSweepRefusesCollateral() public {
        _deposit(10 ether);
        collateral.mint(address(escrow), 5 ether);

        vm.prank(BENEFICIARY);
        vm.expectRevert(DromosEscrow.CannotSweepCollateral.selector);
        escrow.sweep(IERC20(address(collateral)), BENEFICIARY);

        assertEq(escrow.balance(), 15 ether, "collateral untouched");
    }

    function testSweepRejectsZeroAndSelfReceiver() public {
        reward.mint(address(escrow), 1 ether);

        vm.startPrank(BENEFICIARY);
        vm.expectRevert(DromosEscrow.InvalidReceiver.selector);
        escrow.sweep(IERC20(address(reward)), address(0));

        vm.expectRevert(DromosEscrow.InvalidReceiver.selector);
        escrow.sweep(IERC20(address(reward)), address(escrow));
        vm.stopPrank();
    }

    function testSweepCallableByAllowlistedClaimer() public {
        reward.mint(address(escrow), 3 ether);

        vm.prank(BENEFICIARY);
        escrow.setClaimer(CLAIMER, true);

        vm.prank(CLAIMER);
        escrow.sweep(IERC20(address(reward)), RECEIVER);

        assertEq(reward.balanceOf(RECEIVER), 3 ether);
    }

    function testSweepRejectsUnauthorizedCaller() public {
        reward.mint(address(escrow), 3 ether);

        vm.prank(OTHER);
        vm.expectRevert(DromosEscrow.OnlyBeneficiaryOrAllowlist.selector);
        escrow.sweep(IERC20(address(reward)), OTHER);
    }

    function testSweepRecoversTokensSentByMistake() public {
        MockDromosToken stray = new MockDromosToken("Stray", "STRAY");
        stray.mint(address(escrow), 8 ether);

        vm.prank(BENEFICIARY);
        escrow.sweep(IERC20(address(stray)), BENEFICIARY);

        assertEq(stray.balanceOf(BENEFICIARY), 8 ether);
    }

    // ---------------------------------------------------------------
    // gauge-approval invariant
    // ---------------------------------------------------------------

    /// @dev `Gauge.withdrawFrom` pays principal to msg.sender, so any gauge allowance granted by this
    ///      escrow would let the grantee drain its stake. The escrow must never grant one.
    function testEscrowNeverGrantsGaugeWithdrawalApproval() public {
        _deposit(10 ether);
        _setReward(2 ether);

        vm.prank(BENEFICIARY);
        escrow.claim();

        vm.prank(MARKET);
        escrow.pay(RECEIVER, 10 ether);

        collateral.mint(address(escrow), 4 ether);
        vm.prank(MARKET, BENEFICIARY);
        escrow.onDeposit();

        assertEq(gauge.approveCalls(), 0, "escrow must never call gauge.approve");
        assertEq(gauge.setApprovalForAllCalls(), 0, "escrow must never call gauge.setApprovalForAll");
    }

    // ---------------------------------------------------------------
    // depositAndStake
    // ---------------------------------------------------------------

    function testDepositAndStakePullsCollateralAndStakesIt() public {
        collateral.mint(BENEFICIARY, 10 ether);

        vm.startPrank(BENEFICIARY);
        collateral.approve(address(escrow), 10 ether);
        escrow.depositAndStake(10 ether);
        vm.stopPrank();

        assertEq(gauge.balanceOf(address(escrow)), 10 ether);
        assertEq(collateral.balanceOf(BENEFICIARY), 0);
        assertEq(escrow.balance(), 10 ether);
    }

    function testDepositAndStakeStakesPulledAndIdleCollateralTogether() public {
        _deposit(4 ether); // auto-staked into the empty position
        collateral.mint(address(escrow), 3 ether); // idle, skipped by onDeposit
        collateral.mint(BENEFICIARY, 2 ether);

        vm.startPrank(BENEFICIARY);
        collateral.approve(address(escrow), 2 ether);
        escrow.depositAndStake(2 ether);
        vm.stopPrank();

        assertEq(gauge.balanceOf(address(escrow)), 9 ether, "4 staked + 3 idle + 2 pulled");
        assertEq(collateral.balanceOf(address(escrow)), 0);
    }

    function testDepositAndStakeWithZeroAmountStakesOnlyIdleCollateral() public {
        _deposit(4 ether);
        collateral.mint(address(escrow), 6 ether);

        vm.prank(BENEFICIARY);
        escrow.depositAndStake(0);

        assertEq(gauge.balanceOf(address(escrow)), 10 ether);
        assertEq(collateral.balanceOf(address(escrow)), 0);
    }

    function testDepositAndStakeWithNothingToStakeIsNoOp() public {
        vm.prank(BENEFICIARY);
        escrow.depositAndStake(0);

        assertEq(gauge.balanceOf(address(escrow)), 0);
        assertEq(gauge.depositCalls(), 0);
    }

    function testDepositAndStakeEmitsStake() public {
        collateral.mint(address(escrow), 7 ether);

        vm.expectEmit(true, false, false, true, address(escrow));
        emit Stake(BENEFICIARY, 7 ether);

        vm.prank(BENEFICIARY);
        escrow.depositAndStake(0);
    }

    function testDepositAndStakeRejectsNonBeneficiary() public {
        collateral.mint(OTHER, 1 ether);

        vm.startPrank(OTHER);
        collateral.approve(address(escrow), 1 ether);
        vm.expectRevert(DromosEscrow.OnlyBeneficiary.selector);
        escrow.depositAndStake(1 ether);
        vm.stopPrank();
    }

    function testDepositAndStakeRejectsMarket() public {
        vm.prank(MARKET);
        vm.expectRevert(DromosEscrow.OnlyBeneficiary.selector);
        escrow.depositAndStake(0);
    }

    /// @dev The tx.origin gate used to make this impossible; msg.sender-based auth fixes it.
    function testContractBeneficiaryCanStake() public {
        DromosEscrow freshEscrow = new DromosEscrow(address(gauge), address(reward));
        MockContractBeneficiary wallet = new MockContractBeneficiary();

        vm.prank(MARKET);
        freshEscrow.initialize(IERC20(address(collateral)), address(wallet));

        collateral.mint(address(wallet), 10 ether);
        wallet.approve(IERC20(address(collateral)), address(freshEscrow), 10 ether);

        // tx.origin is an unrelated EOA, as it always is for a contract account.
        vm.prank(OTHER, OTHER);
        wallet.stake(freshEscrow, 10 ether);

        assertEq(gauge.balanceOf(address(freshEscrow)), 10 ether, "contract beneficiary staked");
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
