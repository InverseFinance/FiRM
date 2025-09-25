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

contract DolaWstUSRUSDFeedFork is DolaCurveLPPessimsticFeedBaseTest, ConfigAddr {
    ICurvePool public constant dolawstUSR =
        ICurvePool(0x64273624eb57c5cA961d366CBF3968e760Bf0452); 
    address usrWrapper = address(0x182Af82E3619D2182b3669BbFA8C72bC57614aDf);
    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        init(address(0), address(usrWrapper), address(dolawstUSR));
    }
}
