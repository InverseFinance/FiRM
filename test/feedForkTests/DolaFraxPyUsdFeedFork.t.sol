// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {CurveLPPessimisticFeed} from "src/feeds/CurveLPPessimisticFeed.sol";
import {DolaCurveLPPessimisticNestedFeedBaseTest} from "test/feedForkTests/DolaCurveLPPessimisticNestedFeedBaseTest.t.sol";
import {DolaFixedPriceFeed} from "src/feeds/DolaFixedPriceFeed.sol";

contract DolaFraxPyUsdPriceFeedFork is
    DolaCurveLPPessimisticNestedFeedBaseTest
{
    ChainlinkBasePriceFeed mainFraxFeed;
    ChainlinkBasePriceFeed mainPyUSDFeed;
    ChainlinkBasePriceFeed baseCrvUsdToUsd;
    ChainlinkBasePriceFeed baseUsdcToUsd;
    ChainlinkBasePriceFeed baseUsdeToUsd;
    ChainlinkCurveFeed pyUSDFallback;
    ChainlinkCurveFeed fraxFallback;
    CurveLPPessimisticFeed fraxPyUsdFeed;

    ICurvePool public constant dolaPyUSDFrax =
        ICurvePool(0xef484de8C07B6e2d732A92B5F78e81B38f99f95E);

    ICurvePool public constant pyUSDFrax =
        ICurvePool(0xA5588F7cdf560811710A2D82D3C9c99769DB1Dcb);

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

    uint256 fraxIndex = 0;
    // For pyUSD fallback
    ICurvePool public constant pyUsdUsdc =
        ICurvePool(0x383E6b4437b59fff47B619CBA855CA29342A8559);
    uint256 public constant targetKPyUsd = 0;

    IChainlinkFeed public constant usdcToUsd =
        IChainlinkFeed(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    uint256 public usdcHeartbeat = 24 hours;

    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    // UPDATE TO USE USDe feed for Frax fallback
    IChainlinkFeed public constant usdeToUsd =
        IChainlinkFeed(0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961);
    uint256 public usdeHeartbeat = 24 hours;
    ICurvePool public constant fraxUSDe =
        ICurvePool(0x5dc1BF6f1e983C0b21EfB003c105133736fA0743);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20060490); // FRAX < pyUSD at this block  coin1 < coin2 at this block
        // FRAX fallback
        baseUsdeToUsd = new ChainlinkBasePriceFeed(
            gov,
            address(usdeToUsd),
            address(0),
            usdeHeartbeat
        );
        fraxFallback = new ChainlinkCurveFeed(
            address(baseUsdeToUsd),
            address(fraxUSDe),
            0,
            fraxIndex
        );

        // USDC fallback
        baseUsdcToUsd = new ChainlinkBasePriceFeed(
            gov,
            address(usdcToUsd),
            address(0),
            usdcHeartbeat
        );

        pyUSDFallback = new ChainlinkCurveFeed(
            address(baseUsdcToUsd),
            address(pyUsdUsdc),
            targetKPyUsd,
            0
        );

        // Main feeds
        mainFraxFeed = new ChainlinkBasePriceFeed(
            gov,
            address(fraxToUsd),
            address(fraxFallback),
            fraxHeartbeat
        );

        mainPyUSDFeed = new ChainlinkBasePriceFeed(
            gov,
            address(pyUsdToUsd),
            address(pyUSDFallback),
            pyUSDHeartbeat
        );

        fraxPyUsdFeed = new CurveLPPessimisticFeed(
            address(pyUSDFrax),
            address(mainFraxFeed),
            address(mainPyUSDFeed),
            false
        );

        init(address(fraxPyUsdFeed), address(dolaPyUSDFrax));
    }
}
