// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import {ICurvePool} from "src/feeds/CurveLPSingleFeed.sol";
import "src/feeds/CurveLPYearnV2Feed.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";

abstract contract CurveLPYearnV2FeedBaseTest is Test, ConfigAddr {
    CurveLPYearnV2Feed feed;
    ChainlinkBasePriceFeed coin1Feed; // main coin1 feed

    ChainlinkBasePriceFeed baseClFallCoin1; //cl base price feed for coin1 fallback

    ChainlinkCurve2CoinsFeed coin1Fallback; // coin1 fallback

    ICurvePool public curvePool; // Curve Pool for virtual price

    IChainlinkFeed public coin1ClFallback; // Chainlink feed for coin1 fallback

    uint256 SCALE;

    IYearnVaultV2 public yearn;

    function init(
        address _baseClFallCoin1,
        address _coin1Fallback,
        address _coin1Feed,
        address _curvePool,
        address _yearn
    ) public {
        baseClFallCoin1 = ChainlinkBasePriceFeed(_baseClFallCoin1);
        coin1Fallback = ChainlinkCurve2CoinsFeed(_coin1Fallback);
        SCALE = uint(coin1Fallback.SCALE());
        coin1Feed = ChainlinkBasePriceFeed(_coin1Feed);
        curvePool = ICurvePool(_curvePool);
        yearn = IYearnVaultV2(_yearn);
        coin1ClFallback = coin1Fallback.assetToUsd();

        feed = new CurveLPYearnV2Feed(address(yearn), address(coin1Feed));
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

    function test_use_coin1_main_feed() public view {
        (
            uint80 clRoundId,
            int256 coin1UsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = coin1Feed.assetToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        uint256 estimLPUsdPrice = uint256(
            ((YearnVaultV2Helper.collateralToAsset(yearn, 1e18) *
                uint256(coin1UsdPrice)) / 10 ** 8)
        );
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);
        assertEq(uint256(lpUsdPrice), estimLPUsdPrice);
    }

    function test_coin1_Out_of_bounds_MAX_use_coin1_Fallback_() public {
        //Set Out of MAX bounds coin1 main price
        _mockCall_Chainlink(
            address(coin1Feed.assetToUsd()),
            0,
            IAggregator(coin1Feed.assetToUsd().aggregator()).maxAnswer(),
            0,
            0,
            0
        );

        // Use coin1 fallback data (from coin1 fallback chainlink feed)
        (
            uint80 roundIdFall,
            int256 coin1ClFallbackPrice,
            uint256 startedAtFall,
            uint256 updatedAtFall,
            uint80 answeredInRoundFall
        ) = coin1Fallback.assetToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(roundIdFall, roundId);
        assertEq(startedAtFall, startedAt);
        assertEq(updatedAtFall, updatedAt);
        assertEq(answeredInRoundFall, answeredInRound);

        uint256 estimatedCoin1FallPrice;
        if (coin1Fallback.targetIndex() == 0) {
            estimatedCoin1FallPrice =
                (uint(coin1ClFallbackPrice) * SCALE) /
                uint(coin1Fallback.curvePool().price_oracle());
        } else {
            estimatedCoin1FallPrice =
                (uint(coin1Fallback.curvePool().price_oracle()) *
                    uint(coin1ClFallbackPrice)) /
                SCALE;
        }
        int lpPrice = int(
            ((YearnVaultV2Helper.collateralToAsset(yearn, 1e18) *
                estimatedCoin1FallPrice) / 10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_coin1_Out_of_bounds_MIN_use_coin1_Fallback() public {
        //Set Out of MIN bounds coin1 main price
        _mockCall_Chainlink(
            address(coin1Feed.assetToUsd()),
            0,
            IAggregator(coin1Feed.assetToUsd().aggregator()).minAnswer(),
            0,
            0,
            0
        );

        // Use coin1 fallback data (from coin1 fallback chainlink feed)
        (
            uint80 roundIdFall,
            int256 coin1ClFallbackPrice,
            uint256 startedAtFall,
            uint256 updatedAtFall,
            uint80 answeredInRoundFall
        ) = coin1Fallback.assetToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(roundIdFall, roundId);
        assertEq(startedAtFall, startedAt);
        assertEq(updatedAtFall, updatedAt);
        assertEq(answeredInRoundFall, answeredInRound);

        uint256 estimatedCoin1FallPrice;
        if (coin1Fallback.targetIndex() == 0) {
            estimatedCoin1FallPrice =
                (uint(coin1ClFallbackPrice) * SCALE) /
                uint(coin1Fallback.curvePool().price_oracle());
        } else {
            estimatedCoin1FallPrice =
                (uint(coin1Fallback.curvePool().price_oracle()) *
                    uint(coin1ClFallbackPrice)) /
                SCALE;
        }
        int lpPrice = int(
            ((YearnVaultV2Helper.collateralToAsset(yearn, 1e18) *
                estimatedCoin1FallPrice) / 10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_coin1_use_coin1_fallback() public {
        (
            uint80 clRoundId,
            int256 coin1UsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = coin1Feed.assetToUsd().latestRoundData();

        // Set coin1 STALE
        _mockCall_Chainlink(
            address(coin1Feed.assetToUsd()),
            clRoundId,
            coin1UsdPrice,
            clStartedAt,
            clUpdatedAt - 1 - coin1Feed.assetToUsdHeartbeat(),
            clAnsweredInRound
        );

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        (
            uint80 clRoundId2,
            int256 coin1ClFallbackPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = coin1Fallback.assetToUsd().latestRoundData();

        // When coin1 is stale use coin1 fallback
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);
        uint256 estimatedCoin1FallPrice;
        if (coin1Fallback.targetIndex() == 0) {
            estimatedCoin1FallPrice =
                (uint(coin1ClFallbackPrice) * SCALE) /
                uint(coin1Fallback.curvePool().price_oracle());
        } else {
            estimatedCoin1FallPrice =
                (uint(coin1Fallback.curvePool().price_oracle()) *
                    uint(coin1ClFallbackPrice)) /
                SCALE;
        }
        uint256 calculatedLPUsdPrice = (estimatedCoin1FallPrice *
            YearnVaultV2Helper.collateralToAsset(yearn, 1e18)) / 10 ** 8;

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_coin1FallBack_oracle() public view {
        (
            uint80 roundIdFall,
            int256 coin1ClFallbackPrice,
            uint startedAtFall,
            uint updatedAtFall,
            uint80 answeredInRoundFall
        ) = coin1Fallback.assetToUsd().latestRoundData();
        (
            uint80 roundId,
            int256 coin1FallPrice,
            uint256 startedAt,
            uint256 updateAt,
            uint80 answeredInRound
        ) = coin1Fallback.latestRoundData();
        uint256 estimatedCoin1FallPrice;
        if (coin1Fallback.targetIndex() == 0) {
            estimatedCoin1FallPrice =
                (uint(coin1ClFallbackPrice) * SCALE) /
                uint(coin1Fallback.curvePool().price_oracle());
        } else {
            estimatedCoin1FallPrice =
                (uint(coin1Fallback.curvePool().price_oracle()) *
                    uint(coin1ClFallbackPrice)) /
                SCALE;
        }
        assertEq(uint(coin1FallPrice), estimatedCoin1FallPrice);
        assertEq(roundIdFall, roundId);
        assertEq(startedAtFall, startedAt);
        assertEq(updatedAtFall, updateAt);
        assertEq(answeredInRoundFall, answeredInRound);
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
        ) = coin1Feed.latestRoundData();

        if ((oracleUpdatedAt > 0)) {
            oracleLpToUsdPrice =
                (oracleMinToUsdPrice *
                    int(YearnVaultV2Helper.collateralToAsset(yearn, 1e18))) /
                int(10 ** coin1Feed.decimals());
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
