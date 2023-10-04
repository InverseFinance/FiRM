// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/TriFraxPoolPriceFeed.sol";
import "forge-std/console.sol";

contract TriFraxPoolPriceFeedFork is Test {
    TriFraxPoolPriceFeed feed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 18272690); // FRAX < USDC at this block
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

    function test_fallbackWhenOutOfMaxBoundsUSDC() public {
        // Set FRAX > than USDC
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                110000000,
                0,
                block.timestamp,
                0
            )
        );

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.usdcToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 ethToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = feed.ethToUsd().latestRoundData();

        // Out of MAX bounds USDC/USD price
        vm.mockCall(
            address(feed.usdcToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                10 ** 12,
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
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

        uint256 ethUSDCPrice = feed.tricryptoETH().price_oracle(1);
        (, int256 usdcFallback, , , ) = feed.usdcToUsdFallbackOracle();

        uint256 estimatedUSDCPrice = uint256(ethToUsdPrice) *10 ** 18 / ethUSDCPrice;

        assertEq(uint256(usdcFallback), estimatedUSDCPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_fallbackWhenOutOfMinBoundsUSDC() public {
        // Set FRAX > than USDC
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                110000000,
                0,
                block.timestamp,
                0
            )
        );

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.usdcToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 ethToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = feed.ethToUsd().latestRoundData();
        // Out of MIN bounds USDC/USD price
        vm.mockCall(
            address(feed.usdcToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                0,
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
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

        uint256 ethUSDCPrice = feed.tricryptoETH().price_oracle(1);
        (, int256 usdcFallback, , , ) = feed.usdcToUsdFallbackOracle();

        uint256 estimatedUSDCPrice = uint256(ethToUsdPrice) * 10 ** 18 / ethUSDCPrice;

        assertEq(uint256(usdcFallback), estimatedUSDCPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_ETH_fallbackWhenOutOfMinBoundsUSDC() public {
        // Set FRAX > than USDC
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                110000000,
                0,
                block.timestamp,
                0
            )
        );

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.usdcToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 ethToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = feed.ethToUsd().latestRoundData();
        // Out of MIN bounds USDC/USD price
        vm.mockCall(
            address(feed.usdcToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                0,
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
        );

        // Stale price for eth
        vm.mockCall(
            address(feed.ethToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId2,
                ethToUsdPrice,
                clStartedAt2,
                clUpdatedAt2 - 1 - feed.ethHeartbeat(),
                clAnsweredInRound2
            )
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

        (, int256 usdcFallback, , , ) = feed.usdcToUsdFallbackOracle();
        uint256 estimatedUsdcFallback = uint256(ethToUsdPrice) * 10 **18 / feed.tricryptoETH().price_oracle(1);

        assertEq(uint256(usdcFallback), estimatedUsdcFallback);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_FRAX_and_crvUSD_STALE_whenFraxLessThanUSDC() public {
       
        (
            uint80 clRoundId,
            int256 fraxToUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.fraxToUsd().latestRoundData();

        // Set FRAX STALE even if < than USDC
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                fraxToUsdPrice,
                clStartedAt,
                clUpdatedAt - 1 - feed.fraxHeartbeat(),
                clAnsweredInRound
            )
        );
        vm.mockCall(
            address(feed.crvUSDToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                fraxToUsdPrice,
                clStartedAt,
                0,
                clAnsweredInRound
            )
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
            int256 usdcToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = feed.usdcToUsd().latestRoundData();

        // When FRAX is stale even if FRAX < USDC, use USDC
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt); 
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 calculatedLPUsdPrice = feed.tricryptoFRAX().get_virtual_price() * uint256(usdcToUsdPrice) / 10 ** 8;

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
