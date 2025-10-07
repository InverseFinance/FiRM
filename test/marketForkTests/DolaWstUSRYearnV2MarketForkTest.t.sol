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

contract DolaWstUSRYearnV2MarketForkTest is MarketBaseForkTest {
    CurveLPYearnV2Feed yearnFeed;
    CurveLPPessimisticFeed lpFeed;
 
    address usrWrapper = address(0x182Af82E3619D2182b3669BbFA8C72bC57614aDf); 

    ICurvePool public constant dolaWstUSR =
        ICurvePool(0x64273624eb57c5cA961d366CBF3968e760Bf0452);

    address public constant yearn =
        address(0x8A5f20dA6B393fE25aCF1522C828166D22eF8321);

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

        lpFeed = new CurveLPPessimisticFeed(
            address(dolaWstUSR),
            address(usrWrapper),
            address(dolaFixedFeedAddr),
            false
        );

        feed = new CurveLPYearnV2Feed(address(yearn), address(lpFeed));
    }
}
