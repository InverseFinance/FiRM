// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {CurveLPPessimiticFeedBaseTest} from "test/feedForkTests/CurveLPPessimsticFeedBaseTest.t.sol";

contract DolaFraxPyUsdPriceFeedFork is CurveLPPessimiticFeedBaseTest {
    ChainlinkBasePriceFeed mainFraxFeed;
    ChainlinkBasePriceFeed mainPyUSDFeed;
    ChainlinkBasePriceFeed baseCrvUsdToUsd;
    ChainlinkBasePriceFeed baseUsdcToUsd;
    ChainlinkCurveFeed pyUSDFallback;
    ChainlinkCurve2CoinsFeed fraxFallback;

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

    uint256 fraxIndex = 0;
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
        vm.createSelectFork(url, 20060490); // FRAX < pyUSD at this block  coin1 < coin2 at this block
        // FRAX fallback
        baseCrvUsdToUsd = new ChainlinkBasePriceFeed(
            gov,
            address(crvUSDToUsd),
            address(0),
            crvUSDHeartbeat,
            8
        );
        fraxFallback = new ChainlinkCurve2CoinsFeed(
            address(baseCrvUsdToUsd),
            address(crvUSDFrax),
            8,
            fraxIndex
        );

        // USDC fallback
        baseUsdcToUsd = new ChainlinkBasePriceFeed(
            gov,
            address(usdcToUsd),
            address(0),
            usdcHeartbeat,
            8
        );

        pyUSDFallback = new ChainlinkCurveFeed(
            address(baseUsdcToUsd),
            address(pyUsdUsdc),
            targetKPyUsd,
            8,
            1
        );

        // Main feeds
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

        init(
            address(baseCrvUsdToUsd),
            address(fraxFallback),
            address(mainFraxFeed),
            address(baseUsdcToUsd),
            address(pyUSDFallback),
            address(mainPyUSDFeed),
            address(dolaPyUSDFrax)
        );
    }
}
