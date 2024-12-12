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

contract DolascrvUSDYearnV2MarketForkTest is MarketBaseForkTest {
    CurveLPYearnV2Feed yearnFeed;
    CurveLPPessimisticFeed lpFeed;

    address clCrvUSDFeed = address(0xEEf0C605546958c1f899b6fB336C20671f9cD49F);
    uint256 crvUSDHeartbeat = 86400;
    address public constant dolascrvUSD =
        address(0xff17dAb22F1E61078aBa2623c89cE6110E878B3c);

    address public constant yearn =
        address(0xbCe40f1840A449cAAaF374Df0A1fEe1e212784CB);

    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21286440);

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
            address(dolascrvUSD),
            address(scrvUSDFeed),
            address(dolaFixedFeedAddr),
            false
        );

        feed = new CurveLPYearnV2Feed(address(yearn), address(lpFeed));
    }
}
