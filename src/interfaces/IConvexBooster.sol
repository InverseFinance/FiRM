pragma solidity ^0.8.13;

interface IConvexBooster {
    function withdraw(uint256 pid, uint256 _amount) external;

    function deposit(uint256 pid, uint256 amount, bool stake) external;
}
