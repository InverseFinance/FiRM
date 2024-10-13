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

contract DolaFraxBPPriceFeedFork is DolaCurveLPPessimisticNestedFeedBaseTest {
    ChainlinkBasePriceFeed mainFraxFeed;
    ChainlinkBasePriceFeed mainUSDCFeed;
    ChainlinkBasePriceFeed baseEthToUsd;
    ChainlinkBasePriceFeed baseUsdeToUsd;
    ChainlinkCurveFeed usdcFallback;
    ChainlinkCurveFeed fraxFallback;
    CurveLPPessimisticFeed fraxBPFeed;

    ICurvePool public constant dolaFraxBP =
        ICurvePool(0xE57180685E3348589E9521aa53Af0BCD497E884d);

    ICurvePool public constant fraxBP =
        ICurvePool(0xDcEF968d416a41Cdac0ED8702fAC8128A64241A2);

    IChainlinkFeed public constant fraxToUsd =
        IChainlinkFeed(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);

    IChainlinkFeed public constant usdcToUsd =
        IChainlinkFeed(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    uint256 public fraxHeartbeat = 1 hours;
    uint256 public usdcHeartbeat = 24 hours;

    // For Frax fallback
    IChainlinkFeed public constant usdeToUsd =
        IChainlinkFeed(0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961);
    uint256 public usdeHeartbeat = 24 hours;
    ICurvePool public constant fraxUSDe =
        ICurvePool(0x5dc1BF6f1e983C0b21EfB003c105133736fA0743);
    uint256 fraxIndex = 0;
    uint256 usdeK = 0;

    // For USDC fallabck
    ICurvePool public constant tricryptoETH =
        ICurvePool(0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B);

    IChainlinkFeed public constant ethToUsd =
        IChainlinkFeed(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    uint256 public ethHeartbeat = 1 hours;
    uint256 public constant ethK = 1;

    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20906980); // FRAX < pyUSD at this block  coin1 < coin2 at this block
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
            usdeK,
            fraxIndex
        );

        // USDC fallback
        // For USDC fallback
        baseEthToUsd = new ChainlinkBasePriceFeed(
            gov,
            address(ethToUsd),
            address(0),
            ethHeartbeat
        );
        usdcFallback = new ChainlinkCurveFeed(
            address(baseEthToUsd),
            address(tricryptoETH),
            ethK,
            0
        );

        // Main feeds
        mainFraxFeed = new ChainlinkBasePriceFeed(
            gov,
            address(fraxToUsd),
            address(fraxFallback),
            fraxHeartbeat
        );

        mainUSDCFeed = new ChainlinkBasePriceFeed(
            gov,
            address(usdcToUsd),
            address(usdcFallback),
            usdcHeartbeat
        );

        fraxBPFeed = new CurveLPPessimisticFeed(
            address(fraxBP),
            address(mainFraxFeed),
            address(mainUSDCFeed),
            true
        );

        init(address(fraxBPFeed), address(dolaFraxBP));
    }
}
