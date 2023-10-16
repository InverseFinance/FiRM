// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "src/interfaces/IERC20.sol";

interface IDola  is IERC20{
    function mint(address recipient, uint256 amount) external;
    function burn(uint256 amount) external;
    function addMinter(address minter) external;
    function totalSupply() external view returns (uint256);
}