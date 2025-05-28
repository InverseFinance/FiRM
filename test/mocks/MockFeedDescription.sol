pragma solidity ^0.8.13;

interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestAnswer() external view returns (uint);
}

contract Aggregator {
    function maxAnswer() external pure returns (int192) {
        return type(int192).max;
    }
    function minAnswer() external pure returns (int192) {
        return type(int192).min;
    }
}

contract MockFeedDescription is IChainlinkFeed {
    uint8 public decimals;
    int price;
    uint updatedAt;
    string public description;
    Aggregator public aggregator;

    constructor(uint8 _decimals, int _price, string memory _description) {
        updatedAt = block.timestamp;
        decimals = _decimals;
        price = _price;
        description = _description;
        aggregator = new Aggregator();
    }

    function latestAnswer() external view returns (uint) {
        return uint(price);
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, price, 0, updatedAt, 0);
    }

    function changeAnswer(uint _price) external {
        price = int(_price);
    }

    function changeUpdatedAt(uint _updatedAt) external {
        updatedAt = _updatedAt;
    }
}
