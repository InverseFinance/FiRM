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
import {MockFeedDescription} from "test/mocks/MockFeedDescription.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";

contract DolaDeUSDYearnV2MarketForkTest is MarketBaseForkTest {
    CurveLPYearnV2Feed yearnFeed;
    CurveLPPessimisticFeed lpFeed;

    address deUSDFeed = address(0x471a6299C027Bd81ed4D66069dc510Bd0569f4F8);
    ChainlinkBasePriceFeed deUSDWrapper;
    ICurvePool public constant dolaDeUSD =
        ICurvePool(0x6691DBb44154A9f23f8357C56FC9ff5548A8bdc4);

    address public constant yearn =
        address(0xc7C1B907BCD3194C0D9bFA2125251af98BdDAfbb);

    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21826229);

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
        yearnFeed = _deployDolaDeUSDYearnV2Feed();
        _advancedInit(address(market), address(yearnFeed), true);
    }

    function _deployDolaDeUSDYearnV2Feed()
        internal
        returns (CurveLPYearnV2Feed feed)
    {
        deUSDWrapper = new ChainlinkBasePriceFeed(
            gov,
            address(deUSDFeed),
            address(0),
            1
        );

        lpFeed = new CurveLPPessimisticFeed(
            address(dolaDeUSD),
            address(deUSDWrapper),
            address(dolaFixedFeedAddr),
            false
        );

        feed = new CurveLPYearnV2Feed(address(yearn), address(lpFeed));
    }
}
