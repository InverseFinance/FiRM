// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
//import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {DolaFixedPriceFeed} from "src/feeds/DolaFixedPriceFeed.sol";

abstract contract DolaCurveLPPessimisticNestedFeedBaseTest is Test {
    CurveLPPessimisticFeed feed;
    ChainlinkBasePriceFeed coin1Feed; // main coin1 feed
    DolaFixedPriceFeed dolaFeed; // main coin2 feed

    ICurvePool public curvePool; // Curve Pool for virtual price

    uint256 public constant SCALE = 1e18;

    function init(address _coin1Feed, address _curvePool) public {
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
        // Set coin1 < than coin2
        _mockCall_Chainlink(
            address(dolaFeed),
            0,
            1e18 * 2,
            0,
            block.timestamp,
            0
        );
        (
            uint80 clRoundId,
            int256 coin1UsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = coin1Feed.latestRoundData();

        console.log("coin1UsdPrice: ", uint(coin1UsdPrice));
        (, int256 coin2Price, , , ) = dolaFeed.latestRoundData();
        console.log("coin2Price: ", uint(coin2Price));
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

    function test_STALE_coin1_still_use_coin1_if_coin1_lt_coin2() public {
        // Set coin1 < than coin2
        _mockCall_Chainlink(
            address(dolaFeed),
            0,
            1e18 * 2,
            0,
            block.timestamp,
            0
        );

        (
            uint80 clRoundId,
            int256 coin1UsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = coin1Feed.latestRoundData();

        // Set coin1 STALE even if < than coin2
        _mockCall_Chainlink(
            address(coin1Feed),
            clRoundId,
            coin1UsdPrice,
            clStartedAt,
            clUpdatedAt - 25 hours,
            clAnsweredInRound
        );

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        // When coin1 is fully stale, if coin1 < coin2, use coin1
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt - 25 hours, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);

        uint256 calculatedLPUsdPrice = (feed.curvePool().get_virtual_price() *
            uint256(coin1UsdPrice)) / 10 ** coin1Feed.decimals();

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_coin1_still_use_coin2_if_coin2_lt_coin1_but_keep_coin1_data()
        public
    {
        (
            uint80 clRoundId,
            int256 coin1UsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = coin1Feed.latestRoundData();

        // Set coin1 STALE and > than coin2
        _mockCall_Chainlink(
            address(coin1Feed),
            clRoundId,
            coin1UsdPrice * 2,
            clStartedAt,
            clUpdatedAt - 25 hours,
            clAnsweredInRound
        );

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        (, int256 coin2Price, , , ) = dolaFeed.latestRoundData();

        // When coin1 is fully stale if coin2 < coin1, use coin2 but keep coin1 data
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt - 25 hours, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);

        uint256 calculatedLPUsdPrice = (feed.curvePool().get_virtual_price() *
            uint256(coin2Price)) / 10 ** dolaFeed.decimals();

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
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
