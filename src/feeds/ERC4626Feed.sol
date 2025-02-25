// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IChainlinkCurveFeed} from "src/interfaces/IChainlinkCurveFeed.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/// @title ERC4626Feed
/// @notice This contract is a generalized contract for an ERC4626 vault which has a feed in a Normalized Asset to USD price
/// @dev It will convert the normalized asset to USD price to the Asset to USD price using the vault's rate
/// @dev This is contract is meant to be used in combination with ChainlinkCurveFeed or ChainlinkCurve2CoinsFeed contracts.

contract ERC4626Feed {
    error DecimalsMismatch();

    // ChainlinkCurve feed for the normalized asset to USD price
    IChainlinkCurveFeed public immutable feed;
    // ERC4626 vault asset
    IERC4626 public immutable vault;
    // Scaling factor
    uint256 public constant SCALE = 1e18;
    // Description of the feed
    string public description;

    constructor(address _vault, address _feed) {
        feed = IChainlinkCurveFeed(_feed);
        vault = IERC4626(_vault);

        if (feed.decimals() != 18 || vault.decimals() != 18)
            revert DecimalsMismatch();

        description = string(
            abi.encodePacked(
                feed.description(),
                " using ",
                vault.symbol(),
                " vault rate"
            )
        );
    }

    /**
     * @return roundId The round ID from the feed
     * @return assetToUsdPrice The latest asset price in USD
     * @return startedAt The timestamp when the latest round of feed started
     * @return updatedAt The timestamp when the latest round of feed was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (
            uint80 roundId,
            int256 normalizedAssetToUsdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        uint256 assetToUnderlyingRate = vault.previewRedeem(SCALE);

        // Multiply Normalized Asset/USD price by asset/underlying rate to get Asset/USD price
        int256 assetToUsdPrice = int256(
            (uint256(normalizedAssetToUsdPrice) * assetToUnderlyingRate) / SCALE
        );

        return (
            roundId,
            assetToUsdPrice,
            startedAt,
            updatedAt,
            answeredInRound
        );
    }

    /** 
    @notice Retrieves the latest asset price
    @return price The latest asset price
    */
    function latestAnswer() external view returns (int256) {
        (, int256 price, , , ) = latestRoundData();
        return price;
    }

    /**
     * @notice Retrieves number of decimals for the price feed
     * @return decimals The number of decimals for the price feed
     */
    function decimals() public pure returns (uint8) {
        return 18;
    }
}
