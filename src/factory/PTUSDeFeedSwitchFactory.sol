// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FeedSwitch} from "src/util/FeedSwitch.sol";
import {USDeNavBeforeMaturityFeed} from "src/feeds/USDeNavBeforeMaturityFeed.sol";
import {NavBeforeMaturityFeed} from "src/feeds/NavBeforeMaturityFeed.sol";
import {PendleNAVFeed} from "src/feeds/PendleNAVFeed.sol";

contract PTUSDeFeedSwitchFactory {
    address public constant USDeWrapperFeed = 0xB3C1D801A02d88adC96A294123c2Daa382345058;
    address public constant sUSDeWrapper = 0xD723a0910e261de49A90779d38A94aFaAA028F15;
    address public constant sUSDe = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address public gov;
    uint256 public timelockPeriod;
    address public guardian;
    address public pendingGov;

    mapping(address => bool) public isFromFactory;

    event NewFeedSwitch(
        address indexed pendlePT, address indexed feedSwitch, address indexed navFeed, address beforeMaturityFeed, address afterMaturityFeed
    );
    event NewPendingGov(address indexed oldPendingGov, address indexed newPendingGov);
    event NewGov(address indexed oldGov, address indexed newGov);
    event NewTimelockPeriod(uint256 oldTimelockPeriod, uint256 newTimelockPeriod);
    event NewGuardian(address indexed oldGuardian, address indexed newGuardian);

    constructor(address _gov, address _guardian, uint256 _timelockPeriod) {
        gov = _gov;
        guardian = _guardian;
        timelockPeriod = _timelockPeriod;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "Only gov");
        _;
    }

    /**
     * @notice Deploy a new PT USDe feed.
     * @dev The deployed feed has to be set in the oracle for the specific market via on-chain vote.
     * @param pendlePT address of the Pendle PT
     * @param baseDiscount base discount for the feed
     */
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

    /**
     * @notice Deploy a new PT sUSDe feed.
     * @dev The deployed feed has to be set in the oracle for the specific market via on-chain vote.
     * @param pendlePT address of the Pendle PT
     * @param baseDiscount base discount for the feed
     */
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

    // Admin functions
    
    /**
     * @notice Set a new pending gov. The new pending gov then has to call `acceptGov`.
     * @dev Can only be called by the gov.
     * @param _pendingGov address of the new pending gov
     */
    function setPendingGov(address _pendingGov) external onlyGov {
        emit NewPendingGov(pendingGov, _pendingGov);
        pendingGov = _pendingGov;
    }

    /**
     * @notice Accept the new pending gov.
     * @dev Can only be called by the pending gov.
     */
    function acceptGov() external {
        require(msg.sender == pendingGov, "Only pending gov");
        emit NewGov(gov, pendingGov);
        gov = pendingGov;
        pendingGov = address(0);
    }

    /**
     * @notice Set a new timelock period for all deployed feeds.
     * @dev Can only be called by the gov.
     * @param _timelockPeriod new timelock period
     */
    function setTimelockPeriod(uint256 _timelockPeriod) external onlyGov {
        emit NewTimelockPeriod(timelockPeriod, _timelockPeriod);
        timelockPeriod = _timelockPeriod;
    }

    /**
     * @notice Set a new guardian.
     * @dev Can only be called by the gov.
     * @param _guardian address of the new guardian
     */
    function setGuardian(address _guardian) external onlyGov {
        emit NewGuardian(guardian, _guardian);
        guardian = _guardian;
    }
}
