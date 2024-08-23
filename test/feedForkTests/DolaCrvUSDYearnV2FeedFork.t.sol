// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {CurveLPYearnV2FeedBaseTest} from "test/feedForkTests/CurveLPYearnV2FeedBaseTest.t.sol";
import {IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";
import {ConfigAddr} from "src/test/ConfigAddr.sol";

contract DolaCrvUSDYearnV2FeedFork is CurveLPYearnV2FeedBaseTest, ConfigAddr {
    ChainlinkBasePriceFeed mainCrvUSDFeed;
    ChainlinkBasePriceFeed mainPyUSDFeed;
    ChainlinkBasePriceFeed baseFraxToUsd;
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

    //   address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    IYearnVaultV2 _yearn =
        IYearnVaultV2(0xfb5137Aa9e079DB4b7C2929229caf503d0f6DA96);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20590050);
        // CrvUSD fallback
        baseFraxToUsd = new ChainlinkBasePriceFeed(
            gov,
            address(fraxToUsd),
            address(0),
            fraxHeartbeat,
            8
        );
        crvUSDFallback = new ChainlinkCurve2CoinsFeed(
            address(baseFraxToUsd),
            address(crvUSDFrax),
            8,
            crvUSDIndex
        );

        // Main feed
        mainCrvUSDFeed = new ChainlinkBasePriceFeed(
            gov,
            address(crvUSDToUsd),
            address(crvUSDFallback),
            crvUSDHeartbeat,
            8
        );

        init(
            address(baseFraxToUsdAddr),
            address(crvUSDFallbackAddr),
            address(mainCrvUSDFeedAddr),
            address(dolaCrvUSD),
            address(_yearn)
        );
    }
}
