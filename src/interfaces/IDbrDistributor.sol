pragma solidity ^0.8.13;

interface IDbrDistributor {
    function stake(uint amount) external;
    function unstake(uint amount) external;
    function claim(address to) external;
    function claimable(address user) external view returns(uint);
}

