// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MarketBaseForkTest, IOracle, IDolaBorrowingRights, IERC20} from "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";

import {LPCurveConvexEscrow} from "src/escrows/LPCurveConvexEscrow.sol";
import {CurveLPSingleFeed} from "src/feeds/CurveLPSingleFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import "src/feeds/CurveLPSingleFeed.sol";
import {console} from "forge-std/console.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";

interface IYearnVaultFactory {
    function createNewVaultsAndStrategies(
        address _gauge
    )
        external
        returns (
            address vault,
            address convexStrategy,
            address curveStrategy,
            address convexFraxStrategy
        );
}

contract CrvUSDDolaConvexMarketForkTest is MarketBaseForkTest {
    LPCurveConvexEscrow escrow;

    CurveLPSingleFeed feedCrvUSDDola;

    ChainlinkBasePriceFeed mainCrvUSDFeed;
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

    address rewardPool = address(0xC94208D230EEdC4cDC4F80141E21aA485A515660);

    address booster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    uint256 pid = 215;

    IERC20 public cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    LPCurveConvexEscrow userEscrow;

    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20591674);

        // escrow = new LPCurveConvexEscrow(
        //     rewardPool,
        //     booster,
        //     address(cvx),
        //     address(crv),
        //     pid
        // );

        // feedCrvUSDDola = _deployCrvUSDDolaFeed();

        Market market = new Market(
            gov,
            lender,
            pauseGuardian,
            address(crvUSDDolaConvexEscrowAddr),
            IDolaBorrowingRights(address(dbr)),
            IERC20(address(dolaCrvUSD)),
            IOracle(address(oracle)),
            5000,
            5000,
            1000,
            true
        );

        _advancedInit(address(market), address(crvUSDDolaFeedAddr), true);

        userEscrow = LPCurveConvexEscrow(address(market.predictEscrow(user)));
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

    function test_depositToConvex() public {
        testDeposit();
        userEscrow.depositToConvex();
    }

    function test_withdrawFromConvex() public {
        testDeposit();
        userEscrow.depositToConvex();
        userEscrow.withdrawFromConvex();
    }

    function _deployCrvUSDDolaFeed() internal returns (CurveLPSingleFeed feed) {
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

        feed = new CurveLPSingleFeed(
            address(dolaCrvUSD),
            address(mainCrvUSDFeed)
        );
    }
}
