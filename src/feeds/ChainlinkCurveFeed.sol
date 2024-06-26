pragma solidity ^0.8.20;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";

// Combined Chainlink and Curve price_oracle, allows for additional fallback to be set via ChainlinkBasePriceFeed
/// @dev Implementation for Curve pools.
/// @dev Carefully review on Curve Pools when setting the k index for Asset or Target and the target index in the `coins` array
/// NOTE: If k is for Asset then targetIndex is Zero as in Curve otherwise the price calculation will be incorrect,
/// on the other side if k is for the Target then targetIndex has to be set to the index of the Target in the `coins` array (not Zero)
contract ChainlinkCurveFeed {
    int256 public constant SCALE = 1e18;
    /// @dev Chainlink base price feed implementation for the Asset to USD
    IChainlinkBasePriceFeed public immutable assetToUsd;
    /// @dev Curve pool
    ICurvePool public immutable curvePool;
    /// @dev k index for retriving Target or Asset value from the Curve pool price_oracle
    uint256 public immutable assetOrTargetK;
    /// @dev Decimals for this feed
    uint8 public immutable decimals;
    /// @dev Target index in Curve pool `coins` array
    uint256 public immutable targetIndex;

    constructor(
        address _assetToUsd,
        address _curvePool,
        uint256 _k,
        uint8 _decimals,
        uint256 _targetIndex
    ) {
        assetToUsd = IChainlinkBasePriceFeed(_assetToUsd);
        curvePool = ICurvePool(_curvePool);
        assetOrTargetK = _k;
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
                int(curvePool.price_oracle(assetOrTargetK));
        } else {
            usdPrice =
                (int(curvePool.price_oracle(assetOrTargetK)) *
                    assetToUsdPrice) /
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
