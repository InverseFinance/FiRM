pragma solidity ^0.8.13;

interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestAnswer() external view returns (uint);
}

contract EthFeed is IChainlinkFeed {
    uint8 decimals_ = 18;
    uint price = 1600e18;
    uint updatedAt;

    constructor(){
        updatedAt = block.timestamp;
    }

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function latestAnswer() external view returns (uint) {
        return price;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0,int(price),0,updatedAt,0);
    }

    function changeAnswer(uint _price) external {
        price = _price;
    }
    
    function changeUpdatedAt(uint _updatedAt) external {
        updatedAt = _updatedAt;
    }
}
