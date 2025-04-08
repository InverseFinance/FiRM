// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {DolaCurveLPPessimsticFeedBaseTest} from "test/feedForkTests/DolaCurveLPPessimsticFeedBaseTest.t.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";

contract DolaDeUSDFeedFork is DolaCurveLPPessimsticFeedBaseTest, ConfigAddr {
    address clDeUSDFeed = address(0x471a6299C027Bd81ed4D66069dc510Bd0569f4F8);
    uint256 deUSDHeartbeat = 86400;

    ICurvePool public constant dolaDeUSD =
        ICurvePool(0x6691DBb44154A9f23f8357C56FC9ff5548A8bdc4);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21826229);

        ChainlinkBasePriceFeed deUSDFeed = new ChainlinkBasePriceFeed(
            gov,
            clDeUSDFeed,
            address(0),
            deUSDHeartbeat
        );
        init(address(0), address(deUSDFeed), address(dolaDeUSD));
    }
}
