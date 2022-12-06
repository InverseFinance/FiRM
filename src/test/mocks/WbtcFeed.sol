pragma solidity ^0.8.13;

interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestAnswer() external view returns (uint);
}

contract WbtcFeed is IChainlinkFeed {
    uint8 decimals_ = 8;
    uint price_ = 16000e8;

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function latestAnswer() external view returns (uint) {
        return price_;
    }

    function changeAnswer(uint price) external {
        price_ = price;
    }
}
