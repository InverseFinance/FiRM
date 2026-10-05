// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {YsyBOLDFeedDeploy} from "scripts/YsyBOLDFeedDeploy.s.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ClampedPriceFeed} from "src/feeds/ClampedPriceFeed.sol";
import {ERC4626Feed} from "src/feeds/ERC4626Feed.sol";
import {IChainlinkFeed} from "src/interfaces/IChainlinkFeed.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";

contract YsyBOLDFeedDeployHarness is YsyBOLDFeedDeploy {
    function deploy()
        external
        returns (
            ChainlinkBasePriceFeed usdcUsdFeed,
            ChainlinkCurveFeed rawBoldUsdFeed,
            ClampedPriceFeed clampedBoldUsdFeed,
            ERC4626Feed yBoldUsdFeed,
            ERC4626Feed ysyBoldUsdFeed
        )
    {
        _validateConfiguration();
        return _deploy();
    }

    function validateConfiguration() external view {
        _validateConfiguration();
    }
}

contract YsyBOLDFeedForkTest is Test {
    struct RoundData {
        uint80 roundId;
        int256 price;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    address internal constant GOV = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address internal constant CHAINLINK_USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant USDC_USD_FALLBACK_FEED = 0x9d2ed98AC6e72Fc826407F9DE01c8725657B93A2;

    address internal constant BOLD_USDC_POOL = 0xEFc6516323FbD28e80B85A497B65A86243a54B3E;
    address internal constant BOLD = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant YBOLD = 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8;
    address internal constant YSYBOLD = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;

    uint256 internal constant FORK_BLOCK = 25_651_348;
    uint256 internal constant USDC_USD_HEARTBEAT = 24 hours;
    int256 internal constant BOLD_MAX_PRICE = 1e18;

    YsyBOLDFeedDeployHarness internal deployer;
    ChainlinkBasePriceFeed internal usdcUsdFeed;
    ChainlinkCurveFeed internal rawBoldUsdFeed;
    ClampedPriceFeed internal clampedBoldUsdFeed;
    ERC4626Feed internal yBoldUsdFeed;
    ERC4626Feed internal ysyBoldUsdFeed;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), FORK_BLOCK);

        deployer = new YsyBOLDFeedDeployHarness();
        (usdcUsdFeed, rawBoldUsdFeed, clampedBoldUsdFeed, yBoldUsdFeed, ysyBoldUsdFeed) = deployer.deploy();
    }

    function test_configurationAndFeedComposition() public view {
        assertEq(usdcUsdFeed.decimals(), 18);
        assertEq(usdcUsdFeed.owner(), GOV);
        assertEq(usdcUsdFeed.assetToUsdHeartbeat(), USDC_USD_HEARTBEAT);
        assertEq(address(usdcUsdFeed.assetToUsd()), CHAINLINK_USDC_USD_FEED);
        assertEq(address(usdcUsdFeed.assetToUsdFallback()), USDC_USD_FALLBACK_FEED);
        assertEq(usdcUsdFeed.assetToUsdDecimals(), IChainlinkFeed(CHAINLINK_USDC_USD_FEED).decimals());
        assertEq(usdcUsdFeed.assetToUsdFallbackDecimals(), IChainlinkFeed(USDC_USD_FALLBACK_FEED).decimals());

        assertEq(ICurvePool(BOLD_USDC_POOL).coins(0), BOLD);
        assertEq(ICurvePool(BOLD_USDC_POOL).coins(1), USDC);
        assertEq(IERC4626(YBOLD).asset(), BOLD);
        assertEq(IERC4626(YSYBOLD).asset(), YBOLD);

        assertEq(address(rawBoldUsdFeed.assetToUsd()), address(usdcUsdFeed));
        assertEq(address(rawBoldUsdFeed.curvePool()), BOLD_USDC_POOL);
        assertEq(rawBoldUsdFeed.assetOrTargetK(), 0);
        assertEq(rawBoldUsdFeed.targetIndex(), 0);

        assertEq(address(clampedBoldUsdFeed.feed()), address(rawBoldUsdFeed));
        assertEq(clampedBoldUsdFeed.clampPrice(), BOLD_MAX_PRICE);
        assertEq(address(yBoldUsdFeed.feed()), address(clampedBoldUsdFeed));
        assertEq(address(yBoldUsdFeed.vault()), YBOLD);
        assertEq(address(ysyBoldUsdFeed.feed()), address(yBoldUsdFeed));
        assertEq(address(ysyBoldUsdFeed.vault()), YSYBOLD);

        assertEq(rawBoldUsdFeed.decimals(), 18);
        assertEq(clampedBoldUsdFeed.decimals(), 18);
        assertEq(yBoldUsdFeed.decimals(), 18);
        assertEq(ysyBoldUsdFeed.decimals(), 18);

        assertEq(rawBoldUsdFeed.description(), "BOLD / USD");
        assertEq(clampedBoldUsdFeed.description(), "Clamped BOLD / USD");
        assertEq(
            yBoldUsdFeed.description(),
            string.concat("Clamped BOLD / USD using ", IERC20Metadata(YBOLD).symbol(), " vault rate")
        );
        assertEq(
            ysyBoldUsdFeed.description(),
            string.concat(yBoldUsdFeed.description(), " using ", IERC20Metadata(YSYBOLD).symbol(), " vault rate")
        );
    }

    function test_livePricesFollowExpectedComposition() public view {
        RoundData memory usdcData = _roundData(address(usdcUsdFeed));
        RoundData memory rawBoldData = _roundData(address(rawBoldUsdFeed));
        RoundData memory clampedBoldData = _roundData(address(clampedBoldUsdFeed));
        RoundData memory yBoldData = _roundData(address(yBoldUsdFeed));
        RoundData memory ysyBoldData = _roundData(address(ysyBoldUsdFeed));

        int256 expectedRawBoldPrice =
            (usdcData.price * int256(1e18)) / int256(ICurvePool(BOLD_USDC_POOL).price_oracle(0));
        int256 expectedClampedBoldPrice = expectedRawBoldPrice > BOLD_MAX_PRICE ? BOLD_MAX_PRICE : expectedRawBoldPrice;
        int256 expectedYBoldPrice =
            int256((uint256(expectedClampedBoldPrice) * IERC4626(YBOLD).previewRedeem(1e18)) / 1e18);
        int256 expectedYsyBoldPrice =
            int256((uint256(expectedYBoldPrice) * IERC4626(YSYBOLD).previewRedeem(1e18)) / 1e18);

        assertEq(rawBoldData.price, expectedRawBoldPrice);
        assertEq(clampedBoldData.price, expectedClampedBoldPrice);
        assertEq(yBoldData.price, expectedYBoldPrice);
        assertEq(ysyBoldData.price, expectedYsyBoldPrice);
        assertLe(clampedBoldData.price, BOLD_MAX_PRICE);

        _assertMetadataMatches(rawBoldData, usdcData);
        _assertMetadataMatches(clampedBoldData, usdcData);
        _assertMetadataMatches(yBoldData, usdcData);
        _assertMetadataMatches(ysyBoldData, usdcData);

        assertEq(rawBoldUsdFeed.latestAnswer(), rawBoldData.price);
        assertEq(clampedBoldUsdFeed.latestAnswer(), clampedBoldData.price);
        assertEq(yBoldUsdFeed.latestAnswer(), yBoldData.price);
        assertEq(ysyBoldUsdFeed.latestAnswer(), ysyBoldData.price);
    }

    function test_boldClampPropagatesThroughVaultFeeds() public {
        RoundData memory rawData = RoundData({
            roundId: 42, price: 1.05e18, startedAt: block.timestamp - 1, updatedAt: block.timestamp, answeredInRound: 42
        });
        _mockRoundData(address(rawBoldUsdFeed), rawData);

        RoundData memory clampedBoldData = _roundData(address(clampedBoldUsdFeed));
        RoundData memory yBoldData = _roundData(address(yBoldUsdFeed));
        RoundData memory ysyBoldData = _roundData(address(ysyBoldUsdFeed));

        int256 expectedYBoldPrice = int256((uint256(BOLD_MAX_PRICE) * IERC4626(YBOLD).previewRedeem(1e18)) / 1e18);
        int256 expectedYsyBoldPrice =
            int256((uint256(expectedYBoldPrice) * IERC4626(YSYBOLD).previewRedeem(1e18)) / 1e18);

        assertEq(clampedBoldData.price, BOLD_MAX_PRICE);
        assertEq(yBoldData.price, expectedYBoldPrice);
        assertEq(ysyBoldData.price, expectedYsyBoldPrice);

        _assertMetadataMatches(clampedBoldData, rawData);
        _assertMetadataMatches(yBoldData, rawData);
        _assertMetadataMatches(ysyBoldData, rawData);
    }

    function test_validateConfiguration_revertsForWrongPoolCoin() public {
        address wrongCoin = address(1);
        vm.mockCall(BOLD_USDC_POOL, abi.encodeWithSelector(ICurvePool.coins.selector, 0), abi.encode(wrongCoin));

        vm.expectRevert(abi.encodeWithSelector(YsyBOLDFeedDeploy.PoolCoinMismatch.selector, 0, wrongCoin, BOLD));
        deployer.validateConfiguration();
    }

    function test_validateConfiguration_revertsForWrongVaultAsset() public {
        address wrongAsset = address(1);
        vm.mockCall(YBOLD, abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(wrongAsset));

        vm.expectRevert(abi.encodeWithSelector(YsyBOLDFeedDeploy.VaultAssetMismatch.selector, YBOLD, wrongAsset, BOLD));
        deployer.validateConfiguration();
    }

    function test_validateConfiguration_revertsForWrongUsdcFeedDecimals() public {
        uint8 wrongDecimals = 18;
        vm.mockCall(
            CHAINLINK_USDC_USD_FEED, abi.encodeWithSelector(IChainlinkFeed.decimals.selector), abi.encode(wrongDecimals)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                YsyBOLDFeedDeploy.FeedDecimalsMismatch.selector, CHAINLINK_USDC_USD_FEED, wrongDecimals, uint8(8)
            )
        );
        deployer.validateConfiguration();
    }

    function _mockRoundData(address feed, RoundData memory data) internal {
        vm.mockCall(
            feed,
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(data.roundId, data.price, data.startedAt, data.updatedAt, data.answeredInRound)
        );
    }

    function _roundData(address feed) internal view returns (RoundData memory data) {
        (data.roundId, data.price, data.startedAt, data.updatedAt, data.answeredInRound) =
            IChainlinkFeed(feed).latestRoundData();
    }

    function _assertMetadataMatches(RoundData memory actual, RoundData memory expected) internal pure {
        assertEq(actual.roundId, expected.roundId);
        assertEq(actual.startedAt, expected.startedAt);
        assertEq(actual.updatedAt, expected.updatedAt);
        assertEq(actual.answeredInRound, expected.answeredInRound);
    }
}
