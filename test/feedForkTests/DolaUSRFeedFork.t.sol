// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {DolaCurveLPPessimsticFeedBaseTest} from "test/feedForkTests/DolaCurveLPPessimsticFeedBaseTest.t.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";

contract DolaUSRFeedFork is DolaCurveLPPessimsticFeedBaseTest, ConfigAddr {
    address clUSRFeed = address(0x34ad75691e25A8E9b681AAA85dbeB7ef6561B42c);
    uint256 usrHeartbeat = 86400;

    ICurvePool public constant dolaUSR =
        ICurvePool(0x38De22a3175708D45E7c7c64CD78479C8B56f76E);

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21969468);

        ChainlinkBasePriceFeed usrFeed = new ChainlinkBasePriceFeed(
            gov,
            clUSRFeed,
            address(0),
            usrHeartbeat
        );
        init(address(0), address(usrFeed), address(dolaUSR));
    }
}
