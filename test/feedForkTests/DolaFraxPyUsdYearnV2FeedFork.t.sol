// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IYearnVaultV2} from "src/interfaces/IYearnVaultV2.sol";
import {DolaFixedPriceFeed} from "src/feeds/DolaFixedPriceFeed.sol";
import {CurveLPYearnV2Feed} from "src/feeds/CurveLPYearnV2Feed.sol";
import {CurveLPYearnV2FeedBaseTest} from "test/feedForkTests/CurveLPYearnV2FeedBaseTest.t.sol";

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

contract DolaFraxPyUsdYearnV2FeedFork is CurveLPYearnV2FeedBaseTest {
    ChainlinkBasePriceFeed mainFraxFeed;
    ChainlinkBasePriceFeed mainPyUSDFeed;
    ChainlinkBasePriceFeed baseCrvUsdToUsd;
    ChainlinkBasePriceFeed baseUsdcToUsd;
    ChainlinkCurveFeed pyUSDFallback;
    ChainlinkCurve2CoinsFeed fraxFallback;
    CurveLPPessimisticFeed fraxPyUsdFeed;
    CurveLPPessimisticFeed dolaFraxPyUsdFeed;
    DolaFixedPriceFeed dolaFeed;

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

    // For yearn vault creation and initial deposit
    address lpHolder = 0xBFa04e5D6Ac1163b7Da3E873e5B9C969E91A0Ac0;
    address gauge = 0x4B092818708A721cB187dFACF41f440ADb79044D;
    address _yearn = 0xcC2EFb8bEdB6eD69ADeE0c3762470c38D4730C50;
    address yearnHolder = address(0xD);
    IYearnVaultFactory yearnFactory =
        IYearnVaultFactory(0x21b1FC8A52f179757bf555346130bF27c0C2A17A);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20816091); // FRAX < pyUSD at this block  coin1 < coin2 at this block
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

        fraxPyUsdFeed = new CurveLPPessimisticFeed(
            address(pyUSDFrax),
            address(mainFraxFeed),
            address(mainPyUSDFeed),
            false
        );

        dolaFeed = new DolaFixedPriceFeed();

        dolaFraxPyUsdFeed = new CurveLPPessimisticFeed(
            address(dolaPyUSDFrax),
            address(fraxPyUsdFeed),
            address(dolaFeed),
            false
        );
        // Setup YearnVault if needed
        if (_yearn == address(0)) {
            // Setup YearnVault

            (address yearnVault, , , ) = yearnFactory
                .createNewVaultsAndStrategies(gauge);
            _yearn = yearnVault;
            vm.startPrank(lpHolder, lpHolder);
            IERC20(address(dolaPyUSDFrax)).approve(_yearn, type(uint256).max);
            IYearnVaultV2(_yearn).deposit(1000000, yearnHolder);
            vm.stopPrank();
        }

        init(
            address(dolaFraxPyUsdFeed),
            address(dolaPyUSDFrax),
            address(_yearn)
        );
    }

    function test_description() public {
        console.log("feed:", feed.description());
    }
}
