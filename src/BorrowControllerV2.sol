// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "src/DBR.sol";

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
    function debts(address) external view returns(uint);
}

/**
 * @title Borrow Controller
 * @notice Contract for limiting the contracts that are allowed to interact with markets
 */
contract BorrowControllerV2 {
    
    address public operator;
    DolaBorrowingRights public immutable DBR;
    mapping(address => uint) public minDebts;
    mapping(address => bool) public contractAllowlist;
    mapping(address => uint) public dailyBorrowLimit;
    mapping(address => uint) public stalenessThreshold;
    mapping(address => uint) public remainingDailyBorrowLimit;
    mapping(address => uint) public lastDailyBorrowLimitUpdate;

    constructor(address _operator, address _DBR) {
        operator = _operator;
        DBR = DolaBorrowingRights(_DBR);
    }

    modifier onlyOperator {
        require(msg.sender == operator, "Only operator");
        _;
    }
    
    /**
     * @notice Sets the operator of the borrow controller. Only callable by the operator.
     * @param _operator The address of the new operator.
     */
    function setOperator(address _operator) public onlyOperator { operator = _operator; }

    /**
     * @notice Allows a contract to use the associated market.
     * @param allowedContract The address of the allowed contract
     */
    function allow(address allowedContract) public onlyOperator { contractAllowlist[allowedContract] = true; }

    /**
     * @notice Denies a contract to use the associated market
     * @param deniedContract The address of the denied contract
     */
    function deny(address deniedContract) public onlyOperator { contractAllowlist[deniedContract] = false; }

    /**
     * @notice Sets the daily borrow limit for a specific market
     * @param market The address of the market contract
     * @param limit The daily borrow limit amount
     */
    function setDailyBorrowLimit(address market, uint limit) public onlyOperator { dailyBorrowLimit[market] = limit; }
    
    /**
     * @notice Sets the staleness threshold for Chainlink feeds
     * @param newStalenessThreshold The new staleness threshold denominated in seconds
     * @dev Only callable by operator
     */
    function setStalenessThreshold(address market, uint newStalenessThreshold) public onlyOperator { stalenessThreshold[market] = newStalenessThreshold; }
    
    /**
     * @notice sets the market specific minimum amount a debt a borrower needs to take on.
     * @param market The market to set the minimum debt for.
     * @param newMinDebt The new minimum amount of debt.
     * @dev This is to mitigate the creation of positions which are uneconomical to liquidate. Only callable by operator.
     */
    function setMinDebt(address market, uint newMinDebt) public onlyOperator {minDebts[market] = newMinDebt; }
    /**
     * @notice Checks if a borrow is allowed
     * @dev Currently the borrowController checks if contracts are part of an allow list and enforces a daily limit
     * @param msgSender The message sender trying to borrow
     * @param borrower The address being borrowed on behalf of
     * @param amount The amount to be borrowed
     * @return A boolean that is true if borrowing is allowed and false if not.
     */
    function borrowAllowed(address msgSender, address borrower, uint amount) public returns (bool) {
        updateDailyBorrowLimit(msg.sender);
        //Check if market exceeds daily limit
        if(remainingDailyBorrowLimit[msg.sender] < amount){
            return false;
        }
        unchecked{
            remainingDailyBorrowLimit[msg.sender] -= amount;
        }
        uint lastUpdated = DBR.lastUpdated(borrower);
        uint debts = DBR.debts(borrower);
        //Check to prevent effects of edge case bug
        if(lastUpdated > 0 && debts == 0 && lastUpdated != block.timestamp){
            //Important check, otherwise a user could repeatedly mint themsevles DBR
            require(DBR.markets(msg.sender), "Message sender is not a market");
            uint deficit = (block.timestamp - lastUpdated) * amount / 365 days;
            //If the contract is not a DBR minter, it should disallow borrowing for edgecase users
            if(!DBR.minters(address(this))) return false;
            //Mint user deficit caused by edge case bug
            DBR.mint(borrower, deficit);
        }
        //If the debt is below the minimum debt threshold, deny borrow
        if(isBelowMinDebt(msg.sender, borrower, amount)) return false;
        //If the chainlink oracle price feed is stale, deny borrow
        if(isPriceStale(msg.sender)) return false;
        //If the message sender is not a contract, then there's no need check allowlist
        if(msgSender == tx.origin) return true;
        return contractAllowlist[msgSender];
    }

    /**
     * @notice Reduces the daily limit used, when a user repays debt
     * @dev This is necessary to prevent a DOS attack, where a user borrows the daily limit and immediately repays it again.
     * @param amount Amount repaid in the market
     */
    function onRepay(uint amount) public {
        updateDailyBorrowLimit(msg.sender);
        unchecked{
            uint newLimit = remainingDailyBorrowLimit[msg.sender] + amount;
            uint dailyLimit = dailyBorrowLimit[msg.sender];
            remainingDailyBorrowLimit[msg.sender] = newLimit < dailyLimit ? newLimit : dailyLimit;
        }
    }

    /**
     * @notice Updates the daily borrow limit for the market
     * @param market The address of the market which limit will be updated
     */
    function updateDailyBorrowLimit(address market) internal {
        uint timeElapsed = block.timestamp - lastDailyBorrowLimitUpdate[market];
        if(timeElapsed == 0) return;
        // add daily limit capacity linearly based on time elapsed
        uint dailyLimit = dailyBorrowLimit[market];
        uint addedCapacity = timeElapsed * dailyLimit / 1 days;
        uint newLimit = remainingDailyBorrowLimit[market] + addedCapacity;
        // cap the limit to the maximum daily limit
        remainingDailyBorrowLimit[market]= newLimit < dailyLimit ? newLimit : dailyLimit;
        lastDailyBorrowLimitUpdate[msg.sender] = block.timestamp;
    }

    /**
     * @notice Returns the available borrow limit of a market
     * @param market The address of the market to return the available borrow limt
     */
    function availableBorrowLimit(address market) public view returns(uint) {
        uint timeElapsed = block.timestamp - lastDailyBorrowLimitUpdate[market];
        uint dailyLimit = dailyBorrowLimit[market];
        uint newLimit = remainingDailyBorrowLimit[market] + timeElapsed * dailyLimit / 1 days;
        return newLimit < dailyLimit ? newLimit : dailyLimit;
    }

    /**
     * @notice Checks if the price for the given market is stale.
     * @param market The address of the market for which the price staleness is to be checked.
     * @return bool Returns true if the price is stale, false otherwise.
     */
    function isPriceStale(address market) public view returns(bool){
        uint marketStalenessThreshold = stalenessThreshold[market];
        if(marketStalenessThreshold == 0) return false;
        IOracle oracle = IMarket(market).oracle();
        (IChainlinkFeed feed,) = oracle.feeds(IMarket(market).collateral());
        (,,,uint updatedAt,) = feed.latestRoundData();
        return block.timestamp - updatedAt > marketStalenessThreshold;
    }

    /**
     * @notice Checks if the borrower's debt in the given market is below the minimum debt after adding the specified amount.
     * @param market The address of the market for which the borrower's debt is to be checked.
     * @param borrower The address of the borrower whose debt is to be checked.
     * @param amount The amount to be added to the borrower's current debt before checking against the minimum debt.
     * @return bool Returns true if the borrower's debt after adding the amount is below the minimum debt, false otherwise.
     */
    function isBelowMinDebt(address market, address borrower, uint amount) public view returns(bool){
        //Optimization to check if borrow amount itself is higher than the minimum
        //This avoids an expensive lookup in the market
        uint minDebt = minDebts[market];
        if(amount >= minDebt) return false;
        return IMarket(market).debts(borrower) + amount < minDebt;
    }
}
