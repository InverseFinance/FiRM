// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBridgeAssetFeed.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkBridgeAssetBase} from "test/feedForkTests/ChainlinkBridgeAssetBase.t.sol";

contract WbtcFeedFork is ChainlinkBridgeAssetBase {
    address wbtcToBtcBase = 0xfdFD9C85aD200c506Cf9e21F1FD8dd01932FBB23;
    uint wbtcToBtcHeartbeat = 3660;
    address btcToUsdBase = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    uint btcToUsdHeartbeat = 3660;
    address gov;
    ChainlinkBasePriceFeed wbtcToBtc;
    ChainlinkBasePriceFeed btcToUsd;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        wbtcToBtc = new ChainlinkBasePriceFeed(gov, wbtcToBtcBase, address(0), wbtcToBtcHeartbeat);
        btcToUsd = new ChainlinkBasePriceFeed(gov, btcToUsdBase, address(0), btcToUsdHeartbeat);
        init(address(wbtcToBtc), address(btcToUsd), true);
    }

    function test_latestAnswer_returnSameAsLatestRoundData() public {
        (, int btcLRD, , , ) = feed.collateralToBridgeAsset().latestRoundData();
        int btcLA = feed.collateralToBridgeAsset().latestAnswer();

        assertEq(btcLRD, btcLA);
    }
}
