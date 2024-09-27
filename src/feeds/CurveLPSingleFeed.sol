// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";

contract CurveLPSingleFeed {
    ICurvePool public immutable curvePool;

    IChainlinkBasePriceFeed public immutable coinFeed;

    constructor(address _curvePool, address _coinFeed) {
        curvePool = ICurvePool(_curvePool);
        coinFeed = IChainlinkBasePriceFeed(_coinFeed);
        require(
            coinFeed.decimals() == 18,
            "CurveLPSingleFeed: Invalid decimals"
        );
    }

    /**
     * @return roundId The round ID of the Chainlink price feed
     * @return minLpUsdprice The latest LP token price in USD
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
            int256 usdPriceCoin,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = coinFeed.latestRoundData();

        int256 minLpUsdPrice;
        minLpUsdPrice =
            (usdPriceCoin * int(curvePool.get_virtual_price())) /
            int(10 ** coinFeed.decimals());

        return (roundId, minLpUsdPrice, startedAt, updatedAt, answeredInRound);
    }

    /** 
    @notice Retrieves the latest price for LP token
    @return price The latest price for LP token
    */
    function latestAnswer() external view returns (int256) {
        (, int256 price, , , ) = latestRoundData();
        return price;
    }

    /**
     * @notice Retrieves number of decimals for the LP token price feed
     * @return decimals The number of decimals for the LP token price feed
     */
    function decimals() public pure returns (uint8) {
        return 18;
    }
}
