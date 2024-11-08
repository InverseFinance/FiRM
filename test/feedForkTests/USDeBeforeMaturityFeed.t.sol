// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {USDeBeforeMaturityFeed} from "src/feeds/USDeBeforeMaturityFeed.sol";
import {ChainlinkBasePriceFeed, IChainlinkFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "forge-std/console.sol";

contract USDeBeforeMaturityFeedTest is Test {
    USDeBeforeMaturityFeed feed;
    ChainlinkBasePriceFeed sUSDeWrappedFeed;
    address sUSDeFeed = address(0xFF3BC18cCBd5999CE63E788A1c250a88626aD099);
    IERC4626 sUSDe = IERC4626(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        sUSDeWrappedFeed = new ChainlinkBasePriceFeed(
            gov,
            sUSDeFeed,
            address(0),
            24 hours
        );
        feed = new USDeBeforeMaturityFeed(
            address(sUSDeWrappedFeed),
            address(sUSDe)
        );
    }

    function test_decimals() public {
        assertEq(feed.sUSDeFeed().decimals(), 18);
        assertEq(feed.sUSDe().decimals(), 18);
        assertEq(feed.decimals(), 18);
    }

    function test_description() public {
        string memory expected = string(
            abi.encodePacked(
                "USDe/USD Feed using sUSDe Chainlink feed and sUSDe/USDe rate"
            )
        );
        assertEq(feed.description(), expected);
    }

    function test_latestRoundData() public {
        (
            uint80 roundId,
            int256 USDeUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        (
            uint80 roundIdCl,
            int256 sUSDeUsdPrice,
            uint startedAtCl,
            uint updatedAtCl,
            uint80 answeredInRoundCl
        ) = sUSDeWrappedFeed.latestRoundData();
        assertEq(roundId, roundIdCl);
        assertEq(startedAt, startedAtCl);
        assertEq(updatedAt, updatedAtCl);
        assertEq(answeredInRound, answeredInRoundCl);

        int256 USDeUsdPriceEst = (sUSDeUsdPrice * 1e18) /
            int256(sUSDe.convertToAssets(1e18));
        assertEq(USDeUsdPriceEst, USDeUsdPrice);
    }

    function test_latestAnswer() public {
        int256 USDeUsdPrice = feed.latestAnswer();
        int256 USDeUsdPriceEst = (sUSDeWrappedFeed.latestAnswer() * 1e18) /
            int256(sUSDe.convertToAssets(1e18));
        assertEq(USDeUsdPriceEst, USDeUsdPrice);
    }

    function test_STALE_sUSDeFeed() public {
        vm.mockCall(
            address(sUSDeFeed),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 1.1e8, 0, 0, 0)
        );
        (
            uint80 roundId,
            int256 USDeUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        int256 USDeUsdPriceEst = (sUSDeWrappedFeed.latestAnswer() * 1e18) /
            int256(sUSDe.convertToAssets(1e18));
        assertEq(roundId, 0);
        assertEq(USDeUsdPrice, USDeUsdPriceEst);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
    }
}
