// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/// @title USDeFeed
/// @notice A contract to get the USDe price using sUSDe Chainlink Wrapper feed and sUSDe/USDe rate
contract USDeBeforeMaturityFeed {
    error DecimalsMismatch();

    IChainlinkBasePriceFeed public immutable sUSDeFeed;
    IERC4626 public immutable sUSDe;

    string public description;

    constructor(address _sUSDeFeed, address _sUSDe) {
        sUSDeFeed = IChainlinkBasePriceFeed(_sUSDeFeed);
        sUSDe = IERC4626(_sUSDe);
        if (sUSDeFeed.decimals() != 18 || sUSDe.decimals() != 18)
            revert DecimalsMismatch();

        description = string(
            abi.encodePacked(
                "USDe/USD Feed using sUSDe Chainlink feed and sUSDe/USDe rate"
            )
        );
    }

    /**
     * @return roundId The round ID of sUSDe Chainlink price feed
     * @return USDeUsdPrice The latest USDe price in USD
     * @return startedAt The timestamp when the latest round of Chainlink price feed started
     * @return updatedAt The timestamp when the latest round of Chainlink price feed was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (
            uint80 roundId,
            int256 sUSDePrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = sUSDeFeed.latestRoundData();

        uint256 sUSDeToUSDeRate = sUSDe.convertToAssets(1e18);

        // divide sUSDe/USD by sUSDe/USDe rate to get USDe/USD price
        int256 USDeUsdPrice = (sUSDePrice * 1e18) / int256(sUSDeToUSDeRate);

        return (roundId, USDeUsdPrice, startedAt, updatedAt, answeredInRound);
    }

    /** 
    @notice Retrieves the latest USDe price
    @return price The latest USDe price
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
