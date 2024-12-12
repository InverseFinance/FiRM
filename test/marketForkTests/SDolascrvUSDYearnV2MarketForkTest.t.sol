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

contract SDolascrvUSDYearnV2MarketForkTest is MarketBaseForkTest {
    CurveLPYearnV2Feed yearnFeed;
    CurveLPPessimisticFeed lpFeed;

    address clCrvUSDFeed = address(0xEEf0C605546958c1f899b6fB336C20671f9cD49F);
    uint256 crvUSDHeartbeat = 86400;
    address public constant sDolascrvUSD =
        address(0x76A962BA6770068bCF454D34dDE17175611e6637);

    address yearn;
    IYearnVaultFactory yearnFactory =
        IYearnVaultFactory(0x21b1FC8A52f179757bf555346130bF27c0C2A17A);
    address lpHolder = address(0x9D5Df30F475CEA915b1ed4C0CCa59255C897b61B);
    address gauge = address(0xDa0C79988b30d07857994e2C2650FCe644b690E1);
    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21386890);

        // Setup YearnVault if needed
        if (yearn == address(0)) {
            // Setup YearnVault

            (address yearnVault, , , ) = yearnFactory
                .createNewVaultsAndStrategies(gauge);
            yearn = yearnVault;
            vm.startPrank(lpHolder, lpHolder);
            IERC20(address(sDolascrvUSD)).approve(yearn, type(uint256).max);
            IYearnVaultV2(yearn).deposit(1000000, lpHolder);
            vm.stopPrank();
        }

        Market market = new Market(
            gov,
            lender,
            pauseGuardian,
            address(simpleERC20EscrowAddr),
            IDolaBorrowingRights(address(dbr)),
            IERC20(address(yearn)),
            IOracle(address(oracle)),
            5000,
            5000,
            1000,
            false
        );
        yearnFeed = _deployDolascrvUSDYearnV2Feed();
        _advancedInit(address(market), address(yearnFeed), true);
    }

    function _deployDolascrvUSDYearnV2Feed()
        internal
        returns (CurveLPYearnV2Feed feed)
    {
        ChainlinkBasePriceFeed scrvUSDFeed = new ChainlinkBasePriceFeed(
            gov,
            clCrvUSDFeed,
            address(0),
            crvUSDHeartbeat
        );

        lpFeed = new CurveLPPessimisticFeed(
            address(sDolascrvUSD),
            address(scrvUSDFeed),
            address(dolaFixedFeedAddr),
            false
        );

        feed = new CurveLPYearnV2Feed(address(yearn), address(lpFeed));
    }
}
