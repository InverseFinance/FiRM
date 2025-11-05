// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MarketBaseForkTest, IOracle, IDolaBorrowingRights, IERC20} from "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";

import {FXNConvexEscrow} from "src/escrows/FXNConvexEscrow.sol";
import {CurveLPPessimisticFeed} from "src/feeds/CurveLPPessimisticFeed.sol";
import {ChainlinkCurve2CoinsFeed, ICurvePool} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {console} from "forge-std/console.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";
import {DolaFixedPriceFeed} from "src/feeds/DolaFixedPriceFeed.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {MockFeedDescription} from "test/mocks/MockFeedDescription.sol";

contract DolaFxSaveConvexMarketForkTest is MarketBaseForkTest {
    FXNConvexEscrow escrow;

    CurveLPPessimisticFeed feedDolaFxSave;

    ICurvePool public constant dolaFxSavePool =
        ICurvePool(0x2b854e225d7282854819327D0CA5b8D8AA8CAaED);

    address usdcWrapper = address(0x5B4e043d614809A4b240Ed4Be7D1589f7871a749);
    address usdcFxUSDPool = address(0x5018BE882DccE5E3F2f3B0913AE2096B9b3fB61f);
    uint256 k = 0;
    uint256 targetIndex = 1;

    address booster = address(0xAffe966B27ba3E4Ebb8A0eC124C7b7019CC762f8);
    IERC20 fxn = IERC20(0x365AccFCa291e7D3914637ABf1F7635dB165Bb09);
    uint256 pid  = 43;
    FXNConvexEscrow userEscrow;

    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        escrow = new FXNConvexEscrow(
            booster,
            address(fxn),
            pid
        );
        feedDolaFxSave = _deployDolaFxSaveFeed();
        market = new Market(
            gov,
            fedAddr,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbrAddr)),
            IERC20(address(dolaFxSavePool)),
            IOracle(address(oracleAddr)),
            5000,
            5000,
            100,
            true
        );
        _advancedInit(address(market), address(feedDolaFxSave), true);

        userEscrow = FXNConvexEscrow(
            address(Market(address(market)).predictEscrow(user))
        );
    }

    function _deployDolaFxSaveFeed()
        internal
        returns (CurveLPPessimisticFeed feed)
    {
        // USDC/USD * fxUSD/USDC => fxUSD/USD
        ChainlinkCurveFeed fxUSDFeed = new ChainlinkCurveFeed(usdcWrapper, usdcFxUSDPool, k, targetIndex);
        
        feed = new CurveLPPessimisticFeed(
            address(dolaFxSavePool),
            address(fxUSDFeed),
            address(dolaFixedFeedAddr),
            false
        );
    }
}
