pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IVirtualBalanceRewardPool {
    function virtualBalance() external view returns (uint256);

    function queueNewRewards(uint256 _rewards) external;

    function operator() external view returns (address);

    function rewardToken() external view returns (IERC20);
}
