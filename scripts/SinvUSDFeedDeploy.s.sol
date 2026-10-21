// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ClampedPriceFeed} from "src/feeds/ClampedPriceFeed.sol";
import {ERC4626Feed} from "src/feeds/ERC4626Feed.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";

contract SinvUSDFeedDeploy is Script {
    error UnderlyingMismatch(address poolCoin, address vaultAsset);
    error InvalidPrice(address feed, int256 price);

    address internal constant CURVE_POOL = 0xe430e64081a3E7a39D24c5f507D9d4b492b2ED52;
    address internal constant SINVUSD_VAULT = 0x3FF361197036Ae1d24B939146D8a449A80F8427d;
    address internal constant DOLA_USD_FEED = 0xE33592594f72Cc7ec8a05788be8E8455746C3a32;

    int256 internal constant DOLA_USD_CLAMP_PRICE = 1e18;
    uint256 internal constant INVUSD_ORACLE_INDEX = 0;
    uint256 internal constant INVUSD_TARGET_INDEX = 1;

    function run()
        external
        returns (ClampedPriceFeed dolaUsdFeed, ChainlinkCurveFeed invUsdFeed, ERC4626Feed sinvUsdFeed)
    {
        vm.createSelectFork(vm.envString("RPC_MAINNET"));

        address poolCoin = ICurvePool(CURVE_POOL).coins(INVUSD_TARGET_INDEX);
        address vaultAsset = IERC4626(SINVUSD_VAULT).asset();
        if (poolCoin != vaultAsset) {
            revert UnderlyingMismatch(poolCoin, vaultAsset);
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        dolaUsdFeed = new ClampedPriceFeed(DOLA_USD_FEED, DOLA_USD_CLAMP_PRICE);
        invUsdFeed = new ChainlinkCurveFeed(address(dolaUsdFeed), CURVE_POOL, INVUSD_ORACLE_INDEX, INVUSD_TARGET_INDEX);
        sinvUsdFeed = new ERC4626Feed(SINVUSD_VAULT, address(invUsdFeed));

        vm.stopBroadcast();

        int256 dolaUsdPrice = dolaUsdFeed.latestAnswer();
        if (dolaUsdPrice <= 0) {
            revert InvalidPrice(address(dolaUsdFeed), dolaUsdPrice);
        }

        int256 invUsdPrice = invUsdFeed.latestAnswer();
        if (invUsdPrice <= 0) {
            revert InvalidPrice(address(invUsdFeed), invUsdPrice);
        }

        int256 sinvUsdPrice = sinvUsdFeed.latestAnswer();
        if (sinvUsdPrice <= 0) {
            revert InvalidPrice(address(sinvUsdFeed), sinvUsdPrice);
        }

        console2.log("Clamped DOLA/USD feed deployed to", address(dolaUsdFeed));
        console2.log("invUSD feed deployed to", address(invUsdFeed));
        console2.log("sinvUSD feed deployed to", address(sinvUsdFeed));
        console2.log("DOLA/USD answer:");
        console2.logInt(dolaUsdPrice);
        console2.log("invUSD/USD answer:");
        console2.logInt(invUsdPrice);
        console2.log("sinvUSD/USD answer:");
        console2.logInt(sinvUsdPrice);
    }
}
