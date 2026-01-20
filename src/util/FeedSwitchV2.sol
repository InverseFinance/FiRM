// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "src/interfaces/IChainlinkFeed.sol";


/// @title FeedSwitch
/// @notice A contract to switch between feeds after a timelock period
/// @dev The switch can only be initiated by the guardian and will be effective after the timelock period has passed, which could be zero.
/// If the switch is initiated but not yet effective, it can be cancelled by the guardian without timelock period (if is not zero).
/// The guardian can initiate the switch again to the previous feed multiple times.
contract FeedSwitchV2 {
    error NotGuardian();
    error NotGov();
    error NotPendingGov();
    error FeedDecimalsMismatch();

    address public pendingGov;
    address public gov;
    uint256 public timelockPeriod;
    IChainlinkFeed public feed;
    IChainlinkFeed public previousFeed;

    uint256 public switchCompletedAt;

    mapping(address => bool) public isGuardian;

    IChainlinkFeed public immutable initialFeed;
    IChainlinkFeed public immutable fallbackFeed;

    event FeedSwitchInitiated(address indexed newFeed, uint256 effectiveAt);
    event NewPendingGov(address indexed pendingGov);
    event GovChanged(address indexed newGov);
    event GuardianSet(address indexed guardian, bool isGuardian);
    event TimelockPeriodChanged(uint256 newTimelockPeriod);

    constructor(
        address _initialFeed,
        address _fallbackFeed,
        uint256 _timelockPeriod,
        address _gov,
        address _guardian
    ) {
        feed = IChainlinkFeed(_initialFeed);
        initialFeed = IChainlinkFeed(_initialFeed);
        fallbackFeed = IChainlinkFeed(_fallbackFeed);
        if (
            fallbackFeed.decimals() != 18 ||
            feed.decimals() != 18
        ) revert FeedDecimalsMismatch();

        timelockPeriod = _timelockPeriod;
        gov = _gov;
        isGuardian[_guardian] = true;
    }

    modifier onlyGov() {
        if (msg.sender != gov) revert NotGov();
        _;
    }

    /// @notice Toggle the feed switch, entering or exiting the timelock period
    /// @dev Can only be called by the guardian
    function toggleFeedSwitch() external {
        if (!isGuardian[msg.sender]) revert NotGuardian();

        if (switchCompletedAt < block.timestamp) {
            switchCompletedAt = block.timestamp + timelockPeriod;
        } else switchCompletedAt = 0;

        if (address(feed) == address(initialFeed)) {
            feed = fallbackFeed;
            previousFeed = initialFeed;
        } else {
            feed = initialFeed;
            previousFeed = fallbackFeed;
        }

        emit FeedSwitchInitiated(address(feed), switchCompletedAt > 0 ? switchCompletedAt : block.timestamp);
    }

    /// @notice Get the current feed data
    /// @return roundId The round ID
    /// @return price The price of the asset
    /// @return startedAt The timestamp of the start of the round
    /// @return updatedAt The timestamp of the last update
    /// @return answeredInRound The round ID in which the price was answered
    function latestRoundData()
        public
        view
        returns (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
       if (block.timestamp >= switchCompletedAt) {
            return feed.latestRoundData();
        } else {
            return previousFeed.latestRoundData();
        }
    }

    /// @notice Get the latest price of the asset
    /// @return price The price of the asset
    function latestAnswer() external view returns (int256) {
        (, int256 latestPrice, , , ) = latestRoundData();
        return latestPrice;
    }

    /// @notice Get the number of decimals of the feed
    /// @return decimals The number of decimals
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @notice Check if the feed switch is queued
    /// @dev If not queued, will return 0 as time left
    /// @return timeLeft The time left for the switch to be effective
    function isFeedSwitchQueued() external view returns (uint256) {
        bool isQueued = block.timestamp < switchCompletedAt;
        if (!isQueued) return 0;
        else return switchCompletedAt - block.timestamp;
    }

    /// @notice Set a new pending governance
    /// @dev Can only be called by the current governance, the new pending governance must call acceptGov to become the new governance
    /// @param _pendingGov The address of the new pending governance
    function setPendingGov(address _pendingGov) external onlyGov {
        pendingGov = _pendingGov;
        emit NewPendingGov(_pendingGov);
    }

    /// @notice Accept the governance role
    /// @dev Can only be called by the pending governance
    function acceptGov() external {
        if (msg.sender != pendingGov) revert NotPendingGov();
        gov = pendingGov;
        pendingGov = address(0);
        emit GovChanged(gov);
    }

    /// @notice Set the guardian role for an address
    /// @dev Can only be called by the governance
    /// @param guardianAddr The address to set the guardian role for
    /// @param _isGuardian Whether the address should be a guardian
    function setGuardian(address guardianAddr, bool _isGuardian) external onlyGov {
        isGuardian[guardianAddr] = _isGuardian;
        emit GuardianSet(guardianAddr, _isGuardian);
    }

    /// @notice Set a new timelock period
    /// @dev Can only be called by the governance
    /// @param _timelockPeriod The new timelock period in seconds
    function setTimelockPeriod(uint256 _timelockPeriod) external onlyGov {
        timelockPeriod = _timelockPeriod;
        emit TimelockPeriodChanged(_timelockPeriod);
    }
}
