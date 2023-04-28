// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

interface IOracle {
    function feeds(address token) external view returns(IChainlinkFeed, uint8);
}

interface IMarket {
    function collateral() external view returns(address);
    function oracle() external view returns(IOracle);
}

/**
@title Borrow Controller
@notice Contract for limiting the contracts that are allowed to interact with markets
*/
contract BorrowController {
    
    uint stalenessThreshold;
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
    @notice Sets the staleness threshold for Chainlink feeds
    @param newStalenessThreshold The new staleness threshold denominated in seconds
    @dev Only callable by operator
    */
    function setStalenessThreshold(uint newStalenessThreshold) public onlyOperator { stalenessThreshold = newStalenessThreshold; }

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
                //Safe to use unchecked, as function will revert in if statement if overflow
                unchecked{
                    dailyBorrows[msg.sender][day] += amount;
                }
            }
        }
        if(isPriceStale(msg.sender)) return false;
        if(msgSender == tx.origin) return true;
        return contractAllowlist[msgSender];
    }

    /**
    @notice Reduces the daily limit used, when a user repays debt
    @dev This is necessary to prevent a DOS attack, where a user borrows the daily limit and immediately repays it again.
    @param amount Amount repaid in the market
    */
    function onRepay(uint amount) public {
        uint day = block.timestamp / 1 days;
        if(dailyBorrows[msg.sender][day] < amount) {
            dailyBorrows[msg.sender][day] = 0;
        } else {
            //Safe to use unchecked, as dailyBorow is checked to be higher than amount
            unchecked{
                dailyBorrows[msg.sender][day] -= amount;
            }
        }
    }

    /**
     * @notice Checks if the price for the given market is stale.
     * @dev This function makes use of the Chainlink Oracle system to determine the price staleness.
     * @param market The address of the market for which the price staleness is to be checked.
     * @return bool Returns true if the price is stale, false otherwise.
     */
    function isPriceStale(address market) public view returns(bool){
        IOracle oracle = IMarket(market).oracle();
        (IChainlinkFeed feed,) = oracle.feeds(IMarket(market).collateral());
        (,,,uint updatedAt,) = feed.latestRoundData();
        return block.timestamp - updatedAt > stalenessThreshold;
    }
}
