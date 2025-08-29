// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {ERC4626Feed, IERC4626} from "src/feeds/ERC4626Feed.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {PriceFeedNoStale} from "src/feeds/PriceFeedNoStale.sol";
import "forge-std/console2.sol";


contract SINVFeedTest is Test {
    ERC4626Feed vaultFeed;
    PriceFeedNoStale priceFeed;

    IERC4626 sInv = IERC4626(0x08d23468A467d2bb86FaE0e32F247A26C7E2e994);
    ChainlinkBasePriceFeed invToUsd = ChainlinkBasePriceFeed(0x54F1E4EB93c5b5F4C12776c96e08a49A9928FE84);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        vaultFeed = new ERC4626Feed(address(sInv), address(invToUsd));
        priceFeed = new PriceFeedNoStale(address(vaultFeed));
    }

    function test_sINV_Feed() public {
        uint256 exchangeRate = sInv.previewRedeem(1e18);
        uint256 invPrice = uint(invToUsd.latestAnswer());
        uint256 sInvToUsd = exchangeRate * invPrice / 1e18;
        assertEq(sInvToUsd, uint(vaultFeed.latestAnswer()));
        assertEq(sInvToUsd, uint(priceFeed.latestAnswer())); 
        console2.log(uint(vaultFeed.latestAnswer()));
    }

    function test_feedNoStale() public {
        assertEq(vaultFeed.latestAnswer(), priceFeed.latestAnswer());
        (,int price, , uint updateAt,) = priceFeed.latestRoundData();
        assertEq(updateAt, block.timestamp);
        assertEq(price, vaultFeed.latestAnswer());
        console2.log(priceFeed.description());
    }
}