// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MarketBaseForkTest, IOracle, IDolaBorrowingRights, IERC20} from "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";
import {CurveLPPessimisticFeed} from "src/feeds/CurveLPPessimisticFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {console} from "forge-std/console.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";
import {SimpleERC20Escrow} from "src/escrows/SimpleERC20Escrow.sol";
import {CurveLPYearnV2Feed} from "src/feeds/CurveLPYearnV2Feed.sol";

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

contract DolaFraxPyUSDYearnV2MarketForkTest is MarketBaseForkTest {
    SimpleERC20Escrow escrow;
    CurveLPYearnV2Feed feedDolaFraxPyUSDYearnV2;
    CurveLPPessimisticFeed feedDolaFraxPyUSD;

    ChainlinkBasePriceFeed mainFraxFeed;
    ChainlinkBasePriceFeed mainPyUSDFeed;
    ChainlinkBasePriceFeed baseCrvUsdToUsd;
    ChainlinkBasePriceFeed baseUsdcToUsd;
    ChainlinkCurveFeed pyUSDFallback;
    ChainlinkCurve2CoinsFeed fraxFallback;

    ICurvePool public constant dolaFraxPyUSD =
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

    address gauge = 0x4B092818708A721cB187dFACF41f440ADb79044D;
    IYearnVaultFactory yearnFactory =
        IYearnVaultFactory(0x21b1FC8A52f179757bf555346130bF27c0C2A17A);
    IYearnVaultV2 public yearn =
        IYearnVaultV2(0xcC2EFb8bEdB6eD69ADeE0c3762470c38D4730C50);

    uint256 public constant pid = 317;

    address public rewardPool =
        address(0xE8cBdBFD4A1D776AB1146B63ABD1718b2F92a823);
    address public booster =
        address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IERC20 public cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    SimpleERC20Escrow userEscrow;

    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20878462);
        // Setup YearnVault
        // (address yearnVault, , , ) = yearnFactory.createNewVaultsAndStrategies(
        //     gauge
        // );
        // yearn = IYearnVaultV2(yearnVault);

        escrow = new SimpleERC20Escrow();

        //feedDolaFraxPyUSDYearnV2 = _deployDolaFraxPyUSDFeed();

        Market market = new Market(
            gov,
            lender,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbr)),
            IERC20(address(0xcC2EFb8bEdB6eD69ADeE0c3762470c38D4730C50)), // yearn vault
            IOracle(address(oracle)),
            5000,
            5000,
            1000,
            true
        );

        _advancedInit(
            address(market),
            address(0xCe11740bD83cA366e76Ee5ff775134288D9f891e),
            true
        );

        userEscrow = SimpleERC20Escrow(address(market.predictEscrow(user)));
    }

    function _deployDolaFraxPyUSDFeed()
        internal
        returns (CurveLPYearnV2Feed feed)
    {
        // FRAX fallback
        baseCrvUsdToUsd = new ChainlinkBasePriceFeed(
            gov,
            address(crvUSDToUsd),
            address(0),
            crvUSDHeartbeat
        );
        fraxFallback = new ChainlinkCurve2CoinsFeed(
            address(baseCrvUsdToUsd),
            address(crvUSDFrax),
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
            1
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

        feedDolaFraxPyUSD = new CurveLPPessimisticFeed(
            address(dolaFraxPyUSD),
            address(mainFraxFeed),
            address(mainPyUSDFeed),
            false
        );

        feed = new CurveLPYearnV2Feed(
            address(yearn),
            address(feedDolaFraxPyUSD)
        );
    }
}
