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

contract DolasUSDsYearnV2MarketForkTest is MarketBaseForkTest {
    SimpleERC20Escrow escrow;
    CurveLPYearnV2Feed yearnFeed;
    CurveLPPessimisticFeed lpFeed;

    address clDaiFeed = address(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);
    uint256 daiHeartbeat = 3600;

    ICurvePool public constant dolasUSDs =
        ICurvePool(0x8b83c4aA949254895507D09365229BC3a8c7f710);

    SimpleERC20Escrow userEscrow;

    address yearn = address(0x342D24F2a3233F7Ac8A7347fA239187BFd186066);
    IYearnVaultFactory yearnFactory =
        IYearnVaultFactory(0x21b1FC8A52f179757bf555346130bF27c0C2A17A);
    address lpHolder = address(0xEC092c15e8D5A48a77Cde36827F8e228CE39471a);
    address gauge = address(0x8B0aBcFC78a5c14520682FCD76A0E52B71126079);
    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21239299);

        escrow = new SimpleERC20Escrow();
        // Setup YearnVault if needed
        if (yearn == address(0)) {
            // Setup YearnVault

            (address yearnVault, , , ) = yearnFactory
                .createNewVaultsAndStrategies(gauge);
            yearn = yearnVault;
            vm.startPrank(lpHolder, lpHolder);
            IERC20(address(dolasUSDs)).approve(yearn, type(uint256).max);
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
        yearnFeed = _deployDolasUSDsYearnV2Feed();
        _advancedInit(address(market), address(yearnFeed), true);

        userEscrow = SimpleERC20Escrow(
            address(Market(address(market)).predictEscrow(user))
        );
    }

    function _deployDolasUSDsYearnV2Feed()
        internal
        returns (CurveLPYearnV2Feed feed)
    {
        ChainlinkBasePriceFeed sUSDsFeed = new ChainlinkBasePriceFeed(
            gov,
            clDaiFeed,
            address(0),
            daiHeartbeat
        );

        lpFeed = new CurveLPPessimisticFeed(
            address(dolasUSDs),
            address(sUSDsFeed),
            address(dolaFixedFeedAddr),
            false
        );

        feed = new CurveLPYearnV2Feed(address(yearn), address(lpFeed));
    }
}
