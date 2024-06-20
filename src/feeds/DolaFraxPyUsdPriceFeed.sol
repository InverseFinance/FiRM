// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";

contract DolaFraxPyUsdPriceFeed {
    error OnlyGov();

    ICurvePool public immutable dolaPyUSDFrax;

    IChainlinkBasePriceFeed public immutable mainFraxFeed;

    IChainlinkBasePriceFeed public immutable mainPyUSDFeed;

    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    modifier onlyGov() {
        if (msg.sender != gov) revert OnlyGov();
        _;
    }

    constructor(
        address _curvePool,
        address _mainFraxFeed,
        address _mainPyUSDFeed
    ) {
        dolaPyUSDFrax = ICurvePool(_curvePool);
        mainFraxFeed = IChainlinkBasePriceFeed(_mainFraxFeed);
        mainPyUSDFeed = IChainlinkBasePriceFeed(_mainPyUSDFeed);
    }

    /**
     * @return roundId The round ID of the Chainlink price feed
     * @return lpUsdprice The latest LP token price in USD
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
            int256 pyUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = mainPyUSDFeed.latestRoundData();

        (
            uint80 roundIdFrax,
            int256 fraxUsdPrice,
            uint startedAtFrax,
            uint updatedAtFrax,
            uint80 answeredInRoundFrax
        ) = mainFraxFeed.latestRoundData();

        int256 minUsdPrice;

        // If FRAX price is lower than pyUSD price, use FRAX price
        if (
            (fraxUsdPrice < pyUsdPrice && updatedAtFrax > 0) || pyUsdPrice == 0
        ) {
            minUsdPrice = fraxUsdPrice;
            roundId = roundIdFrax;
            startedAt = startedAtFrax;
            updatedAt = updatedAtFrax;
            answeredInRound = answeredInRoundFrax;
        } else {
            minUsdPrice = pyUsdPrice;
        }

        return (
            roundId,
            (int(dolaPyUSDFrax.get_virtual_price()) * minUsdPrice) / 10 ** 8,
            startedAt,
            updatedAt,
            answeredInRound
        );
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

    /**
     * @notice Sets a new gov address
     * @dev Can only be called by the current gov address
     * @param newGov The new gov address
     */
    function setGov(address newGov) external onlyGov {
        gov = newGov;
    }
}
