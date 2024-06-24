// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/DolaFraxBPPriceFeed.sol";
import "forge-std/console.sol";
import {ChainlinkCurve2CoinsAssetFeed} from "src/feeds/ChainlinkCurve2CoinsAssetFeed.sol";
import {ChainlinkCurveAssetFeed} from "src/feeds/ChainlinkCurveAssetFeed.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";

contract DolaFraxBPPriceFeedFork is Test {
    DolaFraxBPPriceFeed feed;
    ChainlinkCurveAssetFeed usdcFallback;
    ChainlinkCurve2CoinsAssetFeed fraxFallback;
    ChainlinkBasePriceFeed mainUsdcFeed;
    ChainlinkBasePriceFeed mainFraxFeed;
    ChainlinkBasePriceFeed baseCrvUsdToUsd;
    ChainlinkBasePriceFeed baseEthToUsd;

    ICurvePool public constant dolaFraxBP =
        ICurvePool(0xE57180685E3348589E9521aa53Af0BCD497E884d);

    IChainlinkFeed public constant fraxToUsd =
        IChainlinkFeed(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);

    uint256 public fraxHeartbeat = 1 hours;

    IChainlinkFeed public constant usdcToUsd =
        IChainlinkFeed(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    uint256 public usdcHeartbeat = 24 hours;

    // For USDC fallabck
    ICurvePool public constant tricryptoETH =
        ICurvePool(0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B);

    IChainlinkFeed public constant ethToUsd =
        IChainlinkFeed(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    uint256 public ethHeartbeat = 1 hours;
    uint256 public constant ethK = 1;

    // For Frax fallback
    ICurvePool public constant crvUSDFrax =
        ICurvePool(0x0CD6f267b2086bea681E922E19D40512511BE538);

    IChainlinkFeed public constant crvUSDToUsd =
        IChainlinkFeed(0xEEf0C605546958c1f899b6fB336C20671f9cD49F);

    uint256 public crvUSDHeartbeat = 24 hours;

    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 18272690); // FRAX < USDC at this block

        baseEthToUsd = new ChainlinkBasePriceFeed(
            gov,
            address(ethToUsd),
            address(0),
            ethHeartbeat,
            8
        );
        usdcFallback = new ChainlinkCurveAssetFeed(
            address(baseEthToUsd),
            address(tricryptoETH),
            ethK,
            8
        );

        baseCrvUsdToUsd = new ChainlinkBasePriceFeed(
            gov,
            address(crvUSDToUsd),
            address(0),
            crvUSDHeartbeat,
            8
        );
        fraxFallback = new ChainlinkCurve2CoinsAssetFeed(
            address(baseCrvUsdToUsd),
            address(crvUSDFrax),
            8
        );

        mainUsdcFeed = new ChainlinkBasePriceFeed(
            gov,
            address(usdcToUsd),
            address(usdcFallback),
            usdcHeartbeat,
            8
        );

        mainFraxFeed = new ChainlinkBasePriceFeed(
            gov,
            address(fraxToUsd),
            address(fraxFallback),
            fraxHeartbeat,
            8
        );

        feed = new DolaFraxBPPriceFeed(
            address(dolaFraxBP),
            address(mainFraxFeed),
            address(mainUsdcFeed)
        );
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
        ) = mainFraxFeed.latestRoundData();

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
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        (
            uint80 clRoundId,
            int256 usdcUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = mainUsdcFeed.assetToUsd().latestRoundData();

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
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        //Set Out of MAX bounds usdc/USD price
        vm.mockCall(
            address(mainUsdcFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                IAggregator(mainUsdcFeed.assetToUsd().aggregator()).maxAnswer(),
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
        ) = usdcFallback.assetToUsd().latestRoundData();

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
            usdcFallback.curvePool().price_oracle(1);
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
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        //Set Out of MAX bounds usdc/USD price
        vm.mockCall(
            address(mainUsdcFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                IAggregator(mainUsdcFeed.assetToUsd().aggregator()).minAnswer(),
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
        ) = usdcFallback.assetToUsd().latestRoundData();

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
            usdcFallback.curvePool().price_oracle(1);
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
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                IAggregator(mainFraxFeed.assetToUsd().aggregator()).maxAnswer(),
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
        ) = fraxFallback.assetToUsd().latestRoundData();

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
            fraxFallback.curvePool().price_oracle();
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
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                IAggregator(mainFraxFeed.assetToUsd().aggregator()).minAnswer(),
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
        ) = fraxFallback.assetToUsd().latestRoundData();

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
            fraxFallback.curvePool().price_oracle();
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
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = mainUsdcFeed.assetToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 ethToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = usdcFallback.assetToUsd().latestRoundData();

        // Out of MAX bounds USDC/USD price
        vm.mockCall(
            address(mainUsdcFeed.assetToUsd()),
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

        uint256 ethUSDCPrice = usdcFallback.curvePool().price_oracle(1);
        (, int256 usdcFallbackPrice, , , ) = mainUsdcFeed
            .assetToUsdFallback()
            .latestRoundData();

        uint256 estimatedUSDCPrice = (uint256(ethToUsdPrice) * 10 ** 18) /
            ethUSDCPrice;

        assertEq(uint256(usdcFallbackPrice), estimatedUSDCPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_ETH_for_USDC_fallback_When_Out_Of_MIN_Bound_USDC_and_Frax_gt_USDC()
        public
    {
        // Set FRAX > than USDC
        vm.mockCall(
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = mainUsdcFeed.assetToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 ethToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = usdcFallback.assetToUsd().latestRoundData();
        // Out of MIN bounds USDC/USD price
        vm.mockCall(
            address(mainUsdcFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                IAggregator(mainUsdcFeed.assetToUsd().aggregator()).minAnswer(),
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
        );

        // Stale price for eth
        vm.mockCall(
            address(baseEthToUsd.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId2,
                ethToUsdPrice,
                clStartedAt2,
                clUpdatedAt2 - 1 - baseEthToUsd.assetToUsdHeartbeat(),
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

        (, int256 usdcFallbackPrice, , , ) = mainUsdcFeed
            .assetToUsdFallback()
            .latestRoundData();
        uint256 estimatedUsdcFallback = (uint256(ethToUsdPrice) * 10 ** 18) /
            usdcFallback.curvePool().price_oracle(1);

        assertEq(uint256(usdcFallbackPrice), estimatedUsdcFallback);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_ETH_for_USDC_fallback_When_Out_Of_MAX_Bound_USDC_and_Frax_gt_USDC()
        public
    {
        // Set FRAX > than USDC
        vm.mockCall(
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = mainUsdcFeed.assetToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 ethToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = usdcFallback.assetToUsd().latestRoundData();
        // Out of MIN bounds USDC/USD price
        vm.mockCall(
            address(mainUsdcFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                IAggregator(mainUsdcFeed.assetToUsd().aggregator()).maxAnswer(),
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
        );

        // Stale price for eth
        vm.mockCall(
            address(baseEthToUsd.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId2,
                ethToUsdPrice,
                clStartedAt2,
                clUpdatedAt2 - 1 - baseEthToUsd.assetToUsdHeartbeat(),
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

        (, int256 usdcFallbackPrice, , , ) = mainUsdcFeed
            .assetToUsdFallback()
            .latestRoundData();
        uint256 estimatedUsdcFallback = (uint256(ethToUsdPrice) * 10 ** 18) /
            usdcFallback.curvePool().price_oracle(1);

        assertEq(uint256(usdcFallbackPrice), estimatedUsdcFallback);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_FRAX_use_Frax_fallback_when_Frax_lt_USDC() public {
        (
            uint80 clRoundId,
            int256 fraxToUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = mainFraxFeed.assetToUsd().latestRoundData();

        // Set FRAX STALE even if < than USDC
        vm.mockCall(
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                fraxToUsdPrice,
                clStartedAt,
                clUpdatedAt - 1 - baseCrvUsdToUsd.assetToUsdHeartbeat(),
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
        ) = fraxFallback.assetToUsd().latestRoundData();

        // When FRAX is stale even if FRAX < USDC, use USDC
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 calculatedLPUsdPrice = (((uint256(crvUSDToUsdPrice) *
            10 ** 18) / fraxFallback.curvePool().price_oracle()) *
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
        ) = mainFraxFeed.assetToUsd().latestRoundData();

        // Set FRAX STALE even if < than USDC
        vm.mockCall(
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                fraxToUsdPrice,
                clStartedAt,
                clUpdatedAt - 1 - baseCrvUsdToUsd.assetToUsdHeartbeat(),
                clAnsweredInRound
            )
        );
        vm.mockCall(
            address(fraxFallback.assetToUsd()),
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
        ) = mainUsdcFeed.assetToUsd().latestRoundData();

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
        ) = mainFraxFeed.assetToUsd().latestRoundData();

        // Set FRAX STALE even if < than USDC
        vm.mockCall(
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                fraxToUsdPrice,
                clStartedAt,
                clUpdatedAt - 1 - baseCrvUsdToUsd.assetToUsdHeartbeat(),
                clAnsweredInRound
            )
        );
        vm.mockCall(
            address(fraxFallback.assetToUsd()),
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
            address(mainUsdcFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                IAggregator(mainUsdcFeed.assetToUsd().aggregator()).maxAnswer(),
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
        ) = usdcFallback.assetToUsd().latestRoundData();

        // When FRAX is fully stale even if FRAX < USDC and USDC is out of bounds, use USDC fallback
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 usdcFallPrice = (uint256(ethToUsdPrice) * 10 ** 18) /
            usdcFallback.curvePool().price_oracle(1);
        uint256 calculatedLPUsdPrice = (feed.dolaFraxBP().get_virtual_price() *
            uint256(usdcFallPrice)) / 10 ** 8;

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_fraxToUsdFallBack_oracle() public {
        (
            uint80 roundIdFall,
            int256 crvUsdToUsdPrice,
            uint startedAtFall,
            uint updatedAtFall,
            uint80 answeredInRoundFall
        ) = fraxFallback.assetToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 fraxFallPrice,
            uint256 startedAt,
            uint256 updateAt,
            uint80 answeredInRound
        ) = mainFraxFeed.assetToUsdFallback().latestRoundData();

        assertEq(
            uint(fraxFallPrice),
            (uint(crvUsdToUsdPrice) * 10 ** 18) /
                uint(fraxFallback.curvePool().price_oracle())
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
        ) = usdcFallback.assetToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 usdcToUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = mainUsdcFeed.assetToUsdFallback().latestRoundData();

        uint256 ethUSDCPrice = usdcFallback.curvePool().price_oracle(1);

        uint256 estimatedUSDCPrice = (uint256(ethToUsdPrice) * 10 ** 18) /
            ethUSDCPrice;

        assertEq(uint256(usdcToUsdPrice), estimatedUSDCPrice);
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
        ) = mainUsdcFeed.assetToUsd().latestRoundData();

        (
            uint80 clRoundIdFrax,
            int256 clFraxToUsdPrice,
            uint clStartedAtFrax,
            uint clUpdatedAtFrax,
            uint80 clAnsweredInRoundFrax
        ) = mainFraxFeed.assetToUsd().latestRoundData();

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
