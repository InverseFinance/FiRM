// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "src/interfaces/IChainlinkFeed.sol";

/// @title FeedSwitch
/// @notice A contract to switch between feeds after a timelock period
/// @dev The contract can only be initiated by the guardian and the feed can only be switched after the timelock period has passed.
/// The backup feed will default to the afterMaturityFeed if the maturity has passed, if not it will default to the beforeMaturityFeed.
/// If a switch is done before maturity, the guardian can initiate the switch again to update the feed to the afterMaturityFeed if the maturity has passed.
contract FeedSwitch {
    error SwitchNotInitiated();
    error CannotSwitchYet();
    error NotGuardian();
    error FeedDecimalsMismatch();

    address public immutable guardian;
    IChainlinkFeed public immutable beforeMaturityFeed;
    IChainlinkFeed public immutable afterMaturityFeed;
    uint256 public immutable maturity;
    uint256 public immutable timelockPeriod;

    IChainlinkFeed public feed;
    uint256 public switchInitiatedAt;

    event FeedSwitchInitiated();
    event FeedSwitched(address indexed newFeed);

    constructor(
        address _feed,
        address _beforeMaturityFeed,
        address _afterMaturityFeed,
        uint256 _timelockPeriod,
        uint256 _maturity,
        address _guardian
    ) {
        feed = IChainlinkFeed(_feed);
        beforeMaturityFeed = IChainlinkFeed(_beforeMaturityFeed);
        afterMaturityFeed = IChainlinkFeed(_afterMaturityFeed);
        if (
            feed.decimals() != beforeMaturityFeed.decimals() ||
            feed.decimals() != afterMaturityFeed.decimals() ||
            feed.decimals() != 18
        ) revert FeedDecimalsMismatch();

        timelockPeriod = _timelockPeriod;
        maturity = _maturity;
        guardian = _guardian;
    }

    /// @notice Initiate the feed switch, entering the timelock period
    /// @dev Can only be called by the guardian
    function initiateFeedSwitch() external {
        if (msg.sender != guardian) revert NotGuardian();
        switchInitiatedAt = block.timestamp;
        emit FeedSwitchInitiated();
    }

    /// @notice Switch the feed to the backup feed
    /// @dev Can be called by anyone but only after the timelock period has passed
    /// If the maturity has passed, the feed will be switched to the afterMaturityFeed.
    /// In case of a switch before maturity, the switch can be initiated again by the guardian and be updated to the after maturity feed.
    function switchFeed() external {
        if (switchInitiatedAt == 0) revert SwitchNotInitiated();
        if (block.timestamp < switchInitiatedAt + timelockPeriod)
            revert CannotSwitchYet();

        if (block.timestamp < maturity) {
            feed = beforeMaturityFeed;
        } else {
            feed = afterMaturityFeed;
        }

        switchInitiatedAt = 0;
        emit FeedSwitched(address(feed));
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
        return feed.latestRoundData();
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
}
