pragma solidity ^0.8.13;
import "src/interfaces/IOracle.sol";

contract MockFeed is IChainlinkFeed {
    uint8 public decimals;
    uint price;
    uint lastUpdate;

    constructor(uint8 _decimals){
        decimals = _decimals;
        lastUpdate = block.timestamp;
    }

    function latestAnswer() external view returns (uint) {
        return price;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0,int(price),0,lastUpdate,0);
    }

    function setPrice(uint _price) external {
        price = _price;
    }

    function setLastUpdate(uint _lastUpdate) external {
        lastUpdate = _lastUpdate;
    }
}

