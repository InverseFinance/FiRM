// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";
import {ERC4626Feed, IERC4626} from "src/feeds/ERC4626Feed.sol";

import "forge-std/console.sol";

contract SInvFeedTest is Test, ConfigAddr {
    ChainlinkBasePriceFeed ethUsdWrapper = ChainlinkBasePriceFeed(
        0x22390B88C53D1631f673b8Dcd91860267137b2c8
    );
    ERC4626Feed sInvFeed;
    ChainlinkBasePriceFeed sInvUsdWrapper;
    address ethUsdClFeed = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    uint256 ethUsdHeartbeat = 1 hours;
    address sInv = 0x08d23468A467d2bb86FaE0e32F247A26C7E2e994;
    address invToUsd = 0x4C871E951228c2f7224416C921e742a86Ef8EECB;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
     
        sInvFeed = new ERC4626Feed(
            sInv,
            invToUsd
        );
    }

    function test_deployment() public {
        assertEq(address(sInvFeed.vault()), address(sInv));
        assertEq(address(sInvFeed.feed()), invToUsd);
        assertEq(sInvFeed.decimals(), 18);
        assertEq(address(ethUsdWrapper.assetToUsd()), ethUsdClFeed);
        assertEq(ethUsdWrapper.assetToUsdHeartbeat(), ethUsdHeartbeat +60);
        assertEq(ethUsdWrapper.decimals(), 18);
    }
    function test_description() public {
        string memory expected = "INV / USD using sINV vault rate";
        string memory actual = sInvFeed.description();
        assertEq(expected, actual);

        assertEq(ethUsdWrapper.description(), "ETH / USD");
    }

    function test_latestRoundData() public {
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

        uint256 invUsdPrice = uint(ChainlinkBasePriceFeed(invToUsd)
            .latestAnswer());
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

    function test_latestAnswer() public {
        int256 sInvUsdPrice = sInvFeed.latestAnswer();
        uint256 invUsdPrice = uint(ChainlinkBasePriceFeed(invToUsd)
            .latestAnswer());
        assertEq(
            uint(sInvUsdPrice),
            (invUsdPrice * IERC4626(sInv).convertToAssets(1e18) / 1e18)
        );
    }
}
