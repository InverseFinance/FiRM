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
contract StakingRewardsClaimAndStakeHelper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidDAOFactory();
    error MarketAlreadyRegistered();
    error MarketNotRegistered();
    error RewardTokenMismatch();
    error NoEscrow();
    error InvalidEscrow();
    error StakeFailed();

    struct MarketConfig {
        IERC20 rewardToken;
        IStakedGovToken stakedGovToken;
    }

    ICoinDAOFactory public immutable daoFactory;
    mapping(Market => MarketConfig) public markets;

    event MarketRegistered(address indexed market, address indexed rewardToken, address indexed stakedGovToken);

    constructor(ICoinDAOFactory daoFactory_) {
        if (address(daoFactory_).code.length == 0) revert InvalidDAOFactory();
        daoFactory = daoFactory_;
    }

    /// @notice Registers a FiRM market using its Monolith CoinDAO factory deployment ID.
    /// @dev Anyone can register a market. The factory record determines its permanent staking token.
    function registerMarket(Market market, uint256 daoId) external {
        if (address(markets[market].stakedGovToken) != address(0)) revert MarketAlreadyRegistered();

        IERC20 rewardToken = StakingRewardsEscrow(market.escrowImplementation()).rewardsToken();
        ICoinDAOFactory.Deployment memory deployment = daoFactory.deployments(daoId);
        IStakedGovToken stakedGovToken = deployment.staker;
        if (deployment.govToken != rewardToken || stakedGovToken.underlying() != rewardToken) {
            revert RewardTokenMismatch();
        }

        markets[market] = MarketConfig(rewardToken, stakedGovToken);
        emit MarketRegistered(address(market), address(rewardToken), address(stakedGovToken));
    }

    /// @notice Claims and stakes rewards from the caller's escrow, crediting the caller.
    /// @dev The caller must first authorize this helper with allowClaimOnBehalf on their escrow.
    /// @return amount The amount of reward tokens staked, or zero if none were claimed.
    function claimAndStake(Market market) external nonReentrant returns (uint256 amount) {
        MarketConfig memory config = markets[market];
        if (address(config.stakedGovToken) == address(0)) revert MarketNotRegistered();

        StakingRewardsEscrow escrow = StakingRewardsEscrow(address(market.escrows(msg.sender)));
        if (address(escrow) == address(0)) revert NoEscrow();
        if (escrow.market() != address(market) || escrow.beneficiary() != msg.sender) revert InvalidEscrow();

        IERC20 rewardToken = config.rewardToken;
        uint256 balanceBefore = rewardToken.balanceOf(address(this));
        escrow.claimTo(address(this));
        amount = rewardToken.balanceOf(address(this)) - balanceBefore;
        if (amount == 0) return 0;

        rewardToken.forceApprove(address(config.stakedGovToken), amount);
        if (!config.stakedGovToken.depositFor(msg.sender, amount)) revert StakeFailed();
        rewardToken.forceApprove(address(config.stakedGovToken), 0);
    }
}
