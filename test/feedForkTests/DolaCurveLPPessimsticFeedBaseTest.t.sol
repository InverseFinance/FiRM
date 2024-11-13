// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
//import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {DolaFixedPriceFeed} from "src/feeds/DolaFixedPriceFeed.sol";

abstract contract DolaCurveLPPessimsticFeedBaseTest is Test {
    CurveLPPessimisticFeed feed;
    ChainlinkBasePriceFeed coin1Feed; // main coin1 feed
    DolaFixedPriceFeed dolaFeed; // main coin2 feed
    ChainlinkCurveFeed public coin1Fallback; // coin1 fallback if any

    ICurvePool public curvePool; // Curve Pool for virtual price

    // For Coin1 Chainlink fallback
    IChainlinkFeed public coin1ClFallback;

    //address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    uint256 public constant SCALE = 1e18;

    function init(
        address _coin1Fallback,
        address _coin1Feed,
        address _curvePool
    ) public {
        coin1Fallback = ChainlinkCurveFeed(_coin1Fallback);
        coin1Feed = ChainlinkBasePriceFeed(_coin1Feed);
        dolaFeed = new DolaFixedPriceFeed();
        curvePool = ICurvePool(_curvePool);

        feed = new CurveLPPessimisticFeed(
            address(curvePool),
            address(coin1Feed),
            address(dolaFeed),
            false
        );
    }

    function test_description() public {
        if (address(coin1ClFallback) != address(0)) {
            console.log("coin1ClFallback: ", coin1ClFallback.description());
        }
        console.log("coin1Feed: ", coin1Feed.description());
        console.log("dolaFeed: ", dolaFeed.description());
        console.log("feed: ", feed.description());
    }

    function test_decimals() public {
        assertEq(feed.decimals(), 18);
    }

    function test_latestAnswer() public {
        (, int256 lpUsdPrice, , , ) = feed.latestRoundData();

        assertEq(feed.latestAnswer(), lpUsdPrice);
    }

    function test_latestRoundData() internal {
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
        ) = coin1Feed.latestRoundData();

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        uint256 estimLPUsdPrice = uint256(
            ((feed.curvePool().get_virtual_price() * uint256(coin1UsdPrice)) /
                10 ** dolaFeed.decimals())
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
            address(coin1Feed),
            0,
            1.1 ether,
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
        ) = dolaFeed.latestRoundData();

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        uint256 estimLPUsdPrice = uint256(
            ((feed.curvePool().get_virtual_price() * uint256(coin2UsdPrice)) /
                10 ** dolaFeed.decimals())
        );
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);
        assertEq(uint256(lpUsdPrice), estimLPUsdPrice, "lpUsdPrice");
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

        uint256 coin1UsdFallPrice;
        if (coin1Fallback.targetIndex() == 0) {
            coin1UsdFallPrice = ((uint256(coin1ClFallbackPrice) * SCALE) /
                coin1Fallback.curvePool().price_oracle());
        } else {
            coin1UsdFallPrice = ((uint256(coin1ClFallbackPrice) *
                coin1Fallback.curvePool().price_oracle()) / SCALE);
        }
        int lpPrice = int(
            ((feed.curvePool().get_virtual_price() * coin1UsdFallPrice) / SCALE)
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

        uint256 coin1UsdFallPrice;
        if (coin1Fallback.targetIndex() == 0) {
            coin1UsdFallPrice = ((uint256(coin1ClFallbackPrice) * SCALE) /
                coin1Fallback.curvePool().price_oracle());
        } else {
            coin1UsdFallPrice = ((uint256(coin1ClFallbackPrice) *
                coin1Fallback.curvePool().price_oracle()) / SCALE);
        }
        int lpPrice = int(
            ((feed.curvePool().get_virtual_price() * coin1UsdFallPrice) / SCALE)
        );

        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
        console.log("coin1UsdFallPrice", coin1UsdFallPrice);
        console.log("lpUsdPrice: ", uint(lpUsdPrice));
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
        uint256 coin1UsdFallPrice;
        if (coin1Fallback.targetIndex() == 0) {
            coin1UsdFallPrice = ((uint256(coin1ClFallbackPrice) * SCALE) /
                coin1Fallback.curvePool().price_oracle());
        } else {
            coin1UsdFallPrice = ((uint256(coin1ClFallbackPrice) *
                coin1Fallback.curvePool().price_oracle()) / SCALE);
        }
        uint256 calculatedLPUsdPrice = (coin1UsdFallPrice *
            feed.curvePool().get_virtual_price()) / SCALE;

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
        console.log("coin1UsdFallPrice", coin1UsdFallPrice);
        console.log("lpUsdPrice: ", uint(lpUsdPrice));
    }

    function test_STALE_coin1_and_STALE_coin1_fallback_then_use_coin2_if_coin2_lt_coin1_but_keep_coin1_data()
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
            coin1UsdPrice * 1e11,
            clStartedAt,
            0,
            clAnsweredInRound
        );
        console.log(uint(coin1UsdPrice), "coin1UsdPrice");
        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        (, int256 coin2Price, , , ) = dolaFeed.latestRoundData();
        (, , , uint updatedAtCoin1Fb, ) = coin1Fallback.latestRoundData();
        console.log(updatedAtCoin1Fb, "updateAt coin1 fallback");

        // When coin1 is fully stale even if coin1 < coin2, use coin2
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(updatedAtCoin1Fb, updatedAt);
        assertEq(updatedAt, 0);
        assertEq(clAnsweredInRound, answeredInRound);

        uint256 calculatedLPUsdPrice = (feed.curvePool().get_virtual_price() *
            uint256(coin2Price)) / 10 ** dolaFeed.decimals();

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
            (uint(coin1Fallback.curvePool().price_oracle()) *
                uint(coin1ClFallbackPrice)) / 10 ** 18,
            "not correct"
        );
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

        (
            uint80 coin2RoundId,
            int256 coin2UsdPrice,
            uint coin2StartedAt,
            uint coin2UpdatedAt,
            uint80 coin2AnsweredInRound
        ) = dolaFeed.latestRoundData();

        if ((oracleMinToUsdPrice < coin2UsdPrice) || coin2UsdPrice == 0) {
            oracleLpToUsdPrice =
                (oracleMinToUsdPrice *
                    int(feed.curvePool().get_virtual_price())) /
                int(10 ** coin1Feed.decimals());
        } else {
            oracleMinToUsdPrice = coin2UsdPrice;
            oracleLpToUsdPrice =
                (oracleMinToUsdPrice *
                    (int(feed.curvePool().get_virtual_price()))) /
                int(10 ** dolaFeed.decimals());
        }
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
