// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ERC4626Feed, IERC4626} from "src/feeds/ERC4626Feed.sol";
import {ChainlinkBridgeAssetFeed} from "src/feeds/ChainlinkBridgeAssetFeed.sol";
import {ChainlinkBridgeAssetBase} from "test/feedForkTests/ChainlinkBridgeAssetBase.t.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";

import "forge-std/console2.sol";


contract WOETHFeed is ChainlinkBridgeAssetBase {
    ERC4626Feed vaultFeed;
    ChainlinkBasePriceFeed ethWrapper;
    ChainlinkBasePriceFeed oEthToEthWrapper;
    
    address oEthToEth = 0x703118C4CbccCBF2AB31913e0f8075fbbb15f563;
    address wOeth = 0xDcEe70654261AF21C44c093C300eD3Bb97b78192;
    address ethToUsd = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        oEthToEthWrapper = new ChainlinkBasePriceFeed(address(this), oEthToEth, address(0), 86400);
        vaultFeed = new ERC4626Feed(wOeth, address(oEthToEthWrapper));
        ethWrapper = new ChainlinkBasePriceFeed(address(this),ethToUsd, address(0), 3600);
        init(address(vaultFeed), address(ethWrapper), true);
    }

    function test_woEth() public {
        uint256 woEthToOEth = IERC4626(wOeth).previewRedeem(1e18);
        uint256 oEthToEthPrice = uint(oEthToEthWrapper.latestAnswer());
        uint256 ethToUsdPrice = uint(ethWrapper.latestAnswer());
        uint256 woEthToEthPrice = woEthToOEth * oEthToEthPrice / 1e18;
        uint256 woEthToUsdPrice = woEthToEthPrice * ethToUsdPrice / 1e18;
        assertEq(woEthToUsdPrice, uint(feed.latestAnswer()));
        console2.log(uint(feed.latestAnswer()));
    }
}