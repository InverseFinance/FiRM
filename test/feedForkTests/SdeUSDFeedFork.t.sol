// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ERC4626Feed.sol";
import "src/interfaces/IChainlinkFeed.sol";
import {ChainlinkCurveFeed, ICurvePool} from "src/feeds/ChainlinkCurveFeed.sol";
import "forge-std/console.sol";

contract SdeUSDFeedForkTest is Test {
    ChainlinkCurveFeed curveFeed;
    ERC4626Feed feed;
    address curvePool = address(0x82202CAEC5E6d85014eADC68D4912F3C90093e7C);
    uint256 k = 0;
    uint256 targetIndex = 1;
    address sdeUSD = address(0x5C5b196aBE0d54485975D1Ec29617D42D9198326);
    address dolaFeed = address(0x6255981e2a1EBeA600aFC506185590eD383517be);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        curveFeed = new ChainlinkCurveFeed(dolaFeed, curvePool, k, targetIndex);
        feed = new ERC4626Feed(sdeUSD, address(curveFeed));
    }

    function test_decimals() public {
        assertEq(feed.decimals(), 18);
    }

    function test_description() public {
        assertEq(feed.description(), "sdeUSD / USD using sdeUSD vault rate");
    }

    function test_latestRoundData() public {
        (
            uint80 roundId,
            int256 sdeUSDToUsdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        assertEq(feed.latestAnswer(), _calculateSdeUSDPrice());
        (
            uint80 roundId2,
            ,
            uint256 startedAt2,
            uint256 updatedAt2,
            uint80 answeredInRound2
        ) = IChainlinkBasePriceFeed(dolaFeed).latestRoundData();
        // Data are
        assertEq(roundId, roundId2);
        assertEq(sdeUSDToUsdPrice, _calculateSdeUSDPrice());
        assertEq(startedAt, startedAt2);
        assertEq(updatedAt, updatedAt2);
        assertEq(answeredInRound, answeredInRound2);
    }

    function test_sdeUSD_upward_depeg() public {
        int256 answer = feed.latestAnswer();
        assertEq(feed.latestAnswer(), _calculateSdeUSDPrice());
        uint256 mockRate = 2e18;
        _mockVaultRate(sdeUSD, mockRate);
        assertEq(feed.latestAnswer(), _calculateSdeUSDPrice());
        assertGt(feed.latestAnswer(), answer);
    }

    function test_sdeUSD_downward_depeg() public {
        int256 answer = feed.latestAnswer();
        assertEq(feed.latestAnswer(), _calculateSdeUSDPrice());
        uint256 mockRate = 0.5e18;
        _mockVaultRate(sdeUSD, mockRate);
        assertEq(feed.latestAnswer(), _calculateSdeUSDPrice());
        assertLt(feed.latestAnswer(), answer);
    }

    function _calculateSdeUSDPrice() internal view returns (int256) {
        uint256 sdeUSDNormalizedToDola = ICurvePool(curvePool).price_oracle(
            curveFeed.assetOrTargetK()
        );

        int256 dolaToUsdPrice = curveFeed.assetToUsd().latestAnswer();
        int256 sdeUSDNormalizedToUsdPrice = int256(
            (sdeUSDNormalizedToDola * uint(dolaToUsdPrice)) / 1e18
        );

        uint256 sdeUSDToDeUSDRate = IERC4626(sdeUSD).previewRedeem(1e18);
        return
            (sdeUSDNormalizedToUsdPrice * int(sdeUSDToDeUSDRate)) /
            int256(1e18);
    }

    function _mockVaultRate(address vault, uint256 mockRate) internal {
        vm.mockCall(
            vault,
            abi.encodeWithSelector(IERC4626.previewRedeem.selector, 1e18),
            abi.encode(mockRate)
        );
    }
}
