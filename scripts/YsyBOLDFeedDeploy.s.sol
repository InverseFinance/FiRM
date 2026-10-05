// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ClampedPriceFeed} from "src/feeds/ClampedPriceFeed.sol";
import {ERC4626Feed} from "src/feeds/ERC4626Feed.sol";
import {IChainlinkFeed} from "src/interfaces/IChainlinkFeed.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";

contract YsyBOLDFeedDeploy is Script {
    error PoolCoinMismatch(uint256 index, address actual, address expected);
    error VaultAssetMismatch(address vault, address actual, address expected);
    error FeedDecimalsMismatch(address feed, uint8 actual, uint8 expected);
    error InvalidPrice(address feed, int256 price);
    error InvalidClampedPrice(int256 rawPrice, int256 clampedPrice);

    address internal constant GOV = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address internal constant CHAINLINK_USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address internal constant USDC_USD_FALLBACK_FEED = 0x9d2ed98AC6e72Fc826407F9DE01c8725657B93A2;

    address internal constant BOLD_USDC_POOL = 0xEFc6516323FbD28e80B85A497B65A86243a54B3E;
    address internal constant BOLD = 0x6440f144b7e50D6a8439336510312d2F54beB01D;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant YBOLD = 0x9F4330700a36B29952869fac9b33f45EEdd8A3d8;
    address internal constant YSYBOLD = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;

    uint256 internal constant BOLD_ORACLE_INDEX = 0;
    uint256 internal constant BOLD_TARGET_INDEX = 0;
    uint256 internal constant USDC_POOL_INDEX = 1;
    uint256 internal constant USDC_USD_HEARTBEAT = 24 hours;
    uint8 internal constant CHAINLINK_USDC_USD_DECIMALS = 8;
    int256 internal constant BOLD_MAX_PRICE = 1e18;

    function run()
        external
        returns (
            ChainlinkBasePriceFeed usdcUsdFeed,
            ChainlinkCurveFeed rawBoldUsdFeed,
            ClampedPriceFeed clampedBoldUsdFeed,
            ERC4626Feed yBoldUsdFeed,
            ERC4626Feed ysyBoldUsdFeed
        )
    {
        vm.createSelectFork(vm.envString("RPC_MAINNET"));

        _validateConfiguration();

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        (usdcUsdFeed, rawBoldUsdFeed, clampedBoldUsdFeed, yBoldUsdFeed, ysyBoldUsdFeed) = _deploy();

        vm.stopBroadcast();

        _validateAndLogPrices(usdcUsdFeed, rawBoldUsdFeed, clampedBoldUsdFeed, yBoldUsdFeed, ysyBoldUsdFeed);
    }

    function _deploy()
        internal
        returns (
            ChainlinkBasePriceFeed usdcUsdFeed,
            ChainlinkCurveFeed rawBoldUsdFeed,
            ClampedPriceFeed clampedBoldUsdFeed,
            ERC4626Feed yBoldUsdFeed,
            ERC4626Feed ysyBoldUsdFeed
        )
    {
        usdcUsdFeed = new ChainlinkBasePriceFeed(
            GOV, CHAINLINK_USDC_USD_FEED, USDC_USD_FALLBACK_FEED, USDC_USD_HEARTBEAT
        );
        rawBoldUsdFeed =
            new ChainlinkCurveFeed(address(usdcUsdFeed), BOLD_USDC_POOL, BOLD_ORACLE_INDEX, BOLD_TARGET_INDEX);
        clampedBoldUsdFeed = new ClampedPriceFeed(address(rawBoldUsdFeed), BOLD_MAX_PRICE);
        yBoldUsdFeed = new ERC4626Feed(YBOLD, address(clampedBoldUsdFeed));
        ysyBoldUsdFeed = new ERC4626Feed(YSYBOLD, address(yBoldUsdFeed));
    }

    function _validateConfiguration() internal view {
        ICurvePool curvePool = ICurvePool(BOLD_USDC_POOL);

        address poolBold = curvePool.coins(BOLD_TARGET_INDEX);
        if (poolBold != BOLD) {
            revert PoolCoinMismatch(BOLD_TARGET_INDEX, poolBold, BOLD);
        }

        address poolUsdc = curvePool.coins(USDC_POOL_INDEX);
        if (poolUsdc != USDC) {
            revert PoolCoinMismatch(USDC_POOL_INDEX, poolUsdc, USDC);
        }

        address yBoldAsset = IERC4626(YBOLD).asset();
        if (yBoldAsset != BOLD) {
            revert VaultAssetMismatch(YBOLD, yBoldAsset, BOLD);
        }

        address ysyBoldAsset = IERC4626(YSYBOLD).asset();
        if (ysyBoldAsset != YBOLD) {
            revert VaultAssetMismatch(YSYBOLD, ysyBoldAsset, YBOLD);
        }

        uint8 feedDecimals = IChainlinkFeed(CHAINLINK_USDC_USD_FEED).decimals();
        if (feedDecimals != CHAINLINK_USDC_USD_DECIMALS) {
            revert FeedDecimalsMismatch(CHAINLINK_USDC_USD_FEED, feedDecimals, CHAINLINK_USDC_USD_DECIMALS);
        }
    }

    function _validateAndLogPrices(
        ChainlinkBasePriceFeed usdcUsdFeed,
        ChainlinkCurveFeed rawBoldUsdFeed,
        ClampedPriceFeed clampedBoldUsdFeed,
        ERC4626Feed yBoldUsdFeed,
        ERC4626Feed ysyBoldUsdFeed
    ) internal view {
        int256 usdcUsdPrice = usdcUsdFeed.latestAnswer();
        _validatePrice(address(usdcUsdFeed), usdcUsdPrice);

        int256 rawBoldUsdPrice = rawBoldUsdFeed.latestAnswer();
        _validatePrice(address(rawBoldUsdFeed), rawBoldUsdPrice);

        int256 clampedBoldUsdPrice = clampedBoldUsdFeed.latestAnswer();
        _validatePrice(address(clampedBoldUsdFeed), clampedBoldUsdPrice);

        int256 expectedClampedPrice = rawBoldUsdPrice > BOLD_MAX_PRICE ? BOLD_MAX_PRICE : rawBoldUsdPrice;
        if (clampedBoldUsdPrice != expectedClampedPrice) {
            revert InvalidClampedPrice(rawBoldUsdPrice, clampedBoldUsdPrice);
        }

        int256 yBoldUsdPrice = yBoldUsdFeed.latestAnswer();
        _validatePrice(address(yBoldUsdFeed), yBoldUsdPrice);

        int256 ysyBoldUsdPrice = ysyBoldUsdFeed.latestAnswer();
        _validatePrice(address(ysyBoldUsdFeed), ysyBoldUsdPrice);

        console2.log("Normalized USDC/USD feed deployed to", address(usdcUsdFeed));
        console2.log("Raw BOLD/USD feed deployed to", address(rawBoldUsdFeed));
        console2.log("Clamped BOLD/USD feed deployed to", address(clampedBoldUsdFeed));
        console2.log("yBOLD/USD feed deployed to", address(yBoldUsdFeed));
        console2.log("ysyBOLD/USD feed deployed to", address(ysyBoldUsdFeed));
        console2.log("USDC/USD answer:");
        console2.logInt(usdcUsdPrice);
        console2.log("Raw BOLD/USD answer:");
        console2.logInt(rawBoldUsdPrice);
        console2.log("Clamped BOLD/USD answer:");
        console2.logInt(clampedBoldUsdPrice);
        console2.log("yBOLD/USD answer:");
        console2.logInt(yBoldUsdPrice);
        console2.log("ysyBOLD/USD answer:");
        console2.logInt(ysyBoldUsdPrice);
    }

    function _validatePrice(address feed, int256 price) internal pure {
        if (price <= 0) revert InvalidPrice(feed, price);
    }
}
