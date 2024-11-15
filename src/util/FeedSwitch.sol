// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "src/interfaces/IChainlinkFeed.sol";

interface IPendlePT {
    function expiry() external view returns (uint256);
}

/// @title FeedSwitch for Pendle PT tokens
/// @notice A contract to switch between feeds after a timelock period
/// @dev The switch can only be initiated by the guardian and will be effective after the timelock period has passed, can only be done before maturity.
/// If the switch is initiated but not yet effective, it can be cancelled by the guardian without timelock period.
/// The feed will default to the afterMaturityFeed if the maturity has passed.
/// The guardian can initiate the switch again to the previous feed multiple times.
contract FeedSwitch {
    error NotGuardian();
    error FeedDecimalsMismatch();
    error MaturityInPast();
    error MaturityPassed();

    address public immutable guardian;
    IChainlinkFeed public immutable initialFeed;
    IChainlinkFeed public immutable beforeMaturityFeed;
    IChainlinkFeed public immutable afterMaturityFeed;
    uint256 public immutable maturity;
    uint256 public immutable timelockPeriod;

    IChainlinkFeed public feed;
    IChainlinkFeed public previousFeed;

    uint256 public switchCompletedAt;

    event FeedSwitchInitiated(address indexed newFeed);

    constructor(
        address _feed,
        address _beforeMaturityFeed,
        address _afterMaturityFeed,
        uint256 _timelockPeriod,
        address _pendlePT,
        address _guardian
    ) {
        feed = IChainlinkFeed(_feed);
        initialFeed = IChainlinkFeed(_feed);
        beforeMaturityFeed = IChainlinkFeed(_beforeMaturityFeed);
        afterMaturityFeed = IChainlinkFeed(_afterMaturityFeed);
        if (
            beforeMaturityFeed.decimals() != 18 ||
            afterMaturityFeed.decimals() != 18 ||
            feed.decimals() != 18
        ) revert FeedDecimalsMismatch();

        timelockPeriod = _timelockPeriod;
        maturity = IPendlePT(_pendlePT).expiry();
        if (maturity <= block.timestamp) revert MaturityInPast();

        guardian = _guardian;
    }

    /// @notice Initiate the feed switch, entering the timelock period
    /// @dev Can only be called by the guardian and can be done before maturity, after that, the feed will return afterMaturityFeed data
    function initiateFeedSwitch() external {
        if (msg.sender != guardian) revert NotGuardian();
        if (block.timestamp >= maturity) revert MaturityPassed();

        if (switchCompletedAt < block.timestamp) {
            switchCompletedAt = block.timestamp + timelockPeriod;
        } else switchCompletedAt = 0;

        if (address(feed) == address(initialFeed)) {
            feed = beforeMaturityFeed;
            previousFeed = initialFeed;
        } else {
            feed = initialFeed;
            previousFeed = beforeMaturityFeed;
        }

        emit FeedSwitchInitiated(address(feed));
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
        if (block.timestamp >= maturity) {
            return afterMaturityFeed.latestRoundData();
        } else if (block.timestamp >= switchCompletedAt) {
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
    /// @dev If not queued, will return false and 0 as time left
    /// @return isQueued Whether the feed switch is queued
    /// @return timeLeft The time left for the switch to be effective
    function isFeedSwitchQueued() external view returns (bool, uint256) {
        bool isQueued = switchCompletedAt > 0 &&
            block.timestamp < switchCompletedAt;
        if (!isQueued) return (false, 0);
        else return (isQueued, switchCompletedAt - block.timestamp);
    }
}
