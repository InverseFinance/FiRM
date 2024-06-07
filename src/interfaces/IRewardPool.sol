pragma solidity ^0.8.13;

interface IRewardPool {
    function withdraw(uint256 amount, bool claim) external returns (bool);

    function withdrawAndUnwrap(
        uint256 amount,
        bool claim
    ) external returns (bool);

    function getReward(
        address account,
        bool claimExtras
    ) external returns (bool);

    function getReward() external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function extraRewardsLength() external view returns (uint);

    function rewardToken() external view returns (address);

    function rewards(
        uint256 index
    ) external view returns (address, uint256, uint256, uint256);
}
