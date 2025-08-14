// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {FeedSwitch, IChainlinkFeed} from "src/util/FeedSwitch.sol";
import {BaseFeedSwitchNavForkTest} from "test/util/BaseFeedSwitchNavFork.t.sol";
import {USDeNavBeforeMaturityFeed} from "src/feeds/USDeNavBeforeMaturityFeed.sol";
import {PendleNAVFeed} from "src/feeds/PendleNAVFeed.sol";

contract FeedSwitchNavSUSDe24Sep25Test is BaseFeedSwitchNavForkTest {
    address _beforeMaturityFeed;
    address _afterMaturityFeed = address(0xB3C1D801A02d88adC96A294123c2Daa382345058); // USDe Chainlink Wrapper
    address _pendlePT = address(0x9F56094C450763769BA0EA9Fe2876070c0fD5F77); // PT sUSDe 24 Sep 25
    uint256 _baseDiscount = 0.2 ether; // 20% 
    address sUSDeWrapper = address(0xD723a0910e261de49A90779d38A94aFaAA028F15);
    address sUSDe = address(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
   
    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 22590519);
      
        PendleNAVFeed _navFeed = new PendleNAVFeed(_pendlePT, _baseDiscount);
        _beforeMaturityFeed = address(new USDeNavBeforeMaturityFeed(sUSDeWrapper,sUSDe,address(_navFeed))); // USDeBeforeMaturityFeed: USDe/USD Feed using sUSDe Chainlink feed and sUSDe/USDe rate and NAV
        
        initialize(address(_beforeMaturityFeed), address(_afterMaturityFeed), _pendlePT , _baseDiscount, address(_navFeed));
    }
}
