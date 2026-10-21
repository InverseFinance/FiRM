// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IPT {
    function expiry() external view returns (uint256);
    function decimals() external view returns(uint8);
}
/// @title PT Token discounted NAV Feed
/// @notice A contract to get the discounted NAV price using underlying Chainlink Wrapper feed to price PT tokens
contract PTDiscountedNAVFeed {
    error DecimalsMismatch();
    error MaturityPassed();
    error DiscountOverflow();

    IChainlinkBasePriceFeed public immutable underlyingFeed;
    uint public immutable maturity;
    uint public immutable baseDiscountPerYear;
    string public description;

    constructor(address _underlyingFeed, address ptToken, uint _baseDiscountPerYear) {
        underlyingFeed = IChainlinkBasePriceFeed(_underlyingFeed);
        baseDiscountPerYear = _baseDiscountPerYear;
        if (underlyingFeed.decimals() != 18 || IPT(ptToken).decimals() != 18)
            revert DecimalsMismatch();
        maturity = IPT(ptToken).expiry();
        if(maturity <= block.timestamp) revert MaturityPassed();
        if(getDiscount() > 1e18) revert DiscountOverflow();
        description = string(
            abi.encodePacked(
                underlyingFeed.description(), " with yearly discount rate of ", Strings.toString(_baseDiscountPerYear)
            )
        );
    }

    /**
     * @return roundId The round ID of underlying Chainlink price feed
     * @return discountedNAVPrice The latest discounted NAV price of the PT token
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
            int256 underlyingPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = underlyingFeed.latestRoundData();

        uint256 discount = getDiscount();

        //If discount is 100% or more, we price the asset at the lowest positive price possible
        int256 discountedNavPrice = int256(1e18 - discount) * underlyingPrice / 1e18;
        //Make sure a 0 price isn't returned
        if(discountedNavPrice == 0) discountedNavPrice = 1;
        
        return (roundId, discountedNavPrice, startedAt, updatedAt, answeredInRound);
    }

    function getDiscount() public view returns (uint256) {
        if(maturity <= block.timestamp) return 0;
        uint timeLeft = maturity - block.timestamp;
        uint discount = (timeLeft * baseDiscountPerYear) / 365 days;
        //Bound discount to avoid overflow
        return discount > 1e18 ? 1e18 : discount;
    }

    /** 
    @notice Retrieves the latest discounted NAV price of the PT token
    @return price The latest discounted NAV price
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
