// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed, ICurvePool} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import "src/feeds/CurveLPYearnV2Feed.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";
import {CurveLPPessimisticFeed} from "src/feeds/CurveLPPessimisticFeed.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";

abstract contract CurveLPYearnV2FeedBaseTest is Test, ConfigAddr {
    CurveLPYearnV2Feed feed;
    CurveLPPessimisticFeed lpFeed; // main coin1 feed

    ICurvePool public curvePool; // Curve Pool for virtual price

    uint256 public constant SCALE = 1e18;

    IYearnVaultV2 public yearn;

    function init(address _lpFeed, address _curvePool, address _yearn) public {
        lpFeed = CurveLPPessimisticFeed(_lpFeed);
        curvePool = ICurvePool(_curvePool);
        yearn = IYearnVaultV2(_yearn);

        feed = new CurveLPYearnV2Feed(address(yearn), address(lpFeed));
    }

    function test_decimals() public view {
        assertEq(feed.decimals(), 18);
    }

    function test_latestAnswer() public view {
        (, int256 lpUsdPrice, , , ) = feed.latestRoundData();

        assertEq(feed.latestAnswer(), lpUsdPrice);
    }

    function test_latestRoundData() public view {
        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        (
            uint80 oracleRoundId,
            int256 oracleLpToUsdPrice,
            uint oracleStartedAt,
            uint oracleUpdatedAt,
            uint80 oracleAnsweredInRound
        ) = _calculateOracleLpPrice();

        assertEq(roundId, oracleRoundId);
        assertEq(lpUsdPrice, oracleLpToUsdPrice);
        assertEq(startedAt, oracleStartedAt);
        assertEq(updatedAt, oracleUpdatedAt);
        assertEq(answeredInRound, oracleAnsweredInRound);
    }

    function test_use_LP_feed() public {
        (
            uint80 clRoundId,
            int256 coin1UsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = lpFeed.latestRoundData();

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        uint256 estimLPUsdPrice = uint256(
            ((YearnVaultV2Helper.collateralToAsset(yearn, 1e18) *
                uint256(coin1UsdPrice)) / 10 ** lpFeed.decimals())
        );
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);
        assertEq(uint256(lpUsdPrice), estimLPUsdPrice);
    }

    function _calculateOracleLpPrice()
        internal
        view
        returns (
            uint80 oracleRoundId,
            int256 oracleLpToUsdPrice,
            uint oracleStartedAt,
            uint oracleUpdatedAt,
            uint80 oracleAnsweredInRound
        )
    {
        int oracleMinToUsdPrice;

        (
            oracleRoundId,
            oracleMinToUsdPrice,
            oracleStartedAt,
            oracleUpdatedAt,
            oracleAnsweredInRound
        ) = lpFeed.latestRoundData();

        if ((oracleUpdatedAt > 0)) {
            oracleLpToUsdPrice =
                (oracleMinToUsdPrice *
                    int(YearnVaultV2Helper.collateralToAsset(yearn, 1e18))) /
                int(10 ** lpFeed.decimals());
        } else {
            oracleUpdatedAt = 0;
        }
    }

    function _mockCall_Chainlink(
        address target,
        uint80 roundId,
        int256 price,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) internal {
        vm.mockCall(
            target,
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(roundId, price, startedAt, updatedAt, answeredInRound)
        );
    }
}
