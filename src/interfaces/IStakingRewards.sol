// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice The Synthetix-style staking interface used by StakingRewardsEscrow.
interface IStakingRewards {
    function stakingToken() external view returns (IERC20);
    function rewardsToken() external view returns (IERC20);
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
}
