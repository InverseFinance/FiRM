// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestAnswer() external view returns (uint);
}

contract Oracle {

    struct FeedData {
        IChainlinkFeed feed;
        uint8 tokenDecimals;
    }

    address public operator;
    address public pendingOperator;
    mapping (address => FeedData) public feeds;
    mapping (address => uint) public fixedPrices;

    constructor(
        address _operator
    ) {
        operator = _operator;
    }

    modifier onlyOperator {
        require(msg.sender == operator, "ONLY OPERATOR");
        _;
    }

    function setPendingOperator(address newOperator_) public onlyOperator { pendingOperator = newOperator_; }
    function setFeed(address token, IChainlinkFeed feed, uint8 tokenDecimals) public onlyOperator { feeds[token] = FeedData(feed, tokenDecimals); }
    function setFixedPrice(address token, uint price) public onlyOperator { fixedPrices[token] = price; }

    function claimOperator() public {
        require(msg.sender == pendingOperator, "ONLY PENDING OPERATOR");
        operator = pendingOperator;
        pendingOperator = address(0);
        emit ChangeOperator(operator);
    }

    function getPrice(address token) external view returns (uint) {
        if(fixedPrices[token] > 0) return fixedPrices[token];
        if(feeds[token].feed != IChainlinkFeed(address(0))) {
            uint price = feeds[token].feed.latestAnswer();
            require(price > 0, "Invalid feed price");
            uint8 feedDecimals = feeds[token].feed.decimals();
            uint8 tokenDecimals = feeds[token].tokenDecimals;
            uint8 decimals = 36 - feedDecimals - tokenDecimals;
            return price * (10 ** decimals);

        }
        revert("Price not found");
    }

    event ChangeOperator(address indexed newOperator);

}