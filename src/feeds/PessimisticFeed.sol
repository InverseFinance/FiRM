// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";

contract PessimisticFeed {
    IChainlinkBasePriceFeed public immutable coin1Feed;
    IChainlinkBasePriceFeed public immutable coin2Feed;

    string public description;

    constructor(address _coin1Feed, address _coin2Feed) {
        coin1Feed = IChainlinkBasePriceFeed(_coin1Feed);
        coin2Feed = IChainlinkBasePriceFeed(_coin2Feed);
        require(
            coin1Feed.decimals() == coin2Feed.decimals() &&
                coin1Feed.decimals() == 18,
            "PessimisticFeed: DECIMALS_MISMATCH"
        );
        description = string(
            abi.encodePacked(
                "PessimisticFeed: ",
                coin1Feed.description(),
                " vs ",
                coin2Feed.description()
            )
        );
    }

    /**
     * @return roundId The round ID of the Chainlink price feed
     * @return minUsdprice The latest pessimistic token price in USD
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
            int256 usdPriceCoin1,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = coin1Feed.latestRoundData();

        (
            uint80 roundIdCoin2,
            int256 usdPriceCoin2,
            uint startedAtCoin2,
            uint updatedAtCoin2,
            uint80 answeredInRoundCoin2
        ) = coin2Feed.latestRoundData();

        // use lower price from usdPriceCoin1 and usdPriceCoin2
        int256 minUsdPrice = usdPriceCoin1 < usdPriceCoin2
            ? usdPriceCoin1
            : usdPriceCoin2;
        // use lowest updatedAt
        if (updatedAtCoin2 < updatedAt) {
            roundId = roundIdCoin2;
            startedAt = startedAtCoin2;
            updatedAt = updatedAtCoin2;
            answeredInRound = answeredInRoundCoin2;
        }
        return (roundId, minUsdPrice, startedAt, updatedAt, answeredInRound);
    }

    /** 
    @notice Retrieves the latest pessimistic price
    @return price The latest pessimistic price
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
