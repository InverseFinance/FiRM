// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {CurveLPPessimiticYearnV2FeedBaseTest} from "test/feedForkTests/base/CurveLPPessimsticYearnV2FeedBaseTest.t.sol";

contract DolaFraxBPYearnV2FeedFork is CurveLPPessimiticYearnV2FeedBaseTest {
    ChainlinkCurveFeed usdcFallback;
    ChainlinkCurve2CoinsFeed fraxFallback;
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

    uint256 fraxIndex = 0;

    uint256 public crvUSDHeartbeat = 24 hours;

    address public _yearn = address(0xe5F625e8f4D2A038AE9583Da254945285E5a77a4);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 18272690); // FRAX < USDC at this block     coin1 < coin2 at this block

        // For FRAX fallback
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

        // For USDC fallback
        baseEthToUsd = new ChainlinkBasePriceFeed(
            gov,
            address(ethToUsd),
            address(0),
            ethHeartbeat,
            8
        );
        usdcFallback = new ChainlinkCurveFeed(
            address(baseEthToUsd),
            address(tricryptoETH),
            ethK,
            8,
            0
        );

        // Main feeds
        mainFraxFeed = new ChainlinkBasePriceFeed(
            gov,
            address(fraxToUsd),
            address(fraxFallback),
            fraxHeartbeat,
            8
        );

        mainUsdcFeed = new ChainlinkBasePriceFeed(
            gov,
            address(usdcToUsd),
            address(usdcFallback),
            usdcHeartbeat,
            8
        );

        init(
            address(baseCrvUsdToUsd),
            address(fraxFallback),
            address(mainFraxFeed),
            address(baseEthToUsd),
            address(usdcFallback),
            address(mainUsdcFeed),
            address(dolaFraxBP),
            address(_yearn)
        );
    }
}
