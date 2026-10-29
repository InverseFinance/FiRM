// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20, SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IStakingRewards} from "src/interfaces/IStakingRewards.sol";

/// @notice Stakes a borrower's FiRM collateral and lets them claim rewards separately.
/// @dev Deploy an implementation per initialized staking pool, then initialize each
/// clone atomically from its market. Tokens must transfer exact amounts and must
/// not rebase. The pool's staking and reward token configuration must remain fixed.
contract StakingRewardsEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidStakingRewards();
    error InvalidToken();
    error IdenticalTokens();
    error InvalidBeneficiary();
    error InvalidRecipient();
    error AlreadyInitialized();
    error OnlyMarket();
    error OnlyBeneficiary();
    error OnlyBeneficiaryOrAllowlist();

    IStakingRewards public immutable stakingRewards;
    IERC20 public immutable token;
    IERC20 public immutable rewardsToken;

    address public market;
    address public beneficiary;
    mapping(address => bool) public allowlist;

    event AllowClaim(address indexed allowedAddress, bool allowed);

    modifier onlyBeneficiary() {
        if (msg.sender != beneficiary) revert OnlyBeneficiary();
        _;
    }

    modifier onlyBeneficiaryOrAllowlist() {
        if (msg.sender != beneficiary && !allowlist[msg.sender]) revert OnlyBeneficiaryOrAllowlist();
        _;
    }

    constructor(address _stakingRewards) {
        if (_stakingRewards.code.length == 0) revert InvalidStakingRewards();
        IStakingRewards pool = IStakingRewards(_stakingRewards);
        IERC20 collateral = pool.stakingToken();
        IERC20 reward = pool.rewardsToken();
        if (address(collateral).code.length == 0 || address(reward).code.length == 0) revert InvalidToken();
        if (collateral == reward) revert IdenticalTokens();

        stakingRewards = pool;
        token = collateral;
        rewardsToken = reward;
    }

    /// @notice Binds a new clone to its market and beneficiary and approves collateral staking.
    /// @dev Must be called by the market immediately after clone creation.
    function initialize(IERC20 _token, address _beneficiary) external nonReentrant {
        if (market != address(0)) revert AlreadyInitialized();
        if (_token != token) revert InvalidToken();
        if (_beneficiary == address(0)) revert InvalidBeneficiary();
        market = msg.sender;
        beneficiary = _beneficiary;
        token.forceApprove(address(stakingRewards), type(uint256).max);
    }

    /// @notice Stakes all idle collateral, including direct transfers into the escrow.
    /// @dev Permissionless so anyone can process deposits made outside the market.
    function onDeposit() external nonReentrant {
        uint256 amount = token.balanceOf(address(this));
        if (amount != 0) stakingRewards.stake(amount);
    }

    /// @notice Returns idle plus staked collateral, excluding pending and held rewards.
    function balance() external view returns (uint256) {
        return token.balanceOf(address(this)) + stakingRewards.balanceOf(address(this));
    }

    /// @notice Pays market-authorized withdrawals or liquidations from collateral.
    /// @dev Uses idle tokens first and withdraws only the shortfall, without claiming rewards.
    function pay(address recipient, uint256 amount) external nonReentrant {
        if (msg.sender != market) revert OnlyMarket();
        if (amount == 0) return;
        uint256 idleBalance = token.balanceOf(address(this));
        if (idleBalance < amount) stakingRewards.withdraw(amount - idleBalance);
        token.safeTransfer(recipient, amount);
    }

    /// @notice Claims rewards to the beneficiary.
    function claim() external onlyBeneficiary {
        claimTo(msg.sender);
    }

    /// @notice Claims and forwards all held reward tokens to a nonzero recipient.
    /// @dev Allowlisted callers may send rewards to any recipient, but cannot withdraw collateral.
    function claimTo(address to) public onlyBeneficiaryOrAllowlist nonReentrant {
        if (to == address(0)) revert InvalidRecipient();
        stakingRewards.getReward();
        uint256 amount = rewardsToken.balanceOf(address(this));
        if (amount != 0) rewardsToken.safeTransfer(to, amount);
    }

    /// @notice Returns pending staking rewards plus reward tokens already held here.
    function claimable() external view returns (uint256) {
        return stakingRewards.earned(address(this)) + rewardsToken.balanceOf(address(this));
    }

    /// @notice Authorizes an address to claim rewards to any recipient.
    function allowClaimOnBehalf(address allowee) external onlyBeneficiary {
        allowlist[allowee] = true;
        emit AllowClaim(allowee, true);
    }

    /// @notice Revokes an address's permission to claim rewards.
    function disallowClaimOnBehalf(address allowee) external onlyBeneficiary {
        allowlist[allowee] = false;
        emit AllowClaim(allowee, false);
    }
}
