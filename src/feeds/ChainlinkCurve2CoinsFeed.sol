pragma solidity ^0.8.20;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";

// Combined Chainlink and price oracle feed for a 2 Coin Curve pool, allows for additional fallback to be set via ChainlinkBasePriceFeed
/// @dev Implementation for a 2 Coins Curve pool
/// @dev Carefully review on Curve Pools when setting the target index from the `coins` array
contract ChainlinkCurve2CoinsFeed {
    int256 public constant SCALE = 1e18;
    /// @dev Chainlink base price feed implementation for the asset to USD
    IChainlinkBasePriceFeed public immutable assetToUsd;
    /// @dev 2 Coins Curve pool
    ICurvePool public immutable curvePool;
    /// @dev Decimals for this feed
    uint8 public immutable decimals;
    /// @dev Target index in Curve pool `coins` array
    uint256 public immutable targetIndex;

    constructor(
        address _assetToUsd,
        address _curvePool,
        uint8 _decimals,
        uint256 _targetIndex
    ) {
        assetToUsd = IChainlinkBasePriceFeed(_assetToUsd);
        curvePool = ICurvePool(_curvePool);
        decimals = _decimals;
        targetIndex = _targetIndex;
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

        if (targetIndex == 0) {
            usdPrice =
                (assetToUsdPrice * SCALE) /
                int(curvePool.price_oracle());
        } else {
            usdPrice =
                (int(curvePool.price_oracle()) * assetToUsdPrice) /
                SCALE;
        }

        return (roundId, usdPrice, startedAt, updatedAt, answeredInRound);
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
}
