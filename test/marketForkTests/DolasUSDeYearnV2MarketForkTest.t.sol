// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MarketBaseForkTest, IOracle, IDolaBorrowingRights, IERC20} from "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";
import {SimpleERC20Escrow} from "src/escrows/SimpleERC20Escrow.sol";
import {CurveLPYearnV2Feed} from "src/feeds/CurveLPYearnV2Feed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import {ChainlinkCurveFeed, ICurvePool} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import "src/feeds/CurveLPYearnV2Feed.sol";
import {console} from "forge-std/console.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";
import {CurveLPPessimisticFeed} from "src/feeds/CurveLPPessimisticFeed.sol";

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

contract DolasUSDeYearnV2MarketForkTest is MarketBaseForkTest {
    SimpleERC20Escrow escrow;
    CurveLPYearnV2Feed yearnFeed;
    CurveLPPessimisticFeed lpFeed;

    ChainlinkBasePriceFeed sUSDeFeed =
        ChainlinkBasePriceFeed(0x6277cB27232F35C75D3d908b26F3670e7d167400);

    ICurvePool public constant dolasUSDe =
        ICurvePool(0x744793B5110f6ca9cC7CDfe1CE16677c3Eb192ef);

    SimpleERC20Escrow userEscrow;

    address yearn = address(0x1Fc80CfCF5B345b904A0fB36d4222196Ed9eB8a5);
    IYearnVaultFactory yearnFactory =
        IYearnVaultFactory(0x21b1FC8A52f179757bf555346130bF27c0C2A17A);
    address lpHolder = address(0xEC092c15e8D5A48a77Cde36827F8e228CE39471a);
    address gauge = address(0x8f5e52BE9B7BDe850BA13e40284F63f14677058f);
    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        escrow = new SimpleERC20Escrow();
        // Setup YearnVault if needed
        if (yearn == address(0)) {
            // Setup YearnVault

            (address yearnVault, , , ) = yearnFactory
                .createNewVaultsAndStrategies(gauge);
            yearn = yearnVault;
            vm.startPrank(lpHolder, lpHolder);
            IERC20(address(dolasUSDe)).approve(yearn, type(uint256).max);
            IYearnVaultV2(yearn).deposit(1000000, lpHolder);
            vm.stopPrank();
        }

        Market market = new Market(
            gov,
            lender,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbr)),
            IERC20(address(yearn)),
            IOracle(address(oracle)),
            5000,
            5000,
            1000,
            false
        );
        yearnFeed = _deployDolasUSDeYearnV2Feed();
        _advancedInit(address(market), address(yearnFeed), true);

        userEscrow = SimpleERC20Escrow(
            address(Market(address(market)).predictEscrow(user))
        );
    }

    function _deployDolasUSDeYearnV2Feed()
        internal
        returns (CurveLPYearnV2Feed feed)
    {
        lpFeed = new CurveLPPessimisticFeed(
            address(dolasUSDe),
            address(sUSDeFeed),
            address(dolaFixedFeedAddr),
            false
        );

        feed = new CurveLPYearnV2Feed(address(yearn), address(lpFeed));
    }
}
