// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {DolaCurveLPPessimsticFeedBaseTest} from "test/feedForkTests/DolaCurveLPPessimsticFeedBaseTest.t.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";

contract DolasUSDeFeedFork is DolaCurveLPPessimsticFeedBaseTest, ConfigAddr {
    ChainlinkBasePriceFeed sUSDeFeed =
        ChainlinkBasePriceFeed(0x6277cB27232F35C75D3d908b26F3670e7d167400);

    ICurvePool public constant dolasUSDe =
        ICurvePool(0x744793B5110f6ca9cC7CDfe1CE16677c3Eb192ef);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21236794);

        init(address(0), address(sUSDeFeed), address(dolasUSDe));
    }
}
