pragma solidity ^0.8.13;

interface IChainlinkFeed {
    function decimals() external view returns (uint8);

    function latestAnswer() external view returns (uint);
}

contract YETHFeed is IChainlinkFeed {
    uint8 decimals_ = 18;
    uint price_ = 2626e18;

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function latestAnswer() external view returns (uint) {
        return price_;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (0, int(price_), 0, 0, 0);
    }

    function changeAnswer(uint price) external {
        price_ = price;
    }
}
