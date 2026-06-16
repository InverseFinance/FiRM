// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Market, IOracle, IDolaBorrowingRights} from "src/Market.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {StakeDaoEscrow, IRewardVault} from "src/escrows/StakeDaoEscrow.sol";

interface IStakeDaoRewardVault is IRewardVault {
    function depositRewards(address rewardsToken, uint128 amount) external;

    function getRewardsDistributor(address token) external view returns (address);

    function getRewardTokens() external view returns (address[] memory);
}

contract StakeDaoEscrowForkTest is Test {
    uint256 internal constant FORK_BLOCK = 25_076_112;

    address internal constant GOV = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address internal constant LENDER = address(0xA11CE);
    address internal constant PAUSE_GUARDIAN = address(0xB0B);
    address internal constant TREASURY = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address internal constant USER = address(0xBEEF);
    address internal constant FRIEND = address(0xCAFE);
    address internal constant RECEIVER = address(0xD00D);

    address internal constant DBR = 0xAD038Eb671c44b853887A7E32528FaB35dC5D710;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address internal constant REWARD_VAULT = 0xCA137e3853Eab95541290B372223e7F2ee4c0cFa;
    address internal constant CRV_FRX_USD_LP = 0x13e12BB0E6A2f1A3d6901a59a9d585e89A6243e1;
    address internal constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    uint256 internal constant DEPOSIT_AMOUNT = 10_000 ether;
    uint256 internal constant REWARD_AMOUNT = 10_000 ether;

    IERC20 internal lpToken;
    IERC20 internal cvx;
    IERC20 internal crv;
    IStakeDaoRewardVault internal rewardVault;
    StakeDaoEscrow internal escrowImplementation;
    Market internal market;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, FORK_BLOCK);

        lpToken = IERC20(CRV_FRX_USD_LP);
        cvx = IERC20(CVX);
        crv = IERC20(CRV);
        rewardVault = IStakeDaoRewardVault(REWARD_VAULT);
        escrowImplementation = new StakeDaoEscrow(REWARD_VAULT, TREASURY);
        market = _deployMarket(CRV_FRX_USD_LP, true);

        vm.label(USER, "user");
        vm.label(FRIEND, "friend");
        vm.label(RECEIVER, "receiver");
        vm.label(CRV_FRX_USD_LP, "crvUSD/frxUSD LP");
        vm.label(REWARD_VAULT, "sd-crvfrxUSD-vault");
        vm.label(CVX, "CVX");
        vm.label(CRV, "CRV");
    }

    function testMarketDepositCreatesAndStakesLpEscrow() public {
        StakeDaoEscrow escrow = _deposit(DEPOSIT_AMOUNT);

        assertEq(address(escrow.market()), address(market), "market");
        assertEq(escrow.beneficiary(), USER, "beneficiary");
        assertEq(address(escrow.token()), CRV_FRX_USD_LP, "token");
        assertEq(address(escrow.rewardVault()), REWARD_VAULT, "vault");
        assertEq(address(escrow.accountant()), rewardVault.ACCOUNTANT(), "accountant");
        assertEq(escrow.gauge(), rewardVault.gauge(), "gauge");
        assertEq(escrow.baseRewardToken(), CRV, "base reward token");
        assertEq(rewardVault.asset(), CRV_FRX_USD_LP, "vault asset");

        assertEq(lpToken.balanceOf(address(escrow)), 0, "unstaked LP");
        assertEq(rewardVault.balanceOf(address(escrow)), DEPOSIT_AMOUNT, "vault shares");
        assertEq(escrow.balance(), DEPOSIT_AMOUNT, "escrow balance");
        assertEq(market.getWithdrawalLimit(USER), DEPOSIT_AMOUNT, "withdrawal limit");
    }

    function testMarketWithdrawUnstakesAndPaysLp() public {
        StakeDaoEscrow escrow = _deposit(DEPOSIT_AMOUNT);

        uint256 half = DEPOSIT_AMOUNT / 2;
        uint256 userBalanceBefore = lpToken.balanceOf(USER);
        uint256 vaultBalanceBefore = rewardVault.balanceOf(address(escrow));

        vm.prank(USER, USER);
        market.withdraw(half);

        assertEq(lpToken.balanceOf(USER), userBalanceBefore + half, "half paid");
        assertEq(rewardVault.balanceOf(address(escrow)), vaultBalanceBefore - half, "half unstaked");
        assertEq(escrow.balance(), DEPOSIT_AMOUNT - half, "half remaining");

        vm.prank(USER, USER);
        market.withdrawMax();

        assertEq(lpToken.balanceOf(USER), userBalanceBefore + DEPOSIT_AMOUNT, "all paid");
        assertEq(rewardVault.balanceOf(address(escrow)), 0, "shares cleared");
        assertEq(lpToken.balanceOf(address(escrow)), 0, "LP cleared");
        assertEq(escrow.balance(), 0, "escrow cleared");
    }

    function testPauseGuardianPullsFundsFromStakeDaoAndRestores() public {
        StakeDaoEscrow escrow = _deposit(DEPOSIT_AMOUNT);
        uint256 additionalDeposit = 1 ether;

        assertTrue(escrow.stakeDaoDepositsEnabled(), "staking disabled");
        assertEq(lpToken.allowance(address(escrow), address(rewardVault)), type(uint256).max, "initial allowance");

        vm.prank(PAUSE_GUARDIAN);
        escrow.setStakeDaoDepositsEnabled(false);

        assertFalse(escrow.stakeDaoDepositsEnabled(), "staking enabled");
        assertEq(rewardVault.balanceOf(address(escrow)), 0, "shares not redeemed");
        assertEq(lpToken.balanceOf(address(escrow)), DEPOSIT_AMOUNT, "LP not pulled");
        assertEq(lpToken.allowance(address(escrow), address(rewardVault)), 0, "allowance not revoked");
        assertEq(escrow.balance(), DEPOSIT_AMOUNT, "pulled balance");

        _depositMore(additionalDeposit);

        assertEq(rewardVault.balanceOf(address(escrow)), 0, "deposit staked while disabled");
        assertEq(lpToken.balanceOf(address(escrow)), DEPOSIT_AMOUNT + additionalDeposit, "deposit not held liquid");
        assertEq(escrow.balance(), DEPOSIT_AMOUNT + additionalDeposit, "disabled balance with deposit");

        uint256 userBalanceBefore = lpToken.balanceOf(USER);
        vm.prank(USER, USER);
        market.withdraw(additionalDeposit);

        assertEq(lpToken.balanceOf(USER), userBalanceBefore + additionalDeposit, "withdraw while disabled");
        assertEq(escrow.balance(), DEPOSIT_AMOUNT, "remaining disabled balance");

        vm.prank(PAUSE_GUARDIAN);
        escrow.setStakeDaoDepositsEnabled(true);

        assertTrue(escrow.stakeDaoDepositsEnabled(), "staking not enabled");
        assertEq(lpToken.allowance(address(escrow), address(rewardVault)), type(uint256).max, "allowance not restored");
        assertEq(lpToken.balanceOf(address(escrow)), 0, "liquid LP not staked");
        assertEq(rewardVault.balanceOf(address(escrow)), DEPOSIT_AMOUNT, "shares not restored");
        assertEq(escrow.balance(), DEPOSIT_AMOUNT, "restored balance");
    }

    function testStakeDaoDepositToggleUsesCurrentMarketPauseGuardian() public {
        StakeDaoEscrow escrow = _deposit(DEPOSIT_AMOUNT);
        address newGuardian = address(0x123);

        vm.prank(FRIEND);
        vm.expectRevert(StakeDaoEscrow.OnlyGuardian.selector);
        escrow.setStakeDaoDepositsEnabled(false);

        vm.prank(GOV);
        market.setPauseGuardian(newGuardian);

        vm.prank(PAUSE_GUARDIAN);
        vm.expectRevert(StakeDaoEscrow.OnlyGuardian.selector);
        escrow.setStakeDaoDepositsEnabled(false);

        vm.prank(newGuardian);
        escrow.setStakeDaoDepositsEnabled(false);

        assertFalse(escrow.stakeDaoDepositsEnabled(), "new guardian did not pull");
    }

    function testClaimCvxRewardsThroughStakeDaoEscrow() public {
        StakeDaoEscrow escrow = _deposit(DEPOSIT_AMOUNT);
        address distributor = rewardVault.getRewardsDistributor(CVX);
        assertTrue(distributor != address(0), "missing distributor");

        deal(CVX, distributor, REWARD_AMOUNT, false);
        vm.startPrank(distributor, distributor);
        cvx.approve(address(rewardVault), REWARD_AMOUNT);
        rewardVault.depositRewards(CVX, uint128(REWARD_AMOUNT));
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        address[] memory rewardTokens = _cvxRewardTokens();
        uint256 beneficiaryBalanceBefore = cvx.balanceOf(USER);

        vm.prank(USER);
        escrow.claim(rewardTokens);

        assertGt(cvx.balanceOf(USER), beneficiaryBalanceBefore, "CVX not claimed");
        assertEq(cvx.balanceOf(address(escrow)), 0, "escrow CVX dust");
    }

    function testAllowlistedClaimerReceivesCrvBaseRewardToken() public {
        StakeDaoEscrow escrow = _deposit(DEPOSIT_AMOUNT);
        address[] memory rewardTokens = new address[](0);

        vm.prank(USER);
        escrow.setClaimer(FRIEND, true);

        vm.warp(block.timestamp + 7 days);
        _depositMore(1 ether);

        uint256 receiverBalanceBefore = crv.balanceOf(RECEIVER);

        vm.prank(FRIEND);
        escrow.claim(rewardTokens, RECEIVER);

        assertGt(crv.balanceOf(RECEIVER), receiverBalanceBefore, "CRV not claimed");
        assertEq(crv.balanceOf(address(escrow)), 0, "escrow CRV dust");
    }

    function testClaimAccessControl() public {
        StakeDaoEscrow escrow = _deposit(DEPOSIT_AMOUNT);
        address[] memory rewardTokens = _cvxRewardTokens();

        vm.prank(FRIEND);
        vm.expectRevert(StakeDaoEscrow.OnlyBeneficiaryOrAllowlist.selector);
        escrow.claim(rewardTokens, RECEIVER);

        vm.prank(FRIEND);
        vm.expectRevert(StakeDaoEscrow.OnlyBeneficiary.selector);
        escrow.claim(rewardTokens);

        vm.prank(FRIEND);
        vm.expectRevert(StakeDaoEscrow.OnlyBeneficiary.selector);
        escrow.setClaimer(FRIEND, true);

        vm.prank(USER);
        escrow.setClaimer(FRIEND, true);
        assertTrue(escrow.allowlist(FRIEND), "friend not allowlisted");

        vm.prank(FRIEND);
        escrow.claim(rewardTokens, RECEIVER);

        vm.prank(USER);
        vm.expectRevert(StakeDaoEscrow.InvalidReceiver.selector);
        escrow.claim(rewardTokens, address(0));

        vm.prank(USER);
        vm.expectRevert(StakeDaoEscrow.InvalidReceiver.selector);
        escrow.claim(rewardTokens, address(escrow));
    }

    function testMarketDepositRevertsForWrongCollateral() public {
        StakeDaoEscrow wrongCollateralImplementation = new StakeDaoEscrow(REWARD_VAULT, TREASURY);
        Market wrongCollateralMarket = new Market(
            GOV,
            LENDER,
            PAUSE_GUARDIAN,
            address(wrongCollateralImplementation),
            IDolaBorrowingRights(DBR),
            IERC20(WETH),
            IOracle(address(0)),
            5000,
            5000,
            1000,
            true
        );

        vm.prank(USER, USER);
        vm.expectRevert(StakeDaoEscrow.WrongCollateral.selector);
        wrongCollateralMarket.deposit(1);
    }

    function _deployMarket(address collateral, bool callOnDepositCallback) internal returns (Market deployedMarket) {
        deployedMarket = new Market(
            GOV,
            LENDER,
            PAUSE_GUARDIAN,
            address(escrowImplementation),
            IDolaBorrowingRights(DBR),
            IERC20(collateral),
            IOracle(address(0)),
            5000,
            5000,
            1000,
            callOnDepositCallback
        );
    }

    function _deposit(uint256 amount) internal returns (StakeDaoEscrow escrow) {
        deal(CRV_FRX_USD_LP, USER, amount, false);
        escrow = StakeDaoEscrow(address(market.predictEscrow(USER)));

        vm.startPrank(USER, USER);
        lpToken.approve(address(market), amount);
        market.deposit(amount);
        vm.stopPrank();
    }

    function _depositMore(uint256 amount) internal {
        deal(CRV_FRX_USD_LP, USER, amount, false);

        vm.startPrank(USER, USER);
        lpToken.approve(address(market), amount);
        market.deposit(amount);
        vm.stopPrank();
    }

    function _cvxRewardTokens() internal pure returns (address[] memory tokens) {
        tokens = new address[](1);
        tokens[0] = CVX;
    }
}
