// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FeedSwitch} from "src/util/FeedSwitch.sol";
import {USDeNavBeforeMaturityFeed} from "src/feeds/USDeNavBeforeMaturityFeed.sol";
import {NavBeforeMaturityFeed} from "src/feeds/NavBeforeMaturityFeed.sol";
import {PendleNAVFeed} from "src/feeds/PendleNAVFeed.sol";

contract PTUSDeFeedSwitchFactory {
    address public constant USDeWrapperFeed = 0xB3C1D801A02d88adC96A294123c2Daa382345058;
    address public constant sUSDeWrapper = address(0xD723a0910e261de49A90779d38A94aFaAA028F15);
    address public constant sUSDe = address(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    uint256 public constant timelockPeriod = 64800;
    address public constant guardian = 0x4b6c63E6a94ef26E2dF60b89372db2d8e211F1B7;

    mapping(address => bool) public isFromFactory;

    event NewFeedSwitch(
        address pendlePT, address feedSwitch, address navFeed, address beforeMaturityFeed, address afterMaturityFeed
    );

    function deployUSDeFeed(address pendlePT, uint256 baseDiscount) external returns (address feedSwitch) {
        PendleNAVFeed navFeed = new PendleNAVFeed(pendlePT, baseDiscount);

        NavBeforeMaturityFeed beforeMaturityFeed = new NavBeforeMaturityFeed(USDeWrapperFeed, address(navFeed));

        feedSwitch = address(
            new FeedSwitch(
                address(navFeed), address(beforeMaturityFeed), USDeWrapperFeed, timelockPeriod, pendlePT, guardian
            )
        );
        isFromFactory[feedSwitch] = true;

        emit NewFeedSwitch(pendlePT, feedSwitch, address(navFeed), address(beforeMaturityFeed), USDeWrapperFeed);
    }

    function deploySUSDeFeed(address pendlePT, uint256 baseDiscount) external returns (address feedSwitch) {
        PendleNAVFeed navFeed = new PendleNAVFeed(pendlePT, baseDiscount);

        USDeNavBeforeMaturityFeed beforeMaturityFeed =
            new USDeNavBeforeMaturityFeed(sUSDeWrapper, sUSDe, address(navFeed)); // USDeBeforeMaturityFeed: USDe/USD Feed using sUSDe Chainlink feed and sUSDe/USDe rate and NAV

        feedSwitch = address(
            new FeedSwitch(
                address(navFeed), address(beforeMaturityFeed), USDeWrapperFeed, timelockPeriod, pendlePT, guardian
            )
        );

        isFromFactory[feedSwitch] = true;

        emit NewFeedSwitch(pendlePT, feedSwitch, address(navFeed), address(beforeMaturityFeed), USDeWrapperFeed);
    }
}
