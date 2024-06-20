pragma solidity ^0.8.20;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";

// Combined Chainlink and Curve price_oracle, allows for additional fallbacks to be set via ChainlinkBasePriceFeed

contract ChainlinkPriceOracleStablePriceFeed {
    int256 public constant SCALE = 1e18;
    IChainlinkBasePriceFeed public immutable assetToUsd;
    ICurvePool public immutable curvePool;
    uint256 public immutable assetK;
    uint8 public immutable decimals;

    address public owner;
    address public pendingOwner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner, "Only pending owner");
        _;
    }

    constructor(
        address _owner,
        address _assetToUsd,
        address _curvePool,
        uint256 _assetK,
        uint8 _decimals
    ) {
        owner = _owner;
        assetToUsd = IChainlinkBasePriceFeed(_assetToUsd);
        curvePool = ICurvePool(_curvePool);
        assetK = _assetK;
        decimals = _decimals;
    }

    /**
     * @notice Retrieves the latest round data for the asset token price feed
     * @return roundId The round ID of the Chainlink price feed for the feed with the lowest updatedAt feed
     * @return usdPrice The latest asset price in USD
     * @return startedAt The timestamp when the latest round of Chainlink price feed started of the lowest last updatedAt feed
     * @return updatedAt The lowest timestamp when either of the latest round of Chainlink price feed was updated
     * @return answeredInRound The round ID in which the answer was computed of the lowest updatedAt feed
     */
    function latestRoundData()
        public
        view
        returns (
            uint80 roundId,
            int256 usdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        int256 assetToUsdPrice;
        (
            roundId,
            assetToUsdPrice,
            startedAt,
            updatedAt,
            answeredInRound
        ) = assetToUsd.latestRoundData();
        return (
            roundId,
            (assetToUsdPrice * SCALE) / int(curvePool.price_oracle(assetK)),
            startedAt,
            updatedAt,
            answeredInRound
        );
    }

    /**
     * @notice Returns the latest price only
     * @dev Unlike chainlink oracles, the latestAnswer will always be the same as in the latestRoundData
     * @return int256 Returns the last finalized price of the chainlink oracle
     */
    function latestAnswer() external view returns (int256) {
        (, int256 latestPrice, , , ) = latestRoundData();
        return latestPrice;
    }

    function setPendingOwner(address newPendingOwner) public onlyOwner {
        pendingOwner = newPendingOwner;
    }

    function acceptOwner() public onlyPendingOwner {
        owner = pendingOwner;
        pendingOwner = address(0);
    }
}
