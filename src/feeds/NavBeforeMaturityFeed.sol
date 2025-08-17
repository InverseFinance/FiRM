// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

interface INavFeed {
    function maturity() external view returns (uint256);
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80);
}
/// @title Feed Before Maturity using NAV
/// @notice A contract to get the collateral price using a Chainlink Wrapper feed and NAV
contract NavBeforeMaturityFeed {
    error DecimalsMismatch();
    error MaturityPassed();

    IChainlinkBasePriceFeed public immutable feed;
    INavFeed public immutable navFeed;

    string public description;

    constructor(address _feed, address _navFeed) {
        feed = IChainlinkBasePriceFeed(_feed);
        navFeed = INavFeed(_navFeed);
        if (feed.decimals() != 18 || navFeed.decimals() != 18)
            revert DecimalsMismatch();
        if(navFeed.maturity() <= block.timestamp) revert MaturityPassed();
        description = string(
            abi.encodePacked(
                feed.description()," with NAV"
            )
        );
    }

    /**
     * @return roundId The round ID of Collateral Chainlink price feed
     * @return collateralDiscountPrice The latest collateral price in USD using NAV
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
            int256 collateralPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();


        (,int256 navDiscountedPrice,,,)= navFeed.latestRoundData();
        int256 collateralDiscountPrice = (collateralPrice * navDiscountedPrice) / 1e18;
        
        return (roundId, collateralDiscountPrice, startedAt, updatedAt, answeredInRound);
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
