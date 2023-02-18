pragma solidity ^0.8.13;

interface IERC20 {
    function approve(address,uint) external;
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
}

