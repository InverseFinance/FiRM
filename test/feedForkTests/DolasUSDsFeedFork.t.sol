// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {DolaCurveLPPessimsticFeedBaseTest} from "test/feedForkTests/DolaCurveLPPessimsticFeedBaseTest.t.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";

contract DolasUSDsFeedFork is DolaCurveLPPessimsticFeedBaseTest, ConfigAddr {
    address clDaiFeed = address(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);
    uint256 daiHeartbeat = 3600;
    ICurvePool public constant dolasUSDs =
        ICurvePool(0x8b83c4aA949254895507D09365229BC3a8c7f710);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21236794);

        ChainlinkBasePriceFeed sUSDsFeed = new ChainlinkBasePriceFeed(
            gov,
            clDaiFeed,
            address(0),
            daiHeartbeat
        );
        init(address(0), address(sUSDsFeed), address(dolasUSDs));
    }
}
