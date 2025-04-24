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

contract SDolaReUSDYearnV2MarketForkTest is MarketBaseForkTest {
    CurveLPYearnV2Feed yearnFeed;
    CurveLPPessimisticFeed lpFeed;

    address public constant baseCrvUSDFeed = address(0x237C421F396216d0869F5177c11E40e7F043b6d2);
    uint256 public assetOrTargetK = 0;
    uint256 public targetIndex = 0;
    address public reUSDsDola = address(0x48d670D189B4b48757992D36897bCa6E3f889040);
    address public reUSDscrvUSD = address(0xc522A6606BBA746d7960404F22a3DB936B6F4F50);
    address public reUSD = address(0x57aB1E0003F623289CD798B1824Be09a793e4Bec);
    ChainlinkCurveFeed reUSDFeed;

    address yearn = address(0x7c439Df9ADE8831180EA4D546c1E910D4Ba71a86);
    address yearnLPFeed = address(0x8c8A46bbaad08c3b90EEb687cA6E25aBb9203561);
    address marketAddr = address(0x1fD4985cdd57bDb1eD646B10B7952fCD58946916);

    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        _advancedInit(marketAddr, address(yearnLPFeed), true);
    }

    function _deploySDolaReUSDYearnV2Feed()
        internal
        returns (CurveLPYearnV2Feed feed)
    {
        reUSDFeed = new ChainlinkCurveFeed(
            baseCrvUSDFeed,
            reUSDscrvUSD,
            assetOrTargetK,
            targetIndex
        );

        lpFeed = new CurveLPPessimisticFeed(
            reUSDsDola,
            address(reUSDFeed),
            address(dolaFixedFeedAddr),
            false
        );

        feed = new CurveLPYearnV2Feed(address(yearn), address(lpFeed));
    }
}
