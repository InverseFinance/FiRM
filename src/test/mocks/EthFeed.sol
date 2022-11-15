pragma solidity ^0.8.13;

interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestAnswer() external view returns (uint);
}

contract EthFeed is IChainlinkFeed {
    uint8 decimals_ = 18;
    uint price_ = 1600e18;

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function latestAnswer() external view returns (uint) {
        return price_;
    }

    function latestRound() external view returns (uint) {
        return price_;
    }

    function changeAnswer(uint price) external {
        price_ = price;
    }
}
