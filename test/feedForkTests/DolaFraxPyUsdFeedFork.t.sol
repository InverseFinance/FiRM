// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/DolaFraxPyUsdPriceFeed.sol";
import {console} from "forge-std/console.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveTargetFeed} from "src/feeds/ChainlinkCurveTargetFeed.sol";
import {ChainlinkCurve2CoinsAssetFeed} from "src/feeds/ChainlinkCurve2CoinsAssetFeed.sol";

contract DolaFraxPyUsdPriceFeedFork is Test {
    DolaFraxPyUsdPriceFeed feed;
    ChainlinkBasePriceFeed mainFraxFeed;
    ChainlinkBasePriceFeed mainPyUSDFeed;
    ChainlinkBasePriceFeed baseCrvUsdToUsd;
    ChainlinkBasePriceFeed baseUsdcToUsd;
    ChainlinkCurveTargetFeed pyUSDFallback;
    ChainlinkCurve2CoinsAssetFeed fraxFallback;

    ICurvePool public constant dolaPyUSDFrax =
        ICurvePool(0xef484de8C07B6e2d732A92B5F78e81B38f99f95E);

    IChainlinkFeed public constant pyUsdToUsd =
        IChainlinkFeed(0x8f1dF6D7F2db73eECE86a18b4381F4707b918FB1);

    IChainlinkFeed public constant fraxToUsd =
        IChainlinkFeed(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);

    uint256 public fraxHeartbeat = 1 hours;
    uint256 public pyUSDHeartbeat = 24 hours;

    // For Frax fallback
    ICurvePool public constant crvUSDFrax =
        ICurvePool(0x0CD6f267b2086bea681E922E19D40512511BE538);

    IChainlinkFeed public constant crvUSDToUsd =
        IChainlinkFeed(0xEEf0C605546958c1f899b6fB336C20671f9cD49F);
    uint256 public crvUSDHeartbeat = 24 hours;

    // For pyUSD fallback
    ICurvePool public constant pyUsdUsdc =
        ICurvePool(0x383E6b4437b59fff47B619CBA855CA29342A8559);
    uint256 public constant targetKPyUsd = 0;

    IChainlinkFeed public constant usdcToUsd =
        IChainlinkFeed(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    uint256 public usdcHeartbeat = 24 hours;

    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20060490); // FRAX < pyUSD at this block
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

        baseUsdcToUsd = new ChainlinkBasePriceFeed(
            gov,
            address(usdcToUsd),
            address(0),
            usdcHeartbeat,
            8
        );

        pyUSDFallback = new ChainlinkCurveTargetFeed(
            address(baseUsdcToUsd),
            address(pyUsdUsdc),
            targetKPyUsd,
            8
        );

        mainFraxFeed = new ChainlinkBasePriceFeed(
            gov,
            address(fraxToUsd),
            address(fraxFallback),
            fraxHeartbeat,
            8
        );

        mainPyUSDFeed = new ChainlinkBasePriceFeed(
            gov,
            address(pyUsdToUsd),
            address(pyUSDFallback),
            pyUSDHeartbeat,
            8
        );
        feed = new DolaFraxPyUsdPriceFeed(
            address(dolaPyUSDFrax),
            address(mainFraxFeed),
            address(mainPyUSDFeed)
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

    function test_use_Frax_when_PyUSD_gt_Frax() public {
        (
            uint80 clRoundId,
            int256 fraxUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = mainFraxFeed.assetToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        uint256 estimLPUsdPrice = uint256(
            ((feed.dolaPyUSDFrax().get_virtual_price() *
                uint256(fraxUsdPrice)) / 10 ** 8)
        );
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);
        assertEq(uint256(lpUsdPrice), estimLPUsdPrice);
    }

    function test_use_PyUSD_when_PyUSD_lt_Frax() public {
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
        ) = mainPyUSDFeed.assetToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        uint256 estimLPUsdPrice = uint256(
            ((feed.dolaPyUSDFrax().get_virtual_price() *
                uint256(usdcUsdPrice)) / 10 ** 8)
        );
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);
        assertEq(uint256(lpUsdPrice), estimLPUsdPrice);
    }

    function test_PyUSD_Out_of_bounds_MAX_use_PyUSD_Fallback_when_PyUSD_lt_Frax()
        public
    {
        // Set FRAX > than pyUSD
        vm.mockCall(
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        //Set Out of MAX bounds pyUSD/USD price
        vm.mockCall(
            address(mainPyUSDFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                IAggregator(mainPyUSDFeed.assetToUsd().aggregator())
                    .maxAnswer(),
                0,
                0,
                0
            )
        );
        // Use fallback USDC data (from usdc/usd chainlink feed)
        (
            uint80 roundIdFall,
            int256 usdcToUsdPrice,
            uint256 startedAtFall,
            uint256 updatedAtFall,
            uint80 answeredInRoundFall
        ) = pyUSDFallback.assetToUsd().latestRoundData();

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

        uint256 pyUsdFallPrice = ((uint256(usdcToUsdPrice) *
            pyUSDFallback.curvePool().price_oracle(0)) / 10 ** 18);
        int lpPrice = int(
            ((feed.dolaPyUSDFrax().get_virtual_price() * pyUsdFallPrice) /
                10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_PyUSD_Out_of_bounds_MIN_use_PyUSD_Fallback_when_PyUSD_lt_Frax()
        public
    {
        // Set FRAX > than pyUSD
        vm.mockCall(
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        //Set Out of MAX bounds pyUSD/USD price
        vm.mockCall(
            address(mainPyUSDFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                IAggregator(mainPyUSDFeed.assetToUsd().aggregator())
                    .minAnswer(),
                0,
                0,
                0
            )
        );
        // Use fallback USDC data (from usdc/usd chainlink feed)
        (
            uint80 roundIdFall,
            int256 usdcToUsdPrice,
            uint256 startedAtFall,
            uint256 updatedAtFall,
            uint80 answeredInRoundFall
        ) = pyUSDFallback.assetToUsd().latestRoundData();

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

        uint256 pyUsdFallPrice = ((uint256(usdcToUsdPrice) *
            pyUSDFallback.curvePool().price_oracle(0)) / 10 ** 18);
        int lpPrice = int(
            ((feed.dolaPyUSDFrax().get_virtual_price() * pyUsdFallPrice) /
                10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_FRAX_Out_of_bounds_MAX_use_FRAX_Fallback_when_Frax_lt_pyUSD()
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
            ((feed.dolaPyUSDFrax().get_virtual_price() * fraxFallPrice) /
                10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_FRAX_Out_of_bounds_MIN_use_FRAX_Fallback_when_Frax_lt_pyUSD()
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
            ((feed.dolaPyUSDFrax().get_virtual_price() * fraxFallPrice) /
                10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_PyUSD_Out_of_bounds_MAX_use_pyUSD_fallback_when_PyUSD_lt_Frax()
        public
    {
        // Set FRAX > than pyUSD
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
        ) = mainPyUSDFeed.assetToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 usdcToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = pyUSDFallback.assetToUsd().latestRoundData();

        // Out of MAX bounds pyUSD/USD price
        vm.mockCall(
            address(mainPyUSDFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                IAggregator(mainPyUSDFeed.assetToUsd().aggregator())
                    .maxAnswer(),
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

        uint256 pyUsdToUsdcPrice = pyUSDFallback.curvePool().price_oracle(0);
        (, int256 pyUsdFallback, , , ) = pyUSDFallback.latestRoundData();

        uint256 estimatedPyUsdPrice = ((uint256(usdcToUsdPrice) *
            pyUsdToUsdcPrice) / 10 ** 18);

        assertEq(uint256(pyUsdFallback), estimatedPyUsdPrice);
        int lpPrice = int(
            ((feed.dolaPyUSDFrax().get_virtual_price() * uint(pyUsdFallback)) /
                10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_USDC_for_pyUSD_fallback_When_Out_Of_MIN_Bound_pyUSD_and_Frax_gt_pyUSD()
        public
    {
        // Set FRAX > than pyUSD
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
        ) = mainPyUSDFeed.assetToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 usdcToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = mainPyUSDFeed.assetToUsd().latestRoundData();

        // Out of MIN bounds pyUSD/USD price
        vm.mockCall(
            address(mainPyUSDFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                IAggregator(mainPyUSDFeed.assetToUsd().aggregator())
                    .minAnswer(),
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
        );

        // Stale price for USDC
        vm.mockCall(
            address(baseUsdcToUsd.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId2,
                usdcToUsdPrice,
                clStartedAt2,
                clUpdatedAt2 - 1 - baseUsdcToUsd.assetToUsdHeartbeat(),
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

        (, int256 pyUsdFallback, , , ) = pyUSDFallback.latestRoundData();
        uint256 estimatedPyUsdFallback = ((uint256(usdcToUsdPrice) *
            pyUSDFallback.curvePool().price_oracle(0)) / 10 ** 18);

        assertEq(uint256(pyUsdFallback), estimatedPyUsdFallback);
        int lpPrice = int(
            ((feed.dolaPyUSDFrax().get_virtual_price() * uint(pyUsdFallback)) /
                10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_USDC_for_pyUSD_fallback_When_Out_Of_MAX_Bound_pyUSD_and_Frax_gt_pyUSD()
        public
    {
        // Set FRAX > than pyUSD
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
        ) = mainPyUSDFeed.assetToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 usdcToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = pyUSDFallback.assetToUsd().latestRoundData();
        // Out of MIN bounds pyUSD/USD price
        vm.mockCall(
            address(mainPyUSDFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                IAggregator(mainPyUSDFeed.assetToUsd().aggregator())
                    .maxAnswer(),
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
        );

        // Stale price for usdc
        vm.mockCall(
            address(baseUsdcToUsd.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId2,
                usdcToUsdPrice,
                clStartedAt2,
                clUpdatedAt2 - 1 - baseUsdcToUsd.assetToUsdHeartbeat(),
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

        (, int256 pyUsdFallback, , , ) = pyUSDFallback.latestRoundData();
        uint256 estimatedPyUsdFallback = ((uint256(usdcToUsdPrice) *
            pyUSDFallback.curvePool().price_oracle(0)) / 10 ** 18);

        assertEq(uint256(pyUsdFallback), estimatedPyUsdFallback);
        int lpPrice = int(
            ((feed.dolaPyUSDFrax().get_virtual_price() * uint(pyUsdFallback)) /
                10 ** 8)
        );
        assertEq(uint256(lpUsdPrice), uint256(lpPrice));
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_FRAX_use_Frax_fallback_when_Frax_lt_pyUSD() public {
        (
            uint80 clRoundId,
            int256 fraxToUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = mainFraxFeed.assetToUsd().latestRoundData();

        // Set FRAX STALE even if < than pyUSD
        vm.mockCall(
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                fraxToUsdPrice,
                clStartedAt,
                clUpdatedAt - 1 - mainFraxFeed.assetToUsdHeartbeat(),
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

        // When FRAX is stale even if FRAX < pyUSD, use Frax fallback
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 calculatedLPUsdPrice = (((uint256(crvUSDToUsdPrice) *
            10 ** 18) / fraxFallback.curvePool().price_oracle()) *
            feed.dolaPyUSDFrax().get_virtual_price()) / 10 ** 8;

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_FRAX_and_crvUSD_STALE_use_pyUSD_even_if_Frax_lt_pyUSD()
        public
    {
        (
            uint80 clRoundId,
            int256 fraxToUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = mainFraxFeed.assetToUsd().latestRoundData();

        // Set FRAX STALE even if < than pyUSD
        vm.mockCall(
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                fraxToUsdPrice,
                clStartedAt,
                clUpdatedAt - 1 - mainFraxFeed.assetToUsdHeartbeat(),
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
        ) = mainPyUSDFeed.assetToUsd().latestRoundData();

        // When FRAX is fully stale even if FRAX < pyUSD, use pyUSD
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 calculatedLPUsdPrice = (feed
            .dolaPyUSDFrax()
            .get_virtual_price() * uint256(usdcToUsdPrice)) / 10 ** 8;

        assertEq(uint256(lpUsdPrice), calculatedLPUsdPrice);
        assertEq(uint256(lpUsdPrice), uint(feed.latestAnswer()));
    }

    function test_STALE_FRAX_and_crvUSD_STALE_and_pyUSD_out_of_Bounds_use_pyUSD_fallback_even_if_Frax_lt_pyUSD()
        public
    {
        (
            uint80 clRoundId,
            int256 fraxToUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = mainFraxFeed.assetToUsd().latestRoundData();

        // Set FRAX STALE even if < than pyUSD
        vm.mockCall(
            address(mainFraxFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                fraxToUsdPrice,
                clStartedAt,
                clUpdatedAt - 1 - mainFraxFeed.assetToUsdHeartbeat(),
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
            address(mainPyUSDFeed.assetToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                0,
                IAggregator(mainPyUSDFeed.assetToUsd().aggregator())
                    .maxAnswer(),
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
            int256 usdcToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = pyUSDFallback.assetToUsd().latestRoundData();

        // When FRAX is fully stale even if FRAX < pyUSD and pyUSD is out of bounds, use pyUSD fallback
        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        uint256 pyUsdFallPrice = ((uint256(usdcToUsdPrice) *
            pyUSDFallback.curvePool().price_oracle(0)) / 10 ** 18);
        uint256 calculatedLPUsdPrice = (feed
            .dolaPyUSDFrax()
            .get_virtual_price() * uint256(pyUsdFallPrice)) / 10 ** 8;

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
        ) = fraxFallback.latestRoundData();

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

    function test_pyUsdToUsdFallBack_oracle() public {
        (
            uint80 clRoundId2,
            int256 usdcToUsdPrice,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = pyUSDFallback.assetToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 pyUsdFallback,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = pyUSDFallback.latestRoundData();

        uint256 pyUsdToUsdcPrice = pyUSDFallback.curvePool().price_oracle(0);

        uint256 estPyUsdFallback = ((uint256(usdcToUsdPrice) *
            pyUsdToUsdcPrice) / 10 ** 18);

        assertEq(uint256(pyUsdFallback), estPyUsdFallback);
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
        ) = mainPyUSDFeed.assetToUsd().latestRoundData();

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
                int(feed.dolaPyUSDFrax().get_virtual_price() / 10 ** 8);
        } else {
            oracleRoundId = clRoundIdFrax;
            oracleMinToUsdPrice = clFraxToUsdPrice;
            oracleStartedAt = clStartedAtFrax;
            oracleUpdatedAt = clUpdatedAtFrax;
            oracleAnsweredInRound = clAnsweredInRoundFrax;

            oracleLpToUsdPrice =
                (int(feed.dolaPyUSDFrax().get_virtual_price()) *
                    oracleMinToUsdPrice) /
                10 ** 8;
        }
    }
}
