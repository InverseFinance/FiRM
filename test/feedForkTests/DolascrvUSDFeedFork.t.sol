// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {DolaCurveLPPessimsticFeedBaseTest} from "test/feedForkTests/DolaCurveLPPessimsticFeedBaseTest.t.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";

contract DolascrvUSDFeedFork is DolaCurveLPPessimsticFeedBaseTest, ConfigAddr {
    address clCrvUSDFeed = address(0xEEf0C605546958c1f899b6fB336C20671f9cD49F);
    uint256 crvUSDHeartbeat = 86400;
    ICurvePool public constant dolascrvUSD =
        ICurvePool(0xff17dAb22F1E61078aBa2623c89cE6110E878B3c);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21286315);

        ChainlinkBasePriceFeed scrvUSDFeed = new ChainlinkBasePriceFeed(
            gov,
            clCrvUSDFeed,
            address(0),
            crvUSDHeartbeat
        );
        init(address(0), address(scrvUSDFeed), address(dolascrvUSD));
    }
}
