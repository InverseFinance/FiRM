// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MarketBaseForkTest, IOracle, IDolaBorrowingRights, IERC20} from "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";
import {LPCurveYearnV2Escrow} from "src/escrows/LPCurveYearnV2Escrow.sol";
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

contract CrvUSDDolaYearnV2MarketForkTest is MarketBaseForkTest {
    LPCurveYearnV2Escrow escrow;
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

    address public yearn = address(0xfb5137Aa9e079DB4b7C2929229caf503d0f6DA96);
    address yearnHolder = address(0x8B5b1D02AAB4e10e49507e89D2bE10A382D52b57); //update

    LPCurveYearnV2Escrow userEscrow;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20020781);

        escrow = new LPCurveYearnV2Escrow(address(yearn));

        feedCrvUSDDola = _deployCrvUSDDolaFeed();

        Market market = new Market(
            gov,
            lender,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbr)),
            IERC20(address(dolaCrvUSD)),
            IOracle(address(oracle)),
            5000,
            5000,
            1000,
            true
        );

        _advancedInit(address(market), address(feedCrvUSDDola), true);

        userEscrow = LPCurveYearnV2Escrow(address(market.predictEscrow(user)));
    }

    function test_escrow_immutables() public {
        testDeposit();
        assertEq(address(userEscrow.yearn()), address(yearn), "Yearn not set");
    }

    function test_depositToYearn() public {
        testDeposit();
        userEscrow.depositToYearn();
        userEscrow.withdrawFromYearn();
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
