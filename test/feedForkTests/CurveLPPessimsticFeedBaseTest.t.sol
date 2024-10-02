// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
//import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";

abstract contract CurveLPPessimiticFeedBaseTest is Test {
    CurveLPPessimisticFeed feed;
    ChainlinkBasePriceFeed coin1Feed; // main coin1 feed
    ChainlinkBasePriceFeed coin2Feed; // main coin2 feed
    ChainlinkBasePriceFeed baseClFallCoin1; //cl base price feed for coin1 fallback
    ChainlinkBasePriceFeed baseClFallCoin2; // cl base price feed for coin2 fallback
    ChainlinkCurveFeed coin1Fallback; // coin1 fallback
    ChainlinkCurveFeed coin2Fallback; // coin2 fallback

    ICurvePool public curvePool; // Curve Pool for virtual price

    // For Coin2 Chainlink fallback
    IChainlinkFeed public coin1ClFallback;

    // For coin2 Chainlink fallback
    IChainlinkFeed public coin2ClFallback;

    //address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    uint256 public constant SCALE = 1e18;

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
        coin1Fallback = ChainlinkCurveFeed(_coin1Fallback);
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
        // console.log("feed :", feed.description());
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

    function test_use_coin1_when_coin2_gt_coin1_but_use_updateAtCoin2_if_lower()
        public
    {
        (
            uint80 clRoundId,
            int256 coin1UsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = coin1Feed.assetToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 coin2UsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = coin2Feed.assetToUsd().latestRoundData();
        assertGt(clUpdatedAt, clUpdatedAt2);

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        // Coin2 updateAt is lower so it returns coin2 data but using lower price (coin1)
        uint256 estimLPUsdPrice = uint256(
            ((feed.curvePool().get_virtual_price() * uint256(coin1UsdPrice)) /
                10 ** 8)
        );

        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);
        assertEq(uint256(lpUsdPrice), estimLPUsdPrice, "lp price");
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
                10 ** coin2Feed.assetToUsd().decimals())
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
                10 ** 18)
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
                10 ** 18)
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

        // Use coin1 fallback price (from coin1 fallback chainlink feed)
        (, int256 coin1ClFallbackPrice, , , ) = coin1Fallback
            .assetToUsd()
            .latestRoundData();
        // coin2 updateAt is lower so use coin2 data but using lower price (coin1)
        (
            uint80 roundId2,
            ,
            uint startedAt2,
            uint updatedAt2,
            uint80 answeredInRound2
        ) = coin2Feed.latestRoundData();
        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(roundId2, roundId);
        assertEq(startedAt2, startedAt);
        assertEq(updatedAt2, updatedAt);
        assertEq(answeredInRound2, answeredInRound);

        uint256 coin1UsdFallPrice;
        if (coin1Fallback.targetIndex() == 0) {
            coin1UsdFallPrice = ((uint256(coin1ClFallbackPrice) * 10 ** 18) /
                coin1Fallback.curvePool().price_oracle(
                    coin1Fallback.assetOrTargetK()
                ));
        } else {
            coin1UsdFallPrice = ((uint256(coin1ClFallbackPrice) *
                coin1Fallback.curvePool().price_oracle(
                    coin1Fallback.assetOrTargetK()
                )) / 10 ** 18);
        }
        int lpPrice = int(
            ((feed.curvePool().get_virtual_price() * coin1UsdFallPrice) /
                10 ** 18)
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

        // Use coin1 fallback price (from coin1 fallback chainlink feed)
        (, int256 coin1ClFallbackPrice, , , ) = coin1Fallback
            .assetToUsd()
            .latestRoundData();

        // coin2 updateAt is lower so use coin2 data but using lower price (coin1)
        (
            uint80 roundId2,
            ,
            uint startedAt2,
            uint updatedAt2,
            uint80 answeredInRound2
        ) = coin2Feed.latestRoundData();

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(roundId2, roundId);
        assertEq(startedAt2, startedAt);
        assertEq(updatedAt2, updatedAt);
        assertEq(answeredInRound2, answeredInRound);

        uint256 coin1UsdFallPrice;
        if (coin1Fallback.targetIndex() == 0) {
            coin1UsdFallPrice = ((uint256(coin1ClFallbackPrice) * 10 ** 18) /
                coin1Fallback.curvePool().price_oracle(
                    coin1Fallback.assetOrTargetK()
                ));
        } else {
            coin1UsdFallPrice = ((uint256(coin1ClFallbackPrice) *
                coin1Fallback.curvePool().price_oracle(
                    coin1Fallback.assetOrTargetK()
                )) / 10 ** 18);
        }
        int lpPrice = int(
            ((feed.curvePool().get_virtual_price() * coin1UsdFallPrice) /
                10 ** 18)
        );

        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
        console.log("coin1UsdFallPrice", coin1UsdFallPrice);
        console.log("lpUsdPrice: ", uint(lpUsdPrice));
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
                10 ** 18)
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
        console.log(uint256(coin2FallPrice), "price coin2 fallback");
        console.log(uint256(coin2ClFallbackPrice), "price coin2 cl fallback");
        uint256 estimatedCoin2Fallback;
        if (coin2Fallback.targetIndex() == 0) {
            estimatedCoin2Fallback = ((uint256(coin2ClFallbackPrice) *
                10 ** 28) /
                coin2Fallback.curvePool().price_oracle(
                    coin2Fallback.assetOrTargetK()
                ));
        } else {
            estimatedCoin2Fallback = ((uint256(coin2ClFallbackPrice) *
                coin2Fallback.curvePool().price_oracle(
                    coin2Fallback.assetOrTargetK()
                )) / 10 ** 8);
        }
        assertEq(uint256(coin2FallPrice), estimatedCoin2Fallback, "fallback");
        int lpPrice = int(
            ((feed.curvePool().get_virtual_price() * uint(coin2FallPrice)) /
                10 ** 18)
        );
        assertEq(
            uint256(lpUsdPrice),
            uint256(lpPrice),
            "calculated price not correct"
        );
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()), "latest");
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
        console.log(uint(coin2ClFallbackPrice), "test");
        (, int256 coin2FallPriceBefore, , , ) = coin2Fallback.latestRoundData();
        console.log(uint(coin2FallPriceBefore), "before mock");
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
            coin2ClFallbackPrice / 10 ** 10,
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
        assertEq(0, updatedAt, "stale"); // This will cause STALE price on the borrow controller
        assertEq(clAnsweredInRound2, answeredInRound);

        (, int256 coin2FallPrice, , , ) = coin2Fallback.latestRoundData();
        uint256 estimatedCoin2Fallback;
        console.log(uint(coin2FallPrice), "coin2FallPrice");
        console.log(uint256(coin2ClFallbackPrice), "coin2ClFallbackPrice");
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
                10 ** 18)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice), "lpPrice");
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

        (, int256 coin1ClFallbackPrice, , , ) = coin1Fallback
            .assetToUsd()
            .latestRoundData();

        (
            uint80 roundId2,
            ,
            uint startedAt2,
            uint updatedAt2,
            uint80 answeredInRound2
        ) = coin2Feed.assetToUsd().latestRoundData();

        // When coin1 is stale if coin1 < coin2, use coin1 fallback price but use lowest updateAt (in this case from coin2)
        assertEq(roundId2, roundId);
        assertEq(startedAt2, startedAt);
        assertEq(updatedAt2, updatedAt);
        assertEq(answeredInRound2, answeredInRound);

        console.log(uint(coin1ClFallbackPrice), "lp Price");
        uint256 coin1UsdFallPrice;
        if (coin1Fallback.targetIndex() == 0) {
            coin1UsdFallPrice = ((uint256(coin1ClFallbackPrice) * 10 ** 18) /
                coin1Fallback.curvePool().price_oracle(
                    coin1Fallback.assetOrTargetK()
                ));
        } else {
            coin1UsdFallPrice = ((uint256(coin1ClFallbackPrice) *
                coin1Fallback.curvePool().price_oracle(
                    coin1Fallback.assetOrTargetK()
                )) / 10 ** 18);
        }
        uint256 calculatedLPUsdPrice = (coin1UsdFallPrice *
            feed.curvePool().get_virtual_price()) / 10 ** 18;

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice, "lp Price");
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
        console.log("coin1UsdFallPrice", coin1UsdFallPrice);
        console.log("lpUsdPrice: ", uint(lpUsdPrice));
    }

    function test_STALE_coin1_and_STALE_coin1_fallback_then_use_coin2_but_coin1_updateAt_when_coin2_lt_coin1()
        public
    {
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
        // Set coin1 fallback STALE and coin2 < coin1
        _mockCall_Chainlink(
            address(coin1Fallback.assetToUsd()),
            clRoundId,
            1.1 ether,
            clStartedAt,
            clUpdatedAt -
                10 -
                IChainlinkBasePriceFeed(address(coin1Fallback.assetToUsd()))
                    .assetToUsdHeartbeat(),
            clAnsweredInRound
        );

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        console.log(uint(lpUsdPrice), "lpUsdPrice");
        (
            uint80 clRoundIdFb,
            ,
            uint clStartedAtFb,
            uint clUpdatedAtFb,
            uint80 clAnsweredInRoundFb
        ) = coin1Feed.assetToUsdFallback().latestRoundData();

        (, int256 coin2UsdPrice, , , ) = coin2Feed.latestRoundData();
        console.log(uint(coin2UsdPrice), "coin2UsdPrice");
        // When coin1 is fully stale even if coin1 < coin2, use coin2
        assertEq(clRoundIdFb, roundId);
        assertEq(clStartedAtFb, startedAt);
        assertEq(
            clUpdatedAt -
                10 -
                IChainlinkBasePriceFeed(address(coin1Fallback.assetToUsd()))
                    .assetToUsdHeartbeat(),
            updatedAt
        ); // update At is from coin1 fallback
        assertGt(clUpdatedAtFb, 0); // but not used bc updateAt from coin1 is lower
        assertEq(clAnsweredInRoundFb, answeredInRound);

        uint256 calculatedLPUsdPrice = (feed.curvePool().get_virtual_price() *
            uint256(coin2UsdPrice)) / 10 ** 18;

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice, "lp Price");
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_coin1_and_STALE_coin1_fallback_and_coin2_out_of_Bounds_use_coin1_fallback_when_coin1_lt_coin2()
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
            uint80 clRoundId1Fallback,
            int256 coin1ClFallbackPrice,
            uint clStartedAt1Fallback,
            uint clUpdatedAt1Fallback,
            uint80 clAnsweredInRoundFallback
        ) = coin1Fallback.assetToUsd().latestRoundData();

        // When coin1 is fully stale even if coin1 < coin2 and coin2 is out of bounds, use coin2 fallback but return STALE
        assertEq(clRoundId1Fallback, roundId);
        assertEq(clStartedAt1Fallback, startedAt);
        assertEq(0, updatedAt);
        assertEq(clAnsweredInRoundFallback, answeredInRound);

        uint256 estimatedCoin1Fallback;
        if (coin1Fallback.targetIndex() == 0) {
            estimatedCoin1Fallback = ((uint256(coin1ClFallbackPrice) *
                10 ** 18) /
                coin1Fallback.curvePool().price_oracle(
                    coin1Fallback.assetOrTargetK()
                ));
        } else {
            estimatedCoin1Fallback = ((uint256(coin1ClFallbackPrice) *
                coin1Fallback.curvePool().price_oracle(
                    coin1Fallback.assetOrTargetK()
                )) / 10 ** 18);
        }

        uint256 calculatedLPUsdPrice = (feed.curvePool().get_virtual_price() *
            uint256(estimatedCoin1Fallback)) / 10 ** 18;

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
                uint(
                    coin1Fallback.curvePool().price_oracle(
                        coin1Fallback.assetOrTargetK()
                    )
                )
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

        if ((oracleMinToUsdPrice < coin2UsdPrice) || coin2UsdPrice == 0) {
            oracleLpToUsdPrice =
                (oracleMinToUsdPrice *
                    int(feed.curvePool().get_virtual_price())) /
                int(10 ** coin1Feed.decimals());
        } else {
            oracleLpToUsdPrice =
                (oracleMinToUsdPrice *
                    (int(feed.curvePool().get_virtual_price()))) /
                int(10 ** coin2Feed.decimals());
        }
        // If coin2UpdatedAt is lower than coin1UpdatedAt, use coin2 data but use the lowest price (coin1 or coin2)
        if (coin2UpdatedAt < oracleUpdatedAt) {
            oracleRoundId = coin2RoundId;
            oracleStartedAt = coin2StartedAt;
            oracleUpdatedAt = coin2UpdatedAt;
            oracleAnsweredInRound = coin2AnsweredInRound;
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
