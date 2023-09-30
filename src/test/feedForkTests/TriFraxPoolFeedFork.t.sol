// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/TriFraxPoolPriceFeed.sol";
import "forge-std/console.sol";

contract TriFraxPoolPriceFeedFork is Test {
    TriFraxPoolPriceFeed feed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        feed = new TriFraxPoolPriceFeed();
    }

    function test_decimals() public {
        assertEq(feed.decimals(), 18);
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

    function _calculateOracleLpPrice()
        internal view 
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
        ) = feed.usdcToUsd().latestRoundData();

        (
            uint80 clRoundIdFrax,
            int256 clFraxToUsdPrice,
            uint clStartedAtFrax,
            uint clUpdatedAtFrax,
            uint80 clAnsweredInRoundFrax
        ) = feed.fraxToUsd().latestRoundData();

        if (oracleMinToUsdPrice <= clFraxToUsdPrice) {
            oracleLpToUsdPrice =
                oracleMinToUsdPrice *
                int(feed.tricryptoFRAX().get_virtual_price() / 10 ** 8);
        } else {
            oracleRoundId = clRoundIdFrax;
            oracleMinToUsdPrice = clFraxToUsdPrice;
            oracleStartedAt = clStartedAtFrax;
            oracleUpdatedAt = clUpdatedAtFrax;
            oracleAnsweredInRound = clAnsweredInRoundFrax;

            oracleLpToUsdPrice =
                (int(feed.tricryptoFRAX().get_virtual_price()) *
                    oracleMinToUsdPrice) /
                10 ** 8;
        }
    }
}
