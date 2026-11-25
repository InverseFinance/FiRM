// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {IChainlinkFeed} from "src/interfaces/IChainlinkFeed.sol";

/// @notice Timelocked switch between a fixed 1e18 price and an underlying 18-decimal feed.
/// @dev Starts in fixed-price mode. While fixed pricing is active, an underlying price below
///      borrowThreshold, or a reverted underlying read, sets updatedAt to zero. Consuming markets
///      must enable their borrow controller's staleness check to block borrowing on this signal.
contract OneDolaFeedSwitch {
    error NotGuardian();
    error NotGov();
    error NotPendingGov();
    error OnlyRWG();
    error ZeroAddress();
    error FeedDecimalsMismatch();
    error InvalidBorrowThreshold();

    int256 public constant FIXED_PRICE = 1e18;
    IChainlinkFeed public immutable underlyingFeed;
    address public immutable RWG;

    address public pendingGov;
    address public gov;
    uint256 public timelockPeriod;
    uint256 public switchCompletedAt;
    int256 public borrowThreshold;
    /// @notice Target mode; during a queued switch, the opposite mode remains active.
    bool public useFixedPrice = true;
    mapping(address => bool) public isGuardian;
    /// @notice Describes both pricing sources, regardless of the active mode.
    string public description;

    event FeedSwitchInitiated(bool useFixedPrice, uint256 effectiveAt);
    event NewPendingGov(address indexed pendingGov);
    event GovChanged(address indexed newGov);
    event GuardianSet(address indexed guardian, bool isGuardian);
    event TimelockPeriodChanged(uint256 newTimelockPeriod);
    event BorrowThresholdChanged(int256 newBorrowThreshold);

    /// @param _underlyingFeed Immutable 18-decimal price source.
    /// @param _timelockPeriod Delay in seconds for switching in either direction; may be zero.
    /// @param _gov Governance controlling guardians and the timelock, with two-step transfer.
    /// @param _guardian Initial guardian allowed to toggle or cancel a switch.
    /// @param _rwg Immutable RWG address allowed to update the borrowing threshold.
    /// @param _borrowThreshold Positive underlying price floor, denominated in 18 decimals.
    constructor(
        address _underlyingFeed,
        uint256 _timelockPeriod,
        address _gov,
        address _guardian,
        address _rwg,
        int256 _borrowThreshold
    ) {
        if (_underlyingFeed == address(0) || _gov == address(0) || _guardian == address(0) || _rwg == address(0)) {
            revert ZeroAddress();
        }
        if (_borrowThreshold <= 0) revert InvalidBorrowThreshold();
        underlyingFeed = IChainlinkFeed(_underlyingFeed);
        if (underlyingFeed.decimals() != 18) revert FeedDecimalsMismatch();
        RWG = _rwg;
        gov = _gov;
        isGuardian[_guardian] = true;
        timelockPeriod = _timelockPeriod;
        borrowThreshold = _borrowThreshold;
        description = string.concat("OneDolaFeedSwitch: Fixed 1e18 or ", underlyingFeed.description());
    }

    modifier onlyGov() {
        if (msg.sender != gov) revert NotGov();
        _;
    }

    /// @notice Queue a switch, or immediately cancel one that has not yet taken effect.
    /// @dev A switch is complete at its exact deadline. Every subsequent switch gets a new timelock.
    function toggleFeedSwitch() external {
        if (!isGuardian[msg.sender]) revert NotGuardian();
        if (block.timestamp < switchCompletedAt) {
            switchCompletedAt = 0;
        } else {
            switchCompletedAt = block.timestamp + timelockPeriod;
        }
        useFixedPrice = !useFixedPrice;
        emit FeedSwitchInitiated(useFixedPrice, switchCompletedAt > 0 ? switchCompletedAt : block.timestamp);
    }

    /// @notice Whether fixed pricing is currently effective, accounting for any queued switch.
    function isFixedPriceActive() public view returns (bool) {
        return block.timestamp >= switchCompletedAt ? useFixedPrice : !useFixedPrice;
    }

    function latestRoundData()
        public
        view
        returns (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (!isFixedPriceActive()) return underlyingFeed.latestRoundData();

        // Keep fixed pricing available for liquidations if the underlying feed fails.
        try underlyingFeed.latestRoundData() returns (uint80, int256 underlyingPrice, uint256, uint256, uint80) {
            updatedAt = underlyingPrice < borrowThreshold ? 0 : block.timestamp;
        } catch {
            updatedAt = 0;
        }
        return (0, FIXED_PRICE, 0, updatedAt, 0);
    }

    /// @notice Returns the effective price; use latestRoundData to inspect the borrowing signal.
    function latestAnswer() external view returns (int256) {
        (, int256 price,,,) = latestRoundData();
        return price;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @notice Seconds until the queued switch becomes effective, or zero if none is pending.
    function isFeedSwitchQueued() external view returns (uint256) {
        return block.timestamp < switchCompletedAt ? switchCompletedAt - block.timestamp : 0;
    }

    /// @notice Immediately update the fixed-mode borrowing floor; equality does not trigger it.
    function setBorrowThreshold(int256 _borrowThreshold) external {
        if (msg.sender != RWG) revert OnlyRWG();
        if (_borrowThreshold <= 0) revert InvalidBorrowThreshold();
        borrowThreshold = _borrowThreshold;
        emit BorrowThresholdChanged(_borrowThreshold);
    }

    function setPendingGov(address _pendingGov) external onlyGov {
        pendingGov = _pendingGov;
        emit NewPendingGov(_pendingGov);
    }

    function acceptGov() external {
        if (msg.sender != pendingGov) revert NotPendingGov();
        gov = pendingGov;
        pendingGov = address(0);
        emit GovChanged(gov);
    }

    function setGuardian(address guardianAddr, bool _isGuardian) external onlyGov {
        isGuardian[guardianAddr] = _isGuardian;
        emit GuardianSet(guardianAddr, _isGuardian);
    }

    /// @dev Updates affect future switches; a queued switch keeps its existing deadline.
    function setTimelockPeriod(uint256 _timelockPeriod) external onlyGov {
        timelockPeriod = _timelockPeriod;
        emit TimelockPeriodChanged(_timelockPeriod);
    }
}
