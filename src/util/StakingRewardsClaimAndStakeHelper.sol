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

/// @notice Claims FiRM escrow rewards and stakes them as a Monolith StakedGovToken.
/// @dev Deploy per market with the corresponding StakedGovToken (sSWAN for sSwanUSD).
contract StakingRewardsClaimAndStakeHelper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error RewardTokenMismatch();
    error NoEscrow();
    error StakeFailed();

    Market public immutable market;
    IStakedGovToken public immutable stakedGovToken;
    IERC20 public immutable rewardToken;

    constructor(Market market_, IStakedGovToken stakedGovToken_) {
        IERC20 reward = StakingRewardsEscrow(market_.escrowImplementation()).rewardsToken();
        if (stakedGovToken_.underlying() != reward) revert RewardTokenMismatch();

        market = market_;
        stakedGovToken = stakedGovToken_;
        rewardToken = reward;
    }

    /// @notice Claims and stakes rewards from the caller's escrow, crediting the caller.
    /// @dev The caller must first authorize this helper with allowClaimOnBehalf on their escrow.
    /// @return amount The amount of reward tokens staked, or zero if none were claimed.
    function claimAndStake() external nonReentrant returns (uint256 amount) {
        StakingRewardsEscrow escrow = StakingRewardsEscrow(address(market.escrows(msg.sender)));
        if (address(escrow) == address(0)) revert NoEscrow();

        uint256 balanceBefore = rewardToken.balanceOf(address(this));
        escrow.claimTo(address(this));
        amount = rewardToken.balanceOf(address(this)) - balanceBefore;
        if (amount == 0) return 0;

        rewardToken.forceApprove(address(stakedGovToken), amount);
        if (!stakedGovToken.depositFor(msg.sender, amount)) revert StakeFailed();
    }
}
