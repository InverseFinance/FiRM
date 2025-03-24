// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkBridgeAssetFeed} from "src/feeds/ChainlinkBridgeAssetFeed.sol";

abstract contract ChainlinkBridgeAssetBase is Test {
    ChainlinkBridgeAssetFeed feed;
    ChainlinkBasePriceFeed collateralToBridgeAssetFeed; // main coin1 feed
    ChainlinkBasePriceFeed bridgeAssetToUsdFeed; // main coin2 feed

    uint256 public constant SCALE = 1e18;

    function init(
        address _collateralToBridgeAssetFeed,
        address _bridgeAssetToUsdFeed,
        bool _bridgeAssetDenominator
    ) public {
        collateralToBridgeAssetFeed = ChainlinkBasePriceFeed(_collateralToBridgeAssetFeed);
        bridgeAssetToUsdFeed = ChainlinkBasePriceFeed(_bridgeAssetToUsdFeed);
        feed = new ChainlinkBridgeAssetFeed(_collateralToBridgeAssetFeed, _bridgeAssetToUsdFeed, _bridgeAssetDenominator);
        console.log("feed :", feed.description());
    }

    function test_decimals() public {
        assertEq(feed.decimals(), 18);
    }

    function test_latestAnswer() public {
        (, int256 lpUsdPrice, , , ) = feed.latestRoundData();

        assertEq(feed.latestAnswer(), lpUsdPrice);
    }

    function test_collateralToBridgeAssetIncrease() public {
        (,int256 priceBefore,,,) = feed.latestRoundData();

        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
            = collateralToBridgeAssetFeed.latestRoundData();

        _mockLatestRoundData(
            address(collateralToBridgeAssetFeed),
            roundId,
            price * 110 / 100,
            startedAt,
            updatedAt,
            answeredInRound
        );

        (,int256 priceAfter,,,) = feed.latestRoundData();

        if(feed.bridgeAssetDenominator()){
            assertGt(priceAfter, priceBefore);
        } else {
            assertLt(priceAfter, priceBefore);
        }
    }

    function test_collateralToBridgeAssetDecrease() public {
        (,int256 priceBefore,,,) = feed.latestRoundData();

        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
            = collateralToBridgeAssetFeed.latestRoundData();

        _mockLatestRoundData(
            address(collateralToBridgeAssetFeed),
            roundId,
            price * 90 / 100,
            startedAt,
            updatedAt,
            answeredInRound
        );

        (,int256 priceAfter,,,) = feed.latestRoundData();

        if(feed.bridgeAssetDenominator()){
            assertLt(priceAfter, priceBefore);
        } else {
            assertGt(priceAfter, priceBefore);
        }
    }

    function test_bridgeAssetToUsdIncrease() public {
        (,int256 priceBefore,,,) = feed.latestRoundData();

        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
            = collateralToBridgeAssetFeed.latestRoundData();

        _mockLatestRoundData(
            address(bridgeAssetToUsdFeed),
            roundId,
            price * 110 / 100,
            startedAt,
            updatedAt,
            answeredInRound
        );

        (,int256 priceAfter,,,) = feed.latestRoundData();

        assertLt(priceAfter, priceBefore);
    }

    function test_bridgeAssetToUsdDecrease() public {
        (,int256 priceBefore,,,) = feed.latestRoundData();

        (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
            = collateralToBridgeAssetFeed.latestRoundData();

        _mockLatestRoundData(
            address(bridgeAssetToUsdFeed),
            roundId,
            price * 90 / 100,
            startedAt,
            updatedAt,
            answeredInRound
        );

        (,int256 priceAfter,,,) = feed.latestRoundData();

        assertLt(priceAfter, priceBefore);
    }

    function _mockLatestRoundData(
        address target,
        uint80 roundId,
        int256 price,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) internal {
        vm.mockCall(
            target,
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(roundId, price, startedAt, updatedAt, answeredInRound)
        );
    }
}
