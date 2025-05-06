// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";
import "forge-std/console.sol";

contract InvFeedV2Test is Test, ConfigAddr {
    ChainlinkCurve2CoinsFeed feed;
    ChainlinkBasePriceFeed ethUsdWrapper;
    address invEth = address(0x6bD88c57523bF138A19b263E8ebC8661c836B171);
    address ethUsdClFeed = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    uint256 invIndex = 1; //targetIndex
    uint256 ethUsdHeartbeat = 1 hours;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        ethUsdWrapper = new ChainlinkBasePriceFeed(
            gov,
            ethUsdClFeed,
            address(0),
            ethUsdHeartbeat
        );
        feed = new ChainlinkCurve2CoinsFeed(
            address(ethUsdWrapper),
            invEth,
            invIndex
        );
    }

    function test_deployment() public {
        assertEq(address(feed.assetToUsd()), address(ethUsdWrapper));
        assertEq(address(feed.curvePool()), invEth);
        assertEq(feed.targetIndex(), invIndex);
        assertEq(feed.decimals(), 18);
        assertEq(address(ethUsdWrapper.assetToUsd()), ethUsdClFeed);
        assertEq(ethUsdWrapper.assetToUsdHeartbeat(), ethUsdHeartbeat);
        assertEq(ethUsdWrapper.decimals(), 18);
    }
    function test_description() public {
        string memory expected = "INV / USD";
        string memory actual = feed.description();
        assertEq(expected, actual);

        assertEq(ethUsdWrapper.description(), "ETH / USD");
    }

    function test_latestRoundData() public {
        (
            uint80 roundId,
            int256 invUsdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        (
            uint80 roundIdCl,
            int256 ethUsdPrice,
            uint256 startedAtCl,
            uint256 updatedAtCl,
            uint80 answeredInRoundCl
        ) = ethUsdWrapper.latestRoundData();

        uint256 invEthPrice = ICurvePool(invEth).price_oracle();
        assertEq(roundId, roundIdCl);
        assertEq(
            uint(invUsdPrice),
            ((uint(invEthPrice) * uint(ethUsdPrice)) / 1e18)
        );
        assertEq(startedAt, startedAtCl);
        assertEq(updatedAt, updatedAtCl);
        assertEq(answeredInRound, answeredInRoundCl);
    }

    function test_latestAnswer() public {
        int256 invUsdPrice = feed.latestAnswer();
        int256 ethUsdPrice = ethUsdWrapper.latestAnswer();
        uint256 invEthPrice = ICurvePool(invEth).price_oracle();
        assertEq(
            uint(invUsdPrice),
            (uint(invEthPrice) * uint(ethUsdPrice)) / 1e18
        );
    }
}
