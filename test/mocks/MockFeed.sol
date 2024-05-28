pragma solidity ^0.8.13;

interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestAnswer() external view returns (uint);
}

contract MockFeed is IChainlinkFeed {
    uint8 public decimals;
    int price;
    uint updatedAt;

    constructor(uint8 _decimals, int _price){
        updatedAt = block.timestamp;
        decimals = _decimals;
        price = _price;
    }

    function latestAnswer() external view returns (uint) {
        return uint(price);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return(0, price, 0, updatedAt, 0);
    }

    function changeAnswer(uint _price) external {
        price = int(_price);
    }

    function changeUpdatedAt(uint _updatedAt) external {
        updatedAt = _updatedAt;
    }
}
