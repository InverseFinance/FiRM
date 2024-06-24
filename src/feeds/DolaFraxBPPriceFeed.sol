// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";

contract DolaFraxBPPriceFeed {
    ICurvePool public immutable dolaFraxBP;

    IChainlinkBasePriceFeed public immutable mainFraxFeed;

    IChainlinkBasePriceFeed public immutable mainUsdcFeed;

    constructor(
        address _curvePool,
        address _mainFraxFeed,
        address _mainUsdcFeed
    ) {
        dolaFraxBP = ICurvePool(_curvePool);
        mainFraxFeed = IChainlinkBasePriceFeed(_mainFraxFeed);
        mainUsdcFeed = IChainlinkBasePriceFeed(_mainUsdcFeed);
    }

    /**
     * @notice Retrieves the latest round data for the LP token price feed
     * @dev This function calculates the LP token price in USD using the lowest usd price for FRAX and USDC from a Chainlink oracle
     * and the virtual price from the DOLA-FRAX-USDC tricrypto pool.
     * If USDC/USD price is out of bounds, it will fallback to ETH/USD price oracle and USDC to ETH ratio from the tricrypto pool
     * @return roundId The round ID of the Chainlink price feed
     * @return lpUsdPrice The latest LP token price in USD computed from the virtual price and USDC/USD or FRAX/USD feed
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
            int256 usdcUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = mainUsdcFeed.latestRoundData();

        (
            uint80 roundIdFrax,
            int256 fraxUsdPrice,
            uint startedAtFrax,
            uint updatedAtFrax,
            uint80 answeredInRoundFrax
        ) = mainFraxFeed.latestRoundData();

        int256 minUsdPrice;

        // If FRAX price is lower than USDC price, use FRAX price
        if (
            (fraxUsdPrice < usdcUsdPrice && updatedAtFrax > 0) ||
            usdcUsdPrice == 0
        ) {
            minUsdPrice = fraxUsdPrice;
            roundId = roundIdFrax;
            startedAt = startedAtFrax;
            updatedAt = updatedAtFrax;
            answeredInRound = answeredInRoundFrax;
        } else {
            minUsdPrice = usdcUsdPrice;
        }

        return (
            roundId,
            (int(dolaFraxBP.get_virtual_price()) * minUsdPrice) / 10 ** 8,
            startedAt,
            updatedAt,
            answeredInRound
        );
    }

    /** 
    @notice Retrieves the latest price for the LP token
    @return price The latest price for the LP token
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
