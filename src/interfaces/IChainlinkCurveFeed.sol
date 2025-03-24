pragma solidity ^0.8.13;

import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";

interface IChainlinkCurveFeed {
    function decimals() external view returns (uint8 decimals);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 crvUsdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestAnswer() external view returns (int256 price);

    function description() external view returns (string memory description);

    function assetToUsd() external view returns (IChainlinkBasePriceFeed feed);

    function curvePool() external view returns (ICurvePool pool);

    function targetIndex() external view returns (uint256 index);

    function assetOrTargetK() external view returns (uint256 k);
}
