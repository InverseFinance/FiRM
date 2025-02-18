// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";

contract SdeUSDFeed {
    error DecimalsMismatch();

    ICurvePool public immutable curvePool;
    uint256 public immutable k;
    IERC4626 public immutable sdeUSD;
    IChainlinkBasePriceFeed public immutable dolaFeed;
    uint256 public constant SCALE = 1e18;
    string public description;

    constructor(
        address _curvePool,
        uint256 _k,
        address _sdeUSD,
        address _dolaFeed
    ) {
        curvePool = ICurvePool(_curvePool);
        k = _k;
        sdeUSD = IERC4626(_sdeUSD);
        dolaFeed = IChainlinkBasePriceFeed(_dolaFeed);
        if (
            curvePool.decimals() != 18 ||
            sdeUSD.decimals() != 18 ||
            dolaFeed.decimals() != 18
        ) revert DecimalsMismatch();

        description = string(
            abi.encodePacked(
                "sdeUSD/USD using DOLA feed, sdeUSD/DOLA pool and sdeUSD/deUSD rate"
            )
        );
    }

    /**
     * @return roundId The round ID of DOLA price feed
     * @return sdeUSDToUsdPrice The latest sdeUSD price in USD
     * @return startedAt The timestamp when the latest round of DOLA feed started
     * @return updatedAt The timestamp when the latest round of DOLA feed was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        uint256 sdeUSDNormalizedToDola = curvePool.price_oracle(k);

        uint256 sdeUSDToDeUSDRate = sdeUSD.convertToAssets(SCALE);

        // Multiply Normalized sdeUSD/DOLA price by sdeUSD/DeUSD rate to get sdeUSD/DOLA price
        int256 sdeUSDToDolaPrice = int256(
            (sdeUSDNormalizedToDola * sdeUSDToDeUSDRate) / SCALE
        );

        (
            uint80 roundId,
            int256 dolaPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = dolaFeed.latestRoundData();

        // Multiply sdeUSD/DOLA price by DOLA/USD price to get sdeUSD/USD price
        int256 sdeUSDToUsdPrice = (sdeUSDToDolaPrice * dolaPrice) /
            int256(SCALE);
        return (
            roundId,
            sdeUSDToUsdPrice,
            startedAt,
            updatedAt,
            answeredInRound
        );
    }

    /** 
    @notice Retrieves the latest sdeUSD price
    @return price The latest sdeUSD price
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
