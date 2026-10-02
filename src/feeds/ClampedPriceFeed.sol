// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IChainlinkFeed} from "src/interfaces/IChainlinkFeed.sol";

/// @notice Normalizes a Chainlink-compatible feed to 18 decimals and applies an immutable price ceiling.
contract ClampedPriceFeed {
    error ZeroAddress();
    error InvalidClampPrice(int256 clampPrice);
    error UnsupportedFeedDecimals(uint8 decimals);

    IChainlinkFeed public immutable feed;
    uint8 public immutable feedDecimals;
    uint256 public immutable scale;
    int256 public immutable clampPrice;

    string public description;

    constructor(address _feed, int256 _clampPrice) {
        if (_feed == address(0)) revert ZeroAddress();
        if (_clampPrice <= 0) revert InvalidClampPrice(_clampPrice);

        feed = IChainlinkFeed(_feed);
        feedDecimals = feed.decimals();
        if (feedDecimals > 18) {
            revert UnsupportedFeedDecimals(feedDecimals);
        }

        scale = 10 ** (18 - feedDecimals);
        clampPrice = _clampPrice;
        description = string.concat("Clamped ", feed.description());
    }

    function latestRoundData()
        public
        view
        returns (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, price, startedAt, updatedAt, answeredInRound) = feed.latestRoundData();
        price *= int256(scale);
        if (price > clampPrice) price = clampPrice;
    }

    function latestAnswer() external view returns (int256) {
        (, int256 price,,,) = latestRoundData();
        return price;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}
