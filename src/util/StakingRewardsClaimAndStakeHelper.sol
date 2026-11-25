// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20, SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Market} from "src/Market.sol";
import {StakingRewardsEscrow} from "src/escrows/StakingRewardsEscrow.sol";

interface IStakedGovToken {
    function underlying() external view returns (IERC20);
    function depositFor(address account, uint256 amount) external returns (bool);
}

interface ICoinDAOFactory {
    // The factory's public array getter returns these static fields in order.
    struct Deployment {
        IERC20 govToken;
        IStakedGovToken staker;
        address governor;
        address timelock;
        address lender;
        address coin;
        address vault;
        address stakingToken;
        address revenueRouter;
        address coinStakingRewards;
        address coinStakingRewardsFunder;
        address treasuryVesting;
        address monolithVesting;
        address deployerVesting;
    }

    function deployments(uint256 daoId) external view returns (Deployment memory);
}

interface IYearnVaultRegistry {
    function vaultInfo(address vault)
        external
        view
        returns (
            address asset,
            uint96 releaseVersion,
            uint64 vaultType,
            uint128 deploymentTimestamp,
            uint64 index,
            string memory tag
        );
}

/// @notice Claims FiRM escrow rewards and stakes them or deposits them into an endorsed Yearn vault.
/// @dev The caller must first authorize this helper with allowClaimOnBehalf on their escrow.
/// The deployer must supply a trusted Monolith DAO factory and Yearn V3 registry.
contract StakingRewardsClaimAndStakeHelper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidDAOFactory();
    error InvalidYearnRegistry();
    error InvalidCompoundVault();
    error InsufficientShares(uint256 received, uint256 minimum);
    error RewardTokenMismatch();
    error NoEscrow();
    error InvalidEscrow();
    error InvalidRecipient();
    error StakeFailed();

    ICoinDAOFactory public immutable factory;
    IYearnVaultRegistry public immutable yearnRegistry;

    uint64 private constant YEARN_ALLOCATOR_VAULT_TYPE = 1;

    /// @param factory_ The trusted Monolith DAO factory for this helper.
    /// @param yearnRegistry_ The trusted Yearn V3 registry for this chain.
    constructor(ICoinDAOFactory factory_, IYearnVaultRegistry yearnRegistry_) {
        if (address(factory_).code.length == 0) revert InvalidDAOFactory();
        if (address(yearnRegistry_).code.length == 0) revert InvalidYearnRegistry();
        factory = factory_;
        yearnRegistry = yearnRegistry_;
    }

    /// @notice Claims and stakes rewards from the caller's escrow, crediting the caller.
    /// @param market The FiRM market whose rewards are being claimed.
    /// @param daoId The DAO's deployment ID within the configured factory.
    /// @return amount The amount of reward tokens staked, or zero if none were claimed.
    function claimAndStake(Market market, uint256 daoId) external nonReentrant returns (uint256 amount) {
        return _claimAndStake(market, daoId, msg.sender);
    }

    /// @notice Claims rewards from the caller's escrow and stakes them for the recipient.
    /// @dev The recipient owns the staked position and must be able to withdraw it.
    /// @param market The FiRM market whose rewards are being claimed.
    /// @param daoId The DAO's deployment ID within the configured factory.
    /// @param recipient The address that receives the staked GOV tokens.
    /// @return amount The amount of reward tokens staked, or zero if none were claimed.
    function claimAndStakeTo(Market market, uint256 daoId, address recipient)
        external
        nonReentrant
        returns (uint256 amount)
    {
        _validateRecipient(recipient);
        return _claimAndStake(market, daoId, recipient);
    }

    /// @notice Claims the caller's rewards and deposits them into the selected Yearn vault for the caller.
    /// @return shares The shares minted, or zero if there were no rewards.
    function claimAndCompound(Market market, IERC4626 vault, uint256 minShares)
        external
        nonReentrant
        returns (uint256 shares)
    {
        return _claimAndCompound(market, vault, minShares, msg.sender);
    }

    /// @notice Claims the caller's rewards and mints Yearn vault shares to the specified recipient.
    /// @return shares The shares minted, or zero if there were no rewards.
    function claimAndCompoundTo(Market market, IERC4626 vault, uint256 minShares, address recipient)
        external
        nonReentrant
        returns (uint256 shares)
    {
        _validateRecipient(recipient);
        return _claimAndCompound(market, vault, minShares, recipient);
    }

    function _claimAndStake(Market market, uint256 daoId, address recipient) private returns (uint256 amount) {
        StakingRewardsEscrow escrow = _getEscrow(market);
        IERC20 rewardToken = escrow.rewardsToken();
        ICoinDAOFactory.Deployment memory deployment = factory.deployments(daoId);
        IStakedGovToken stakedGovToken = deployment.staker;
        if (deployment.govToken != rewardToken || stakedGovToken.underlying() != rewardToken) {
            revert RewardTokenMismatch();
        }

        amount = _claimRewards(escrow, rewardToken);
        if (amount == 0) return 0;

        rewardToken.forceApprove(address(stakedGovToken), amount);
        if (!stakedGovToken.depositFor(recipient, amount)) revert StakeFailed();
    }

    function _claimAndCompound(Market market, IERC4626 vault, uint256 minShares, address recipient)
        private
        returns (uint256 shares)
    {
        StakingRewardsEscrow escrow = _getEscrow(market);
        IERC20 rewardToken = escrow.rewardsToken();
        (address registeredAsset,, uint64 vaultType,,,) = yearnRegistry.vaultInfo(address(vault));
        if (
            registeredAsset != address(rewardToken) || vaultType != YEARN_ALLOCATOR_VAULT_TYPE
                || vault.asset() != address(rewardToken)
        ) revert InvalidCompoundVault();

        uint256 amount = _claimRewards(escrow, rewardToken);
        if (amount == 0) return 0;

        rewardToken.forceApprove(address(vault), amount);
        shares = vault.deposit(amount, recipient);
        if (shares == 0 || shares < minShares) revert InsufficientShares(shares, minShares);
    }

    function _getEscrow(Market market) private view returns (StakingRewardsEscrow escrow) {
        escrow = StakingRewardsEscrow(address(market.escrows(msg.sender)));
        if (address(escrow) == address(0)) revert NoEscrow();
        if (escrow.market() != address(market) || escrow.beneficiary() != msg.sender) revert InvalidEscrow();
    }

    function _claimRewards(StakingRewardsEscrow escrow, IERC20 rewardToken) private returns (uint256 amount) {
        uint256 balanceBefore = rewardToken.balanceOf(address(this));
        escrow.claimTo(address(this));
        amount = rewardToken.balanceOf(address(this)) - balanceBefore;
    }

    function _validateRecipient(address recipient) private view {
        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();
    }
}
