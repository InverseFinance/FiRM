pragma solidity ^0.8.20;
import {IChainlinkFeed} from "src/interfaces/IChainlinkFeed.sol";

contract ChainlinkBridgeAssetFeed {
    IChainlinkFeed public immutable collateralToBridgeAsset;
    IChainlinkFeed public immutable bridgeAssetToUsd;
    bool public immutable bridgeAssetDenominator;
    string public description;

    /**
     * @notice Oracle for the USD price of a collateral asset derived by combining a collateral-bridgeAsset oracle and bridgeAsset-USD oracle
     * @param _collateralToBridgeAsset Chainlink oracle returning the collateral/bridgeAsset OR bridgeAsset/collateral price
     * @param _bridgeAssetToUsd Chainlink oracle returning the bridgeAsset/USD price
     * @param _bridgeAssetDenominator If true, the `_collateralToBridgeAsset` oracle will return collateral/bridgeAsset, if false, bridgeAsset/collateral.
     * @dev We assume the underlying oracles have already been normalized using our standard chainlink feed. These feeds should also be used for fallback logic.
     */
    constructor(address _collateralToBridgeAsset, address _bridgeAssetToUsd, bool _bridgeAssetDenominator){
        collateralToBridgeAsset = IChainlinkFeed(_collateralToBridgeAsset);
        bridgeAssetToUsd = IChainlinkFeed(_bridgeAssetToUsd);
        bridgeAssetDenominator = _bridgeAssetDenominator;
        if(_bridgeAssetDenominator){
            description = string(abi.encodePacked(collateralToBridgeAsset.description(), " * ", bridgeAssetToUsd.description()));
        } else {
            description = string(abi.encodePacked(bridgeAssetToUsd.description(), " / (", collateralToBridgeAsset.description(),")"));
        }
        require(collateralToBridgeAsset.decimals() == 18, "collateralToBridgeAsset feed not normalized");
        require(bridgeAssetToUsd.decimals() == 18, "bridgeAssetToUsd feed not normalize");
    }

    function decimals() external view returns (uint8) {
        return 18;
    }

    /**
     * @notice Retrieves the latest round data for the collateral token price feed
     * @dev This function calculates the collateral price in USD by combining the bridgeAsset to USD price from a Chainlink oracle and the collateral to bridgeAsset ratio from the bridgeAsset Chainlink oracle
     * @return roundId The round ID of the Chainlink price feed for the feed with the lowest updatedAt feed
     * @return bridgeAssetToUsdPrice The latest collateral price in USD computed from the collateral/bridgeAsset and bridgeAsset/USD feeds
     * @return startedAt The timestamp when the latest round of Chainlink price feed started of the lowest last updatedAt feed
     * @return updatedAt The lowest timestamp when either of the latest round of Chainlink price feed was updated
     * @return answeredInRound The round ID in which the answer was computed of the lowest updatedAt feed
     */
    function latestRoundData()
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (
            uint80 collateralToBridgeAssetRoundId,
            int256 collateralToBridgeAssetPrice,
            uint collateralToBridgeAssetStartedAt,
            uint collateralToBridgeAssetUpdatedAt,
            uint80 collateralToBridgeAssetAnsweredInRound
        ) = collateralToBridgeAsset.latestRoundData();
        (
            uint80 bridgeAssetToUsdRoundId,
            int256 bridgeAssetToUsdPrice,
            uint bridgeAssetToUsdStartedAt,
            uint bridgeAssetToUsdUpdatedAt,
            uint80 bridgeAssetToUsdAnsweredInRound
        ) = bridgeAssetToUsd.latestRoundData();
        int price;
        if(bridgeAssetDenominator){
            price = bridgeAssetToUsdPrice * collateralToBridgeAssetPrice / 10 ** 18;
        } else {
            price = bridgeAssetToUsdPrice *  10 ** 18 / collateralToBridgeAssetPrice;
        }
        if (collateralToBridgeAssetUpdatedAt < bridgeAssetToUsdUpdatedAt) {
            return (
                collateralToBridgeAssetRoundId,
                price,
                collateralToBridgeAssetStartedAt,
                collateralToBridgeAssetUpdatedAt,
                collateralToBridgeAssetAnsweredInRound
            );
        } else {
            return (
                bridgeAssetToUsdRoundId,
                price,
                bridgeAssetToUsdStartedAt,
                bridgeAssetToUsdUpdatedAt,
                bridgeAssetToUsdAnsweredInRound
            );
        }
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
