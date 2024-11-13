// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MarketBaseForkTest, IOracle, IDolaBorrowingRights, IERC20} from "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";
import {ConvexEscrowV2} from "src/escrows/ConvexEscrowV2.sol";
import {CurveLPPessimisticFeed} from "src/feeds/CurveLPPessimisticFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {DolaFixedPriceFeed} from "src/feeds/DolaFixedPriceFeed.sol";
import {console} from "forge-std/console.sol";

contract DolaFraxBPConvexMarketForkTest is MarketBaseForkTest {
    ConvexEscrowV2 escrow;
    CurveLPPessimisticFeed feedDolaFraxBP;

    ChainlinkBasePriceFeed mainFraxFeed;
    ChainlinkBasePriceFeed mainUSDCFeed;
    ChainlinkBasePriceFeed baseEthToUsd;
    ChainlinkBasePriceFeed baseUsdeToUsd;
    ChainlinkCurveFeed usdcFallback;
    ChainlinkCurveFeed fraxFallback;
    CurveLPPessimisticFeed fraxBPFeed;
    DolaFixedPriceFeed dolaFeed;

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

    // Escrow implementation
    IERC20 cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address rewardPool = address(0x0404d05F3992347d2f0dC3a97bdd147D77C85c1c);
    address booster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    ConvexEscrowV2 userEscrow;
    uint256 pid = 115;

    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20878462);

        escrow = new ConvexEscrowV2(
            address(rewardPool),
            address(booster),
            address(cvx),
            address(crv),
            pid
        );

        feedDolaFraxBP = _deployDolaFraxBPFeed();

        Market market = new Market(
            gov,
            lender,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbr)),
            IERC20(address(dolaFraxBP)),
            IOracle(address(oracle)),
            5000,
            5000,
            1000,
            true
        );

        _advancedInit(address(market), address(feedDolaFraxBP), true);

        userEscrow = ConvexEscrowV2(address(market.predictEscrow(user)));
    }

    function test_escrow_immutables() public {
        testDeposit();
        assertEq(
            address(userEscrow.rewardPool()),
            address(rewardPool),
            "Reward pool not set"
        );
        assertEq(
            address(userEscrow.booster()),
            address(booster),
            "Booster not set"
        );
        assertEq(address(userEscrow.cvx()), address(cvx), "CVX not set");
        assertEq(address(userEscrow.crv()), address(crv), "CRV not set");
    }

    function _deployDolaFraxBPFeed()
        internal
        returns (CurveLPPessimisticFeed feed)
    {
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

        dolaFeed = new DolaFixedPriceFeed();

        feed = new CurveLPPessimisticFeed(
            address(dolaFraxBP),
            address(fraxBPFeed),
            address(dolaFeed),
            false
        );
    }
}
