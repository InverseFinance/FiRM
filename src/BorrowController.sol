// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract BorrowController {

    address public operator;
    mapping(address => bool) public contractAllowlist;

    constructor(address _operator) {
        operator = _operator;
    }

    modifier onlyOperator {
        require(msg.sender == operator, "Only operator");
        _;
    }

    function setOperator(address _operator) public onlyOperator { operator = _operator; }

    function allow(address allowedContract) public onlyOperator { contractAllowlist[allowedContract] = true; }

    function deny(address deniedContract) public onlyOperator { contractAllowlist[deniedContract] = false; }

    function borrowAllowed(address borrower, uint) public view returns (bool) {
        if(borrower == tx.origin) return true;
        return contractAllowlist[borrower];
    }
}