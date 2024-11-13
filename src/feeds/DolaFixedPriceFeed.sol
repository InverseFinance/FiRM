// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DolaFixedPriceFeed
 * @notice Fixed price feed for Dola
 * @dev This contract is used to provide a fixed price feed for DOLA within Inverse FiRM Protocol
 * Don't use it for external integrations
 */

contract DolaFixedPriceFeed {
    uint8 public constant DECIMALS = 18;
    int256 public constant PRICE = 1e18;
    string public constant description = "DOLA / USD";

    /**
     * @notice Retrieves the price and current timestamp for DOLA price feed
     * @dev This function doens't return the round ID, startedAt and answeredInRound as it's not relevant for DOLA price within Inverse Feeds system
     * @return roundId
     * @return usdPrice The fixed price of DOLA
     * @return startedAt
     * @return updatedAt The current timestamp
     * @return answeredInRound
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
        return (0, PRICE, 0, block.timestamp, 0);
    }

    /**
     * @notice Returns the latest price only
     * @dev Unlike chainlink oracles, the latestAnswer will always be the same as in the latestRoundData
     * @return int256 Returns the finalized price
     */
    function latestAnswer() external view returns (int256) {
        (, int256 latestPrice, , , ) = latestRoundData();
        return latestPrice;
    }

    /**
     * @notice Retrieves number of decimals for the DOLA price feed conforming to the Chainlink standard
     * @return decimals The number of decimals
     */
    function decimals() public pure returns (uint8) {
        return DECIMALS;
    }
}
