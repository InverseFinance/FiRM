// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ClampedPriceFeed} from "src/feeds/ClampedPriceFeed.sol";
import {MockFeedDescription} from "test/mocks/MockFeedDescription.sol";

contract ClampedPriceFeedTest is Test {
    int256 internal constant CLAMP_PRICE = 1e18;

    MockFeedDescription internal sourceFeed;
    ClampedPriceFeed internal clampedFeed;

    function setUp() public {
        sourceFeed = new MockFeedDescription(8, 99_607_083, "DOLA / USD");
        clampedFeed = new ClampedPriceFeed(address(sourceFeed), CLAMP_PRICE);
    }

    function test_constructor() public view {
        assertEq(address(clampedFeed.feed()), address(sourceFeed));
        assertEq(clampedFeed.feedDecimals(), 8);
        assertEq(clampedFeed.scale(), 1e10);
        assertEq(clampedFeed.clampPrice(), CLAMP_PRICE);
        assertEq(clampedFeed.decimals(), 18);
        assertEq(clampedFeed.description(), "Clamped DOLA / USD");
    }

    function test_latestRoundData_normalizesPriceBelowClampAndPreservesMetadata() public {
        vm.warp(2 hours);
        uint256 updatedAt = block.timestamp - 1 hours;
        sourceFeed.changeUpdatedAt(updatedAt);

        (uint80 roundId, int256 price, uint256 startedAt, uint256 returnedUpdatedAt, uint80 answeredInRound) =
            clampedFeed.latestRoundData();

        assertEq(roundId, 0);
        assertEq(price, 996_070_830_000_000_000);
        assertEq(startedAt, 0);
        assertEq(returnedUpdatedAt, updatedAt);
        assertEq(answeredInRound, 0);
    }

    function test_latestRoundData_clampsPriceAboveClamp() public {
        sourceFeed.changeAnswer(101_000_000);

        (, int256 price,,,) = clampedFeed.latestRoundData();

        assertEq(price, CLAMP_PRICE);
    }

    function test_latestRoundData_preservesPriceEqualToClamp() public {
        sourceFeed.changeAnswer(100_000_000);

        (, int256 price,,,) = clampedFeed.latestRoundData();

        assertEq(price, CLAMP_PRICE);
    }

    function test_latestRoundData_preservesNegativePrice() public {
        MockFeedDescription negativeSourceFeed = new MockFeedDescription(8, -1, "DOLA / USD");
        ClampedPriceFeed negativeClampedFeed = new ClampedPriceFeed(address(negativeSourceFeed), CLAMP_PRICE);

        (, int256 price,,,) = negativeClampedFeed.latestRoundData();

        assertEq(price, -1e10);
    }

    function test_latestAnswer_matchesLatestRoundData() public view {
        (, int256 price,,,) = clampedFeed.latestRoundData();
        assertEq(clampedFeed.latestAnswer(), price);
    }

    function test_constructor_revertsForZeroAddress() public {
        vm.expectRevert(ClampedPriceFeed.ZeroAddress.selector);
        new ClampedPriceFeed(address(0), CLAMP_PRICE);
    }

    function test_constructor_revertsForZeroClampPrice() public {
        vm.expectRevert(abi.encodeWithSelector(ClampedPriceFeed.InvalidClampPrice.selector, 0));
        new ClampedPriceFeed(address(sourceFeed), 0);
    }

    function test_constructor_revertsForNegativeClampPrice() public {
        vm.expectRevert(abi.encodeWithSelector(ClampedPriceFeed.InvalidClampPrice.selector, -1));
        new ClampedPriceFeed(address(sourceFeed), -1);
    }

    function test_constructor_revertsForMoreThan18Decimals() public {
        MockFeedDescription unsupportedFeed = new MockFeedDescription(19, 1, "Unsupported");

        vm.expectRevert(abi.encodeWithSelector(ClampedPriceFeed.UnsupportedFeedDecimals.selector, 19));
        new ClampedPriceFeed(address(unsupportedFeed), CLAMP_PRICE);
    }
}
