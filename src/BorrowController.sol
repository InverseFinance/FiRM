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
    
    /**
    @notice Sets the operator of the borrow controller. Only callable by the operator.
    @param _operator The address of the new operator.
    */
    function setOperator(address _operator) public onlyOperator { operator = _operator; }

    /**
    @notice Allows a contract to use the associated market.
    @param allowedContract The address of the allowed contract
    */
    function allow(address allowedContract) public onlyOperator { contractAllowlist[allowedContract] = true; }

    /**
    @notice Denies a contract to use the associated market
    @param deniedContract The addres of the denied contract
    */
    function deny(address deniedContract) public onlyOperator { contractAllowlist[deniedContract] = false; }

    /**
    @notice Checks if a borrow is allowed
    @dev Currently the borrowController only checks if contracts are part of an allow list
    @param msgSender The message sender trying to borrow
    @return A boolean that is true if borrowing is allowed and false if not.
    */
    function borrowAllowed(address msgSender, address, uint) public view returns (bool) {
        if(msgSender == tx.origin) return true;
        return contractAllowlist[msgSender];
    }
}
