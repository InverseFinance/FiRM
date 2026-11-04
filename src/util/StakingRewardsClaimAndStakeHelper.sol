// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20, SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
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

/// @notice Claims FiRM escrow rewards and stakes them as a Monolith StakedGovToken.
/// @dev The caller must first authorize this helper with allowClaimOnBehalf on their escrow.
/// Frontends must supply a known Monolith DAO factory. A malicious factory can return a
/// staking contract that keeps the caller's claimed rewards even if the token checks pass.
contract StakingRewardsClaimAndStakeHelper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidDAOFactory();
    error RewardTokenMismatch();
    error NoEscrow();
    error InvalidEscrow();
    error InvalidRecipient();
    error StakeFailed();

    /// @notice Claims and stakes rewards from the caller's escrow, crediting the caller.
    /// @param market The FiRM market whose rewards are being claimed.
    /// @param factory The caller-selected Monolith DAO factory that deployed the DAO.
    /// @param daoId The DAO's deployment ID within that factory.
    /// @return amount The amount of reward tokens staked, or zero if none were claimed.
    function claimAndStake(Market market, ICoinDAOFactory factory, uint256 daoId)
        external
        nonReentrant
        returns (uint256 amount)
    {
        return _claimAndStake(market, factory, daoId, msg.sender);
    }

    /// @notice Claims rewards from the caller's escrow and stakes them for the recipient.
    /// @dev The recipient owns the staked position and must be able to withdraw it.
    /// @param market The FiRM market whose rewards are being claimed.
    /// @param factory The caller-selected Monolith DAO factory that deployed the DAO.
    /// @param daoId The DAO's deployment ID within that factory.
    /// @param recipient The address that receives the staked GOV tokens.
    /// @return amount The amount of reward tokens staked, or zero if none were claimed.
    function claimAndStakeTo(Market market, ICoinDAOFactory factory, uint256 daoId, address recipient)
        external
        nonReentrant
        returns (uint256 amount)
    {
        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();
        return _claimAndStake(market, factory, daoId, recipient);
    }

    function _claimAndStake(Market market, ICoinDAOFactory factory, uint256 daoId, address recipient)
        private
        returns (uint256 amount)
    {
        StakingRewardsEscrow escrow = StakingRewardsEscrow(address(market.escrows(msg.sender)));
        if (address(escrow) == address(0)) revert NoEscrow();
        if (escrow.market() != address(market) || escrow.beneficiary() != msg.sender) revert InvalidEscrow();

        if (address(factory).code.length == 0) revert InvalidDAOFactory();
        IERC20 rewardToken = escrow.rewardsToken();
        ICoinDAOFactory.Deployment memory deployment = factory.deployments(daoId);
        IStakedGovToken stakedGovToken = deployment.staker;
        if (deployment.govToken != rewardToken || stakedGovToken.underlying() != rewardToken) {
            revert RewardTokenMismatch();
        }

        uint256 balanceBefore = rewardToken.balanceOf(address(this));
        escrow.claimTo(address(this));
        amount = rewardToken.balanceOf(address(this)) - balanceBefore;
        if (amount == 0) return 0;

        rewardToken.forceApprove(address(stakedGovToken), amount);
        if (!stakedGovToken.depositFor(recipient, amount)) revert StakeFailed();
        rewardToken.forceApprove(address(stakedGovToken), 0);
    }
}
