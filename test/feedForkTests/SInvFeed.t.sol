// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";
import {ERC4626Feed, IERC4626} from "src/feeds/ERC4626Feed.sol";
import {NormalizedPriceFeed} from "src/feeds/NormalizedPriceFeed.sol";
import {DynamicFeeCurveFeed} from "src/feeds/DynamicFeeCurveFeed.sol";
import "forge-std/console.sol";

contract SInvFeedTest is Test, ConfigAddr {
    ERC4626Feed sInvFeed;
    NormalizedPriceFeed ethUsdWrapper;
    DynamicFeeCurveFeed invToUsd;
    
    address ethUsdClFeed = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    uint256 ethUsdHeartbeat = 1 hours;
    address sInv = 0x08d23468A467d2bb86FaE0e32F247A26C7E2e994;
    address curvePool = 0xDcD90D866Ff9636e5a04768825d05d27b3Fb19eC;
    address inv = 0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68;
   
   
    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        ethUsdWrapper = new NormalizedPriceFeed(
            ethUsdClFeed,
            address(0),
            ethUsdHeartbeat
        );

        invToUsd = new DynamicFeeCurveFeed(
            address(ethUsdWrapper),
            curvePool,
            inv, 
            gov
        );

        sInvFeed = new ERC4626Feed(
            sInv,
            address(invToUsd)
        );
    }

    function test_deployment() public view{
        assertEq(address(sInvFeed.vault()), address(sInv));
        assertEq(address(sInvFeed.feed()), address(invToUsd));
        assertEq(sInvFeed.decimals(), 18);
        assertEq(address(ethUsdWrapper.assetToUsd()), ethUsdClFeed);
        assertEq(ethUsdWrapper.assetToUsdHeartbeat(), ethUsdHeartbeat);
        assertEq(ethUsdWrapper.decimals(), 18);
    }

    function test_description() public view {
        string memory expected = "INV / USD using sINV vault rate";
        string memory actual = sInvFeed.description();
        assertEq(expected, actual);

        assertEq(ethUsdWrapper.description(), "ETH / USD");
    }

    function test_latestRoundData() public view {
        (
            uint80 roundId,
            int256 sInvUsdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = sInvFeed.latestRoundData();

        (
            uint80 roundIdCl,
            int256 ethUsdPrice,
            uint256 startedAtCl,
            uint256 updatedAtCl,
            uint80 answeredInRoundCl
        ) = ethUsdWrapper.latestRoundData();

        uint256 invUsdPrice = uint(invToUsd.latestAnswer());
        assertEq(roundId, roundIdCl);
        assertEq(
            uint(sInvUsdPrice),
            (invUsdPrice * IERC4626(sInv).convertToAssets(1e18) / 1e18)
        );
        assertEq(startedAt, startedAtCl);
        assertEq(updatedAt, updatedAtCl);
        assertEq(answeredInRound, answeredInRoundCl);
        console.log("sINV/USD Price:", uint(sInvUsdPrice));
    }

    function test_latestAnswer() public view {
        int256 sInvUsdPrice = sInvFeed.latestAnswer();
        uint256 invUsdPrice = uint(invToUsd.latestAnswer());
          
        assertEq(
            uint(sInvUsdPrice),
            (invUsdPrice * IERC4626(sInv).convertToAssets(1e18) / 1e18)
        );
    }

    function test_stale_feed_doesnt_return_zero_updatedAt() public {
        (
            ,
            ,
            ,
            uint256 updatedAtBefore,
            ) = sInvFeed.latestRoundData();

        
        vm.warp(block.timestamp + 24 hours);
        (
            ,
            ,
            ,
            uint256 updatedAt,
            
        ) = sInvFeed.latestRoundData();

        assertEq(updatedAt, updatedAtBefore,"should not be zero"); 
    }
}
