// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/DolaFraxBPPriceFeed.sol";
import "forge-std/console.sol";

contract DolaFraxBPPriceFeedFork is Test {
    DolaFraxBPPriceFeed feed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 18272690); // FRAX < USDC at this block
        feed = new DolaFraxBPPriceFeed();
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

    function test_use_Frax_when_USDC_gt_Frax() public {
        (
            uint80 clRoundId,
            int256 fraxUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.fraxToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        uint256 estimLPUsdPrice = uint256(
            ((feed.dolaFraxBP().get_virtual_price() * uint256(fraxUsdPrice)) /
                10 ** 8)
        );
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);
        assertEq(uint256(lpUsdPrice), estimLPUsdPrice);
    }

    function test_use_USDC_when_USDC_lt_Frax() public {
        // Set FRAX > than USDC
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        (
            uint80 clRoundId,
            int256 usdcUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.usdcToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        uint256 estimLPUsdPrice = uint256(
            ((feed.dolaFraxBP().get_virtual_price() * uint256(usdcUsdPrice)) /
                10 ** 8)
        );
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);
        assertEq(uint256(lpUsdPrice), estimLPUsdPrice);
    }

    function test_USDC_Out_of_bounds_MAX_use_USDC_Fallback_when_USDC_lt_Frax()
        public
    {
        // Set FRAX > than USDC
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        //Set Out of MAX bounds usdc/USD price
        vm.mockCall(
            address(feed.usdcToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                IAggregator(feed.usdcToUsd().aggregator()).maxAnswer(),
                0,
                0,
                0
            )
        );
        // Use fallback USDC data (from eth/usd chainlink feed)
        (
            uint80 roundIdFall,
            int256 ethToUsdPrice,
            uint256 startedAtFall,
            uint256 updatedAtFall,
            uint80 answeredInRoundFall
        ) = feed.ethToUsd().latestRoundData();

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

        uint256 usdcFallPrice = (uint256(ethToUsdPrice) * 10 ** 18) /
            feed.tricryptoETH().price_oracle(1);
        int lpPrice = int(
            ((feed.dolaFraxBP().get_virtual_price() * usdcFallPrice) / 10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_USDC_Out_of_bounds_MIN_use_USDC_Fallback_when_USDC_lt_Frax()
        public
    {
        // Set FRAX > than USDC
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        //Set Out of MAX bounds usdc/USD price
        vm.mockCall(
            address(feed.usdcToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                IAggregator(feed.usdcToUsd().aggregator()).minAnswer(),
                0,
                0,
                0
            )
        );
        // Use fallback USDC data (from eth/usd chainlink feed)
        (
            uint80 roundIdFall,
            int256 ethToUsdPrice,
            uint256 startedAtFall,
            uint256 updatedAtFall,
            uint80 answeredInRoundFall
        ) = feed.ethToUsd().latestRoundData();

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

        uint256 usdcFallPrice = (uint256(ethToUsdPrice) * 10 ** 18) /
            feed.tricryptoETH().price_oracle(1);
        int lpPrice = int(
            ((feed.dolaFraxBP().get_virtual_price() * usdcFallPrice) / 10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_FRAX_Out_of_bounds_MAX_use_FRAX_Fallback_when_Frax_lt_USDC()
        public
    {
        //Set Out of MAX bounds Frax/USD price
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                IAggregator(feed.fraxToUsd().aggregator()).maxAnswer(),
                0,
                0,
                0
            )
        );
        // Use fallback Frax data (from crvUsd/usd chainlink feed)
        (
            uint80 roundIdFall,
            int256 crvUsdToUsdPrice,
            uint256 startedAtFall,
            uint256 updatedAtFall,
            uint80 answeredInRoundFall
        ) = feed.crvUSDToUsd().latestRoundData();

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

        uint256 fraxFallPrice = (uint256(crvUsdToUsdPrice) * 10 ** 18) /
            feed.crvUSDFrax().ema_price();
        int lpPrice = int(
            ((feed.dolaFraxBP().get_virtual_price() * fraxFallPrice) / 10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_FRAX_Out_of_bounds_MIN_use_FRAX_Fallback_when_Frax_lt_USDC()
        public
    {
        //Set Out of MIN bounds Frax/USD price
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                IAggregator(feed.fraxToUsd().aggregator()).minAnswer(),
                0,
                0,
                0
            )
        );
        // Use fallback Frax data (from crvUsd/usd chainlink feed)
        (
            uint80 roundIdFall,
            int256 crvUsdToUsdPrice,
            uint256 startedAtFall,
            uint256 updatedAtFall,
            uint80 answeredInRoundFall
        ) = feed.crvUSDToUsd().latestRoundData();

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

        uint256 fraxFallPrice = (uint256(crvUsdToUsdPrice) * 10 ** 18) /
            feed.crvUSDFrax().ema_price();
        int lpPrice = int(
            ((feed.dolaFraxBP().get_virtual_price() * fraxFallPrice) / 10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_USDC_Out_of_bounds_MAX_use_Frax_when_USDC_lt_Frax_fallbackWhenOutOfMaxBoundsUSDC()
        public
    {
        // Set FRAX > than USDC
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
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

        uint256 estimatedUSDCPrice = (uint256(ethToUsdPrice) * 10 ** 18) /
            ethUSDCPrice;

        assertEq(uint256(usdcFallback), estimatedUSDCPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_ETH_for_USDC_fallback_When_Out_Of_MIN_Bound_USDC_and_Frax_gt_USDC()
        public
    {
        // Set FRAX > than USDC
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
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
                IAggregator(feed.usdcToUsd().aggregator()).minAnswer(),
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
        uint256 estimatedUsdcFallback = (uint256(ethToUsdPrice) * 10 ** 18) /
            feed.tricryptoETH().price_oracle(1);

        assertEq(uint256(usdcFallback), estimatedUsdcFallback);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_ETH_for_USDC_fallback_When_Out_Of_MAX_Bound_USDC_and_Frax_gt_USDC()
        public
    {
        // Set FRAX > than USDC
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
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
                IAggregator(feed.usdcToUsd().aggregator()).maxAnswer(),
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
        uint256 estimatedUsdcFallback = (uint256(ethToUsdPrice) * 10 ** 18) /
            feed.tricryptoETH().price_oracle(1);

        assertEq(uint256(usdcFallback), estimatedUsdcFallback);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_FRAX_use_Frax_fallback_when_Frax_lt_USDC() public {
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

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        (
            uint80 clRoundId2,
            int256 crvUSDToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = feed.crvUSDToUsd().latestRoundData();

        // When FRAX is stale even if FRAX < USDC, use USDC
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 calculatedLPUsdPrice = (((uint256(crvUSDToUsdPrice) *
            10 ** 18) / feed.crvUSDFrax().ema_price()) *
            feed.dolaFraxBP().get_virtual_price()) / 10 ** 8;

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_FRAX_and_crvUSD_STALE_use_USDC_even_if_Frax_lt_USDC()
        public
    {
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

        // When FRAX is fully stale even if FRAX < USDC, use USDC
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 calculatedLPUsdPrice = (feed.dolaFraxBP().get_virtual_price() *
            uint256(usdcToUsdPrice)) / 10 ** 8;

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_FRAX_and_crvUSD_STALE_and_USDC_out_of_Bounds_use_USDC_fallback_even_if_Frax_lt_USDC()
        public
    {
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
        vm.mockCall(
            address(feed.usdcToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                IAggregator(feed.usdcToUsd().aggregator()).maxAnswer(),
                0,
                0,
                0
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
            int256 ethToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = feed.ethToUsd().latestRoundData();

        // When FRAX is fully stale even if FRAX < USDC and USDC is out of bounds, use USDC fallback
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 usdcFallPrice = (uint256(ethToUsdPrice) * 10 ** 18) /
            feed.tricryptoETH().price_oracle(1);
        uint256 calculatedLPUsdPrice = (feed.dolaFraxBP().get_virtual_price() *
            uint256(usdcFallPrice)) / 10 ** 8;

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_PriceisOutOfBounds() public {
        assertEq(feed.isPriceOutOfBounds(0, feed.ethToUsd()), true);
    }

    function test_fraxToUsdFallBack_oracle() public {
        (
            uint80 roundIdFall,
            int256 crvUsdToUsdPrice,
            uint startedAtFall,
            uint updatedAtFall,
            uint80 answeredInRoundFall
        ) = feed.crvUSDToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 fraxFallPrice,
            uint256 startedAt,
            uint256 updateAt,
            uint80 answeredInRound
        ) = feed.fraxToUsdFallbackOracle();

        assertEq(
            uint(fraxFallPrice),
            (uint(crvUsdToUsdPrice) * 10 ** 18) /
                uint(feed.crvUSDFrax().ema_price())
        );
        assertEq(roundIdFall, roundId);
        assertEq(startedAtFall, startedAt);
        assertEq(updatedAtFall, updateAt);
        assertEq(answeredInRoundFall, answeredInRound);
    }

    function test_usdcToUsdFallBack_oracle() public {
        (
            uint80 clRoundId2,
            int256 ethToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = feed.ethToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 usdcToUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.usdcToUsdFallbackOracle();

        uint256 ethUSDCPrice = feed.tricryptoETH().price_oracle(1);

        uint256 estimatedUSDCPrice = (uint256(ethToUsdPrice) * 10 ** 18) /
            ethUSDCPrice;

        assertEq(uint256(usdcToUsdPrice), estimatedUSDCPrice);
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);
    }

    function test_setEthHeartbeat() public {
        assertEq(feed.ethHeartbeat(), 3600);

        vm.expectRevert(DolaFraxBPPriceFeed.OnlyGov.selector);
        feed.setEthHeartbeat(100);
        assertEq(feed.ethHeartbeat(), 3600);

        vm.prank(feed.gov());
        feed.setEthHeartbeat(100);
        assertEq(feed.ethHeartbeat(), 100);
    }

    function test_setFraxHeartbeat() public {
        assertEq(feed.fraxHeartbeat(), 3600);

        vm.expectRevert(DolaFraxBPPriceFeed.OnlyGov.selector);
        feed.setFraxHeartbeat(100);
        assertEq(feed.fraxHeartbeat(), 3600);

        vm.prank(feed.gov());
        feed.setFraxHeartbeat(100);
        assertEq(feed.fraxHeartbeat(), 100);
    }

    function test_setCrvUSDHeartbeat() public {
        assertEq(feed.crvUSDHeartbeat(), 24 hours);

        vm.expectRevert(DolaFraxBPPriceFeed.OnlyGov.selector);
        feed.setCrvUSDHeartbeat(100);
        assertEq(feed.crvUSDHeartbeat(), 24 hours);

        vm.prank(feed.gov());
        feed.setCrvUSDHeartbeat(100);
        assertEq(feed.crvUSDHeartbeat(), 100);
    }

    function test_setGov() public {
        assertEq(feed.gov(), 0x926dF14a23BE491164dCF93f4c468A50ef659D5B);

        vm.expectRevert(DolaFraxBPPriceFeed.OnlyGov.selector);
        feed.setGov(address(this));
        assertEq(feed.gov(), 0x926dF14a23BE491164dCF93f4c468A50ef659D5B);

        vm.prank(feed.gov());
        feed.setGov(address(this));
        assertEq(feed.gov(), address(this));
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
                int(feed.dolaFraxBP().get_virtual_price() / 10 ** 8);
        } else {
            oracleRoundId = clRoundIdFrax;
            oracleMinToUsdPrice = clFraxToUsdPrice;
            oracleStartedAt = clStartedAtFrax;
            oracleUpdatedAt = clUpdatedAtFrax;
            oracleAnsweredInRound = clAnsweredInRoundFrax;

            oracleLpToUsdPrice =
                (int(feed.dolaFraxBP().get_virtual_price()) *
                    oracleMinToUsdPrice) /
                10 ** 8;
        }
    }
}
