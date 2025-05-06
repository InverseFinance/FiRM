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

contract DolaUSRYearnV2MarketForkTest is MarketBaseForkTest {
    CurveLPYearnV2Feed yearnFeed;
    CurveLPPessimisticFeed lpFeed;

    address public usrFeed = address(0x34ad75691e25A8E9b681AAA85dbeB7ef6561B42c);
 
    ChainlinkBasePriceFeed usrWrapper;

    ICurvePool public constant dolaUSR =
        ICurvePool(0x38De22a3175708D45E7c7c64CD78479C8B56f76E);

    address public constant yearn =
        address(0x57a2c7925bAA1894a939f9f6721Ea33F2EcFD0e2);

    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

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
        yearnFeed = _deployDolaUSRYearnV2Feed();
        _advancedInit(address(market), address(yearnFeed), true);
    }

    function _deployDolaUSRYearnV2Feed()
        internal
        returns (CurveLPYearnV2Feed feed)
    {
        usrWrapper = new ChainlinkBasePriceFeed(
            gov,
            address(usrFeed),
            address(0),
            86400
        );

        lpFeed = new CurveLPPessimisticFeed(
            address(dolaUSR),
            address(usrWrapper),
            address(dolaFixedFeedAddr),
            false
        );

        feed = new CurveLPYearnV2Feed(address(yearn), address(lpFeed));
    }
}
