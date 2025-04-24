// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {DolaCurveLPPessimsticFeedBaseTest} from "test/feedForkTests/DolaCurveLPPessimsticFeedBaseTest.t.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";

contract SDolaReUSDFeedFork is DolaCurveLPPessimsticFeedBaseTest, ConfigAddr {
    address public constant baseCrvUSDFeed = address(0x237C421F396216d0869F5177c11E40e7F043b6d2);
    uint256 public assetOrTargetK = 0;
    uint256 public targetIndex = 0;
    address public reUSDsDola = address(0x48d670D189B4b48757992D36897bCa6E3f889040);
    address public reUSDscrvUSD = address(0xc522A6606BBA746d7960404F22a3DB936B6F4F50);
    ChainlinkCurveFeed reUSDFeed;
    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        reUSDFeed = new ChainlinkCurveFeed(
            baseCrvUSDFeed,
            reUSDscrvUSD,
            assetOrTargetK,
            targetIndex
        );
        init(address(0), address(reUSDFeed), address(reUSDsDola));
    }
}
