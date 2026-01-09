// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title IConvexBooster
/// @notice Interface for the Convex Finance Booster contract
/// @dev Used to interact with Convex pools for depositing, withdrawing, and claiming rewards
interface IConvexBooster {
    /// @notice Withdraws LP tokens from a Convex pool
    /// @param pid The pool ID to withdraw from
    /// @param _amount The amount of LP tokens to withdraw
    function withdraw(uint256 pid, uint256 _amount) external;

    /// @notice Deposits LP tokens into a Convex pool
    /// @param pid The pool ID to deposit into
    /// @param amount The amount of LP tokens to deposit
    /// @param stake Whether to stake the deposit in the rewards contract
    function deposit(uint256 pid, uint256 amount, bool stake) external;

    /// @notice Claims pending CRV and CVX rewards for a pool and transfers them to the reward contract
    /// @param pid The pool ID to claim rewards for
    function earmarkRewards(uint256 pid) external;
}
