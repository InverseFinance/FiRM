// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {CurveLPSingleFeedBaseTest} from "test/feedForkTests/base/CurveLPSingleFeedBaseTest.t.sol";

contract DolaCrvUSDPriceFeedFork is CurveLPSingleFeedBaseTest {
    ChainlinkBasePriceFeed mainCrvUSDFeed;
    ChainlinkBasePriceFeed mainPyUSDFeed;
    ChainlinkBasePriceFeed baseFraxToUsd;
    ChainlinkBasePriceFeed baseUsdcToUsd;
    ChainlinkCurve2CoinsFeed crvUSDFallback;

    ICurvePool public constant dolaCrvUSD =
        ICurvePool(0x8272E1A3dBef607C04AA6e5BD3a1A134c8ac063B);

    IChainlinkFeed public constant fraxToUsd =
        IChainlinkFeed(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);

    uint256 public fraxHeartbeat = 1 hours;

    // For CrvUSD fallback
    ICurvePool public constant crvUSDFrax =
        ICurvePool(0x0CD6f267b2086bea681E922E19D40512511BE538);

    IChainlinkFeed public constant crvUSDToUsd =
        IChainlinkFeed(0xEEf0C605546958c1f899b6fB336C20671f9cD49F);
    uint256 public crvUSDHeartbeat = 24 hours;

    uint256 crvUSDIndex = 1;

    ICurvePool public constant crvUSDUSDC =
        ICurvePool(0x4DEcE678ceceb27446b35C672dC7d61F30bAD69E);

    IChainlinkFeed public constant usdcToUsd =
        IChainlinkFeed(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    uint256 public usdcHeartbeat = 24 hours;

    uint256 usdcIndex = 0;

    //  address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20591674);
        // CrvUSD fallback
        // baseFraxToUsd = new ChainlinkBasePriceFeed(
        //     gov,
        //     address(fraxToUsd),
        //     address(0),
        //     fraxHeartbeat,
        //     8
        // );
        // baseUsdcToUsd = new ChainlinkBasePriceFeed(
        //     gov,
        //     address(usdcToUsd),
        //     address(0),
        //     usdcHeartbeat,
        //     8
        // );
        // crvUSDFallback = new ChainlinkCurve2CoinsFeed(
        //     address(baseUsdcToUsdAddr),
        //     address(crvUSDUSDC),
        //     8,
        //     usdcIndex
        // );

        // // Main feed
        // mainCrvUSDFeed = new ChainlinkBasePriceFeed(
        //     gov,
        //     address(crvUSDToUsd),
        //     address(crvUSDFallback),
        //     crvUSDHeartbeat,
        //     8
        // );

        init(
            address(baseUsdcToUsdAddr),
            address(crvUSDFallbackAddr),
            address(mainCrvUSDFeedAddr),
            address(dolaCrvUSD)
        );
    }
}
