// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {CurveLPYearnV2FeedBaseTest} from "test/feedForkTests/CurveLPYearnV2FeedBaseTest.t.sol";

contract SDolaReUSDYearnV2FeedFork is CurveLPYearnV2FeedBaseTest {
    address public constant baseCrvUSDFeed = address(0x237C421F396216d0869F5177c11E40e7F043b6d2);
    uint256 public assetOrTargetK = 0;
    uint256 public targetIndex = 0;
    address public reUSDsDola = address(0x48d670D189B4b48757992D36897bCa6E3f889040);
    address public reUSDscrvUSD = address(0xc522A6606BBA746d7960404F22a3DB936B6F4F50);
    ChainlinkCurveFeed reUSDFeed;
    CurveLPPessimisticFeed sDolaReUSDFeed;
    address public yearnVault = 0x7c439Df9ADE8831180EA4D546c1E910D4Ba71a86;
    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        reUSDFeed = new ChainlinkCurveFeed(
            baseCrvUSDFeed,
            reUSDscrvUSD,
            assetOrTargetK,
            targetIndex
        );

        sDolaReUSDFeed = new CurveLPPessimisticFeed(
            reUSDsDola,
            address(reUSDFeed),
            dolaFixedFeedAddr,
            false
        );
        init(address(sDolaReUSDFeed), address(0), yearnVault);
    }
}
