// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
@title Borrow Controller
@notice Contract for limiting the contracts that are allowed to interact with markets
*/
contract BorrowController {
    
    address public operator;
    mapping(address => bool) public contractAllowlist;
    mapping(address => uint) public dailyLimits;
    mapping(address => mapping(uint => uint)) public dailyBorrows;

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
    @notice Sets the daily borrow limit for a specific market
    @param market The addres of the market contract
    @param limit The daily borrow limit amount
    */
    function setDailyLimit(address market, uint limit) public onlyOperator { dailyLimits[market] = limit; }

    /**
    @notice Checks if a borrow is allowed
    @dev Currently the borrowController checks if contracts are part of an allow list and enforces a daily limit
    @param msgSender The message sender trying to borrow
    @param amount The amount to be borrowed
    @return A boolean that is true if borrowing is allowed and false if not.
    */
    function borrowAllowed(address msgSender, address, uint amount) public returns (bool) {
        uint day = block.timestamp / 1 days;
        uint dailyLimit = dailyLimits[msg.sender];
        if(dailyLimit > 0) {
            if(dailyBorrows[msg.sender][day] + amount > dailyLimit) {
                return false;
            } else {
                dailyBorrows[msg.sender][day] += amount;
            }
        }
        if(msgSender == tx.origin) return true;
        return contractAllowlist[msgSender];
    }
}
