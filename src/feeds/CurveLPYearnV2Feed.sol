// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";

contract CurveLPYearnV2Feed {
    IYearnVaultV2 public immutable yearn;

    IChainlinkBasePriceFeed public immutable coinFeed;

    string public description;

    constructor(address _yearn, address _coinFeed) {
        yearn = IYearnVaultV2(_yearn);
        coinFeed = IChainlinkBasePriceFeed(_coinFeed);
        require(
            coinFeed.decimals() == 18,
            "CurveLPYearnV2Feed: Invalid decimals"
        );
        description = string(
            abi.encodePacked("YearnV2 for ", coinFeed.description())
        );
    }

    /**
     * @return roundId The round ID of the Chainlink price feed
     * @return minLpUsdprice The latest Yearn V2 token price in USD
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

        uint256 lpForYToken = YearnVaultV2Helper.collateralToAsset(yearn, 1e18);

        int256 minLpUsdPrice;
        minLpUsdPrice =
            (usdPriceCoin * int(lpForYToken)) /
            int(10 ** decimals());

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
