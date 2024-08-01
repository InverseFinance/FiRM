// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";

abstract contract CurveLPPessimiticFeedBaseTest is Test {
    CurveLPPessimisticFeed feed;
    ChainlinkBasePriceFeed coin1Feed; // main coin1 feed
    ChainlinkBasePriceFeed coin2Feed; // main coin2 feed
    ChainlinkBasePriceFeed baseClFallCoin1; //cl base price feed for coin1 fallback
    ChainlinkBasePriceFeed baseClFallCoin2; // cl base price feed for coin2 fallback
    ChainlinkCurve2CoinsFeed coin1Fallback; // coin1 fallback
    ChainlinkCurveFeed coin2Fallback; // coin2 fallback

    ICurvePool public curvePool; // Curve Pool for virtual price

    // For Coin2 Chainlink fallback
    IChainlinkFeed public coin1ClFallback;

    // For coin2 Chainlink fallback
    IChainlinkFeed public coin2ClFallback;

    //address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    function init(
        address _baseClFallCoin1,
        address _coin1Fallback,
        address _coin1Feed,
        address _baseClFallCoin2,
        address _coin2Fallback,
        address _coin2Feed,
        address _curvePool
    ) public {
        baseClFallCoin1 = ChainlinkBasePriceFeed(_baseClFallCoin1);
        coin1Fallback = ChainlinkCurve2CoinsFeed(_coin1Fallback);
        coin1Feed = ChainlinkBasePriceFeed(_coin1Feed);
        baseClFallCoin2 = ChainlinkBasePriceFeed(_baseClFallCoin2);
        coin2Fallback = ChainlinkCurveFeed(_coin2Fallback);
        coin2Feed = ChainlinkBasePriceFeed(_coin2Feed);
        curvePool = ICurvePool(_curvePool);
        coin1ClFallback = coin1Fallback.assetToUsd();
        coin2ClFallback = coin2Fallback.assetToUsd();

        feed = new CurveLPPessimisticFeed(
            address(curvePool),
            address(coin1Feed),
            address(coin2Feed)
        );
    }

    function test_decimals() public {
        assertEq(feed.decimals(), 18);
    }

    function test_latestAnswer() public {
        (, int256 lpUsdPrice, , , ) = feed.latestRoundData();

        assertEq(feed.latestAnswer(), lpUsdPrice);
    }

    function test_latestRoundData() public {
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

    function test_use_coin1_when_coin2_gt_coin1() public {
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
            ((feed.curvePool().get_virtual_price() * uint256(coin1UsdPrice)) /
                10 ** 8)
        );
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);
        assertEq(uint256(lpUsdPrice), estimLPUsdPrice);
    }

    function test_use_coin2_when_coin2_lt_coin1() public {
        // Set coin1 > than coin2
        _mockCall_Chainlink(
            address(coin1Feed.assetToUsd()),
            0,
            110000000,
            0,
            block.timestamp,
            0
        );

        (
            uint80 clRoundId,
            int256 coin2UsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = coin2Feed.assetToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        uint256 estimLPUsdPrice = uint256(
            ((feed.curvePool().get_virtual_price() * uint256(coin2UsdPrice)) /
                10 ** 8)
        );
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);
        assertEq(uint256(lpUsdPrice), estimLPUsdPrice);
    }

    function test_coin2_Out_of_bounds_MAX_use_coin2_Fallback_when_coin2_lt_coin1()
        public
    {
        // Set coin1 > coin2
        _mockCall_Chainlink(
            address(coin1Feed.assetToUsd()),
            0,
            110000000,
            0,
            block.timestamp,
            0
        );

        //Set Out of MAX bounds coin2 main price
        _mockCall_Chainlink(
            address(coin2Feed.assetToUsd()),
            0,
            IAggregator(coin2Feed.assetToUsd().aggregator()).maxAnswer(),
            0,
            0,
            0
        );

        // Use fallback coin2 data (from coin2 fallback chainlink feed)
        (
            uint80 roundIdFall,
            int256 coin2ClFallbackPrice,
            uint256 startedAtFall,
            uint256 updatedAtFall,
            uint80 answeredInRoundFall
        ) = coin2Fallback.assetToUsd().latestRoundData();

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

        uint256 coin2UsdFallPrice;
        if (coin2Fallback.targetIndex() == 0) {
            coin2UsdFallPrice = ((uint256(coin2ClFallbackPrice) * 10 ** 18) /
                coin2Fallback.curvePool().price_oracle(
                    coin2Fallback.assetOrTargetK()
                ));
        } else {
            coin2UsdFallPrice = ((uint256(coin2ClFallbackPrice) *
                coin2Fallback.curvePool().price_oracle(
                    coin2Fallback.assetOrTargetK()
                )) / 10 ** 18);
        }
        int lpPrice = int(
            ((feed.curvePool().get_virtual_price() * coin2UsdFallPrice) /
                10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_coin2_Out_of_bounds_MIN_use_coin2_Fallback_when_coin2_lt_coin1()
        public
    {
        // Set coin1 > coin2
        _mockCall_Chainlink(
            address(coin1Feed.assetToUsd()),
            0,
            110000000,
            0,
            block.timestamp,
            0
        );

        //Set Out of MAX bounds coin2 main price
        _mockCall_Chainlink(
            address(coin2Feed.assetToUsd()),
            0,
            IAggregator(coin2Feed.assetToUsd().aggregator()).minAnswer(),
            0,
            0,
            0
        );

        // Use fallback coin2 data (from coin2 fallback chainlink feed)
        (
            uint80 roundIdFall,
            int256 coin2ClFallbackPrice,
            uint256 startedAtFall,
            uint256 updatedAtFall,
            uint80 answeredInRoundFall
        ) = coin2Fallback.assetToUsd().latestRoundData();

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

        uint256 coin2UsdFallPrice;
        if (coin2Fallback.targetIndex() == 0) {
            coin2UsdFallPrice = ((uint256(coin2ClFallbackPrice) * 10 ** 18) /
                coin2Fallback.curvePool().price_oracle(
                    coin2Fallback.assetOrTargetK()
                ));
        } else {
            coin2UsdFallPrice = ((uint256(coin2ClFallbackPrice) *
                coin2Fallback.curvePool().price_oracle(
                    coin2Fallback.assetOrTargetK()
                )) / 10 ** 18);
        }

        int lpPrice = int(
            ((feed.curvePool().get_virtual_price() * coin2UsdFallPrice) /
                10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_coin1_Out_of_bounds_MAX_use_coin1_Fallback_when_coin1_lt_coin2()
        public
    {
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

        uint256 coin1FallPrice = (uint256(coin1ClFallbackPrice) * 10 ** 18) /
            coin1Fallback.curvePool().price_oracle();
        int lpPrice = int(
            ((feed.curvePool().get_virtual_price() * coin1FallPrice) / 10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_coin1_Out_of_bounds_MIN_use_coin1_Fallback_when_coin1_lt_coin2()
        public
    {
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

        uint256 coin1FallPrice = (uint256(coin1ClFallbackPrice) * 10 ** 18) /
            coin1Fallback.curvePool().price_oracle();
        int lpPrice = int(
            ((feed.curvePool().get_virtual_price() * coin1FallPrice) / 10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_coin2_Out_of_bounds_MAX_use_coin2_fallback_when_coin2_lt_coin1()
        public
    {
        // Set coin1 > coin2
        _mockCall_Chainlink(
            address(coin1Feed.assetToUsd()),
            0,
            110000000,
            0,
            block.timestamp,
            0
        );

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = coin2Feed.assetToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 coin2ClFallbackPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = coin2Fallback.assetToUsd().latestRoundData();

        // Out of MAX bounds main coin2 price
        _mockCall_Chainlink(
            address(coin2Feed.assetToUsd()),
            clRoundId,
            IAggregator(coin2Feed.assetToUsd().aggregator()).maxAnswer(),
            clStartedAt,
            clUpdatedAt,
            clAnsweredInRound
        );

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 coin2CurveFallPrice = coin2Fallback.curvePool().price_oracle(
            coin2Fallback.assetOrTargetK()
        );
        (, int256 coin2FallPrice, , , ) = coin2Fallback.latestRoundData();

        uint256 estimatedCoin2Price;
        if (coin2Fallback.targetIndex() == 0) {
            estimatedCoin2Price = ((uint256(coin2ClFallbackPrice) * 10 ** 18) /
                coin2CurveFallPrice);
        } else {
            estimatedCoin2Price = ((uint256(coin2ClFallbackPrice) *
                coin2CurveFallPrice) / 10 ** 18);
        }

        assertEq(uint256(coin2FallPrice), estimatedCoin2Price);
        int lpPrice = int(
            ((feed.curvePool().get_virtual_price() * uint(coin2FallPrice)) /
                10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_ClFeed_for_coin2_fallback_When_Out_Of_MIN_Bound_coin2_and_coin1_gt_coin2()
        public
    {
        // Set coin1 > coin2
        _mockCall_Chainlink(
            address(coin1Feed.assetToUsd()),
            0,
            110000000,
            0,
            block.timestamp,
            0
        );

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = coin2Feed.assetToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 coin2ClFallbackPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = coin2Feed.assetToUsd().latestRoundData();

        // Out of MIN bounds main coin2 price
        _mockCall_Chainlink(
            address(coin2Feed.assetToUsd()),
            clRoundId,
            IAggregator(coin2Feed.assetToUsd().aggregator()).minAnswer(),
            clStartedAt,
            clUpdatedAt,
            clAnsweredInRound
        );

        // Stale price for cl fallback coin2
        _mockCall_Chainlink(
            address(baseClFallCoin2.assetToUsd()),
            clRoundId2,
            coin2ClFallbackPrice,
            clStartedAt2,
            clUpdatedAt2 - 1 - baseClFallCoin2.assetToUsdHeartbeat(),
            clAnsweredInRound2
        );

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(0, updatedAt); // This will cause STALE price on the borrow controller
        assertEq(clAnsweredInRound2, answeredInRound);

        (, int256 coin2FallPrice, , , ) = coin2Fallback.latestRoundData();
        uint256 estimatedCoin2Fallback;
        if (coin2Fallback.targetIndex() == 0) {
            estimatedCoin2Fallback = ((uint256(coin2ClFallbackPrice) *
                10 ** 18) /
                coin2Fallback.curvePool().price_oracle(
                    coin2Fallback.assetOrTargetK()
                ));
        } else {
            estimatedCoin2Fallback = ((uint256(coin2ClFallbackPrice) *
                coin2Fallback.curvePool().price_oracle(
                    coin2Fallback.assetOrTargetK()
                )) / 10 ** 18);
        }
        assertEq(uint256(coin2FallPrice), estimatedCoin2Fallback);
        int lpPrice = int(
            ((feed.curvePool().get_virtual_price() * uint(coin2FallPrice)) /
                10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_ClFeed_for_coin2_fallback_When_Out_Of_MAX_Bound_coin2_and_coin1_gt_coin2()
        public
    {
        // Set coin1 > coin2
        _mockCall_Chainlink(
            address(coin1Feed.assetToUsd()),
            0,
            110000000,
            0,
            block.timestamp,
            0
        );

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = coin2Feed.assetToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 coin2ClFallbackPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = coin2Fallback.assetToUsd().latestRoundData();

        // Out of MIN bounds main coin2 price
        _mockCall_Chainlink(
            address(coin2Feed.assetToUsd()),
            clRoundId,
            IAggregator(coin2Feed.assetToUsd().aggregator()).maxAnswer(),
            clStartedAt,
            clUpdatedAt,
            clAnsweredInRound
        );

        // Stale price for cl fallback coin2
        _mockCall_Chainlink(
            address(baseClFallCoin2.assetToUsd()),
            clRoundId2,
            coin2ClFallbackPrice,
            clStartedAt2,
            clUpdatedAt2 - 1 - baseClFallCoin2.assetToUsdHeartbeat(),
            clAnsweredInRound2
        );

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(0, updatedAt); // This will cause STALE price on the borrow controller
        assertEq(clAnsweredInRound2, answeredInRound);

        (, int256 coin2FallPrice, , , ) = coin2Fallback.latestRoundData();
        uint256 estimatedCoin2Fallback;
        if (coin2Fallback.targetIndex() == 0) {
            estimatedCoin2Fallback = ((uint256(coin2ClFallbackPrice) *
                10 ** 18) /
                coin2Fallback.curvePool().price_oracle(
                    coin2Fallback.assetOrTargetK()
                ));
        } else {
            estimatedCoin2Fallback = ((uint256(coin2ClFallbackPrice) *
                coin2Fallback.curvePool().price_oracle(
                    coin2Fallback.assetOrTargetK()
                )) / 10 ** 18);
        }

        assertEq(uint256(coin2FallPrice), estimatedCoin2Fallback);
        int lpPrice = int(
            ((feed.curvePool().get_virtual_price() * uint(coin2FallPrice)) /
                10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_coin1_use_coin1_fallback_when_coin1_lt_coin2() public {
        (
            uint80 clRoundId,
            int256 coin1UsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = coin1Feed.assetToUsd().latestRoundData();

        // Set coin1 STALE even if < than coin2
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

        // When coin1 is stale if coin1 < coin2, use coin1 fallback
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 calculatedLPUsdPrice = (((uint256(coin1ClFallbackPrice) *
            10 ** 18) / coin1Fallback.curvePool().price_oracle()) *
            feed.curvePool().get_virtual_price()) / 10 ** 8;

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_coin1_and_STALE_coin1_fallback_then_use_coin2_even_if_coin1_lt_coin2()
        public
    {
        (
            uint80 clRoundId,
            int256 coin1UsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = coin1Feed.assetToUsd().latestRoundData();

        // Set coin1 STALE even if < than coin2
        _mockCall_Chainlink(
            address(coin1Feed.assetToUsd()),
            clRoundId,
            coin1UsdPrice,
            clStartedAt,
            clUpdatedAt - 1 - coin1Feed.assetToUsdHeartbeat(),
            clAnsweredInRound
        );
        // Set coin1 fallback STALE even if < than coin2
        _mockCall_Chainlink(
            address(coin1Fallback.assetToUsd()),
            clRoundId,
            coin1UsdPrice,
            clStartedAt,
            0,
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
            int256 coin2ClFallbackPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = coin2Feed.assetToUsd().latestRoundData();

        // When coin1 is fully stale even if coin1 < coin2, use coin2
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 calculatedLPUsdPrice = (feed.curvePool().get_virtual_price() *
            uint256(coin2ClFallbackPrice)) / 10 ** 8;

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_coin1_and_STALE_coin1_fallabck_and_coin2_out_of_Bounds_use_coin2_fallback_even_if_coin1_lt_coin2()
        public
    {
        (
            uint80 clRoundId,
            int256 coin1UsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = coin1Feed.assetToUsd().latestRoundData();

        // Set coin1 STALE even if < than coin2
        _mockCall_Chainlink(
            address(coin1Feed.assetToUsd()),
            clRoundId,
            coin1UsdPrice,
            clStartedAt,
            clUpdatedAt - 1 - coin1Feed.assetToUsdHeartbeat(),
            clAnsweredInRound
        );

        // Set coin1 fallback STALE even if < than coin2
        _mockCall_Chainlink(
            address(coin1Fallback.assetToUsd()),
            clRoundId,
            coin1UsdPrice,
            clStartedAt,
            0,
            clAnsweredInRound
        );

        // Set coin2 STALE
        _mockCall_Chainlink(
            address(coin2Feed.assetToUsd()),
            0,
            IAggregator(coin2Feed.assetToUsd().aggregator()).maxAnswer(),
            0,
            0,
            0
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
            int256 coin2ClFallbackPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = coin2Fallback.assetToUsd().latestRoundData();

        // When coin1 is fully stale even if coin1 < coin2 and coin2 is out of bounds, use coin2 fallback
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 estimatedCoin2Fallback;
        if (coin2Fallback.targetIndex() == 0) {
            estimatedCoin2Fallback = ((uint256(coin2ClFallbackPrice) *
                10 ** 18) /
                coin2Fallback.curvePool().price_oracle(
                    coin2Fallback.assetOrTargetK()
                ));
        } else {
            estimatedCoin2Fallback = ((uint256(coin2ClFallbackPrice) *
                coin2Fallback.curvePool().price_oracle(
                    coin2Fallback.assetOrTargetK()
                )) / 10 ** 18);
        }
        uint256 calculatedLPUsdPrice = (feed.curvePool().get_virtual_price() *
            uint256(estimatedCoin2Fallback)) / 10 ** 8;

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_coin1FallBack_oracle() public {
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

        assertEq(
            uint(coin1FallPrice),
            (uint(coin1ClFallbackPrice) * 10 ** 18) /
                uint(coin1Fallback.curvePool().price_oracle())
        );
        assertEq(roundIdFall, roundId);
        assertEq(startedAtFall, startedAt);
        assertEq(updatedAtFall, updateAt);
        assertEq(answeredInRoundFall, answeredInRound);
    }

    function test_coin2FallBack_oracle() public {
        (
            uint80 clRoundId2,
            int256 coin2ClFallbackPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = coin2Fallback.assetToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 coin2FallPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = coin2Fallback.latestRoundData();

        uint256 coin2CurveFallback = coin2Fallback.curvePool().price_oracle(
            coin2Fallback.assetOrTargetK()
        );
        uint256 estCoin2Fallback;
        if (coin2Fallback.targetIndex() == 0) {
            estCoin2Fallback = ((uint256(coin2ClFallbackPrice) * 10 ** 18) /
                coin2CurveFallback);
        } else {
            estCoin2Fallback = ((uint256(coin2ClFallbackPrice) *
                coin2CurveFallback) / 10 ** 18);
        }

        assertEq(uint256(coin2FallPrice), estCoin2Fallback);
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);
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

        (
            uint80 coin2RoundId,
            int256 coin2UsdPrice,
            uint coin2StartedAt,
            uint coin2UpdatedAt,
            uint80 coin2AnsweredInRound
        ) = coin2Feed.latestRoundData();

        if (
            (oracleMinToUsdPrice < coin2UsdPrice && oracleUpdatedAt > 0) ||
            coin2UsdPrice == 0
        ) {
            oracleLpToUsdPrice =
                (oracleMinToUsdPrice *
                    int(feed.curvePool().get_virtual_price())) /
                int(10 ** coin1Feed.decimals());
        } else {
            oracleRoundId = coin2RoundId;
            oracleMinToUsdPrice = coin2UsdPrice;
            oracleStartedAt = coin2StartedAt;
            oracleUpdatedAt = coin2UpdatedAt;
            oracleAnsweredInRound = coin2AnsweredInRound;

            oracleLpToUsdPrice =
                (oracleMinToUsdPrice *
                    (int(feed.curvePool().get_virtual_price()))) /
                int(10 ** coin2Feed.decimals());
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
