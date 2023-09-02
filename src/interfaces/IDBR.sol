// SPDX-License-Identifier: UNLICENSED 
pragma solidity ^0.8.13;

interface IDBR {
    function markets(address) external view returns (bool);
    function mint(address, uint) external;
}
