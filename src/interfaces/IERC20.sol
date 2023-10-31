pragma solidity ^0.8.13;

interface IERC20 {
    function approve(address,uint) external;
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
    function allowance(address from, address to) external view returns (uint);
}

interface IMintable is IERC20 {
    function mint(address,uint) external;
    function burn(uint) external;
    function addMinter(address minter) external;
}

interface IDelegateableERC20 is IERC20 {
    function delegate(address delegatee) external;
    function delegates(address delegator) external view returns (address delegatee);
}

