// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/interfaces/IChainlinkFeed.sol";

contract PriceFeedNoStale {
    IChainlinkFeed public immutable feed;
    string public description;

    constructor(
        address _feed
    ) {
        feed = IChainlinkFeed(_feed);
        require(feed.decimals() == 18, "Wrong Decimals");
        description = feed.description();
    }

    /**
     * @notice Retrieves the latest round data for the asset token price feed
     * @return roundId Will return 0
     * @return usdPrice The latest asset price in USD with 18 decimals
     * @return startedAt Will return 0
     * @return updatedAt Will return block.timestamp
     * @return answeredInRound Will return 0
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
        return (0, feed.latestAnswer(), 0, block.timestamp, 0 );
    }

    /**
     * @notice Returns the latest price only
     * @dev Unlike chainlink oracles, the latestAnswer will always be the same as in the latestRoundData
     * @return int256 Returns the last finalized price of the chainlink oracle
     */
    function latestAnswer() external view returns (int256) {
        return feed.latestAnswer();
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}
