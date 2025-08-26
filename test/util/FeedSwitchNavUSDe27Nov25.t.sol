// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {FeedSwitch, IChainlinkFeed} from "src/util/FeedSwitch.sol";
import {BaseFeedSwitchNavForkTest} from "test/util/BaseFeedSwitchNavFork.t.sol";
import {NavBeforeMaturityFeed} from "src/feeds/NavBeforeMaturityFeed.sol";
import {PendleNAVFeed} from "src/feeds/PendleNAVFeed.sol";
import {console2} from "forge-std/console2.sol";

contract FeedSwitchNavUSDe27Nov25Test is BaseFeedSwitchNavForkTest {
    address usdeWrapper = address(0xB3C1D801A02d88adC96A294123c2Daa382345058);
    NavBeforeMaturityFeed _beforeMaturityFeed;
    address _afterMaturityFeed = address(0xB3C1D801A02d88adC96A294123c2Daa382345058); // USDe Chainlink Wrapper
    address _pendlePT = address(0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7); // PT USDe 27 Nov 25
    uint256 _baseDiscount = 0.22 ether; // 22% 

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        PendleNAVFeed _navFeed = new PendleNAVFeed(_pendlePT, _baseDiscount);
        _beforeMaturityFeed = new NavBeforeMaturityFeed(usdeWrapper,address(_navFeed)); // USDeBeforeMaturityFeed: USDe/USD Feed using USDe Chainlink wrapper and NAV

        initialize(address(_beforeMaturityFeed), address(_afterMaturityFeed), _pendlePT , _baseDiscount, address(_navFeed));
    }
}