// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {DolaCurveLPPessimsticFeedBaseTest} from "test/feedForkTests/DolaCurveLPPessimsticFeedBaseTest.t.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";
import {ERC4626Feed} from "src/feeds/ERC4626Feed.sol";

contract DolaFxSAVEUSDFeedFork is DolaCurveLPPessimsticFeedBaseTest, ConfigAddr {
    address clUSDCFeed = address(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);
    uint256 usdcHeartbeat = 86400;
    address usdcWrapper = address(0x5B4e043d614809A4b240Ed4Be7D1589f7871a749);
    address usdcFxUSDPool = address(0x5018BE882DccE5E3F2f3B0913AE2096B9b3fB61f);
    uint256 k = 0;
    uint256 targetIndex = 1;
    ICurvePool public constant dolaFxSave =
        ICurvePool(0x2b854e225d7282854819327D0CA5b8D8AA8CAaED); 
    
    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        // USDC/USD * fxUSD/USDC => fxUSD/USD
        ChainlinkCurveFeed fxUSDFeed = new ChainlinkCurveFeed(usdcWrapper, usdcFxUSDPool, k, targetIndex);

        init(address(0), address(fxUSDFeed), address(dolaFxSave));
    }
}
