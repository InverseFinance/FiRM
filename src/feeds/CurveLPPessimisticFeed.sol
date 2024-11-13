// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract CurveLPPessimisticFeed {
    ICurvePool public immutable curvePool;

    IChainlinkBasePriceFeed public immutable coin1Feed;
    IChainlinkBasePriceFeed public immutable coin2Feed;

    string public description;

    constructor(
        address _curvePool,
        address _coin1Feed,
        address _coin2Feed,
        bool _oldCurveImpl
    ) {
        curvePool = ICurvePool(_curvePool);
        coin1Feed = IChainlinkBasePriceFeed(_coin1Feed);
        coin2Feed = IChainlinkBasePriceFeed(_coin2Feed);
        require(
            coin1Feed.decimals() == coin2Feed.decimals() &&
                coin1Feed.decimals() == 18,
            "CurveLPPessimisticFeed: DECIMALS_MISMATCH"
        );
        if (_oldCurveImpl)
            description = string(
                abi.encodePacked(
                    IERC20(curvePool.lp_token()).symbol(),
                    " / USD"
                )
            );
        else
            description = string(
                abi.encodePacked(curvePool.symbol(), " / USD")
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

        int256 minLpUsdPrice;

        // If coin1 price is lower than coin2 price, use coin1 price
        if (usdPriceCoin1 < usdPriceCoin2) {
            minLpUsdPrice =
                (usdPriceCoin1 * int256(curvePool.get_virtual_price())) /
                int256(10 ** decimals());
        } else {
            minLpUsdPrice =
                (usdPriceCoin2 * int(curvePool.get_virtual_price())) /
                int256(10 ** decimals());
        }
        if (updatedAtCoin2 < updatedAt) {
            roundId = roundIdCoin2;
            startedAt = startedAtCoin2;
            updatedAt = updatedAtCoin2;
            answeredInRound = answeredInRoundCoin2;
        }
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
