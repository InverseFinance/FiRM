// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

/// @notice Coin-0 USD feed with permissionless liquidation wind-down and RWG-controlled recovery.
/// @dev For StableSwap pools with a 2e18 capped EMA, pricing coins[0] by inversion.
///      As with ChainlinkCurveFeed, select the base USD feed to match the pool's rate-normalized units.
///      Use ChainlinkCurveFeed for nonzero target indices; their direct EMA has no downside floor.
///      Before activation: base USD price * 1e18 / Curve EMA; nonpositive results return zeroed data.
///      EMA >= 1.9e18 sets updatedAt to zero immediately, blocking configured borrowing before activation.
///      After activation: fixed starting USD price decays to 100 raw feed units; timestamps are zero.
///      Activation is permissionless at EMA >= 1.9e18, without a persistence window or timestamp check.
///      RWG can restore live pricing; updatedAt remains zero while EMA >= 1.9e18.
///      Fund this feed with Ethereum mainnet DOLA before activation to offer a caller reward.
///      The caller receives the full balance in the activation transaction, including a zero transfer.
///      There is no rescue function; DOLA is paid only when a wind-down is started.
///      Consuming FiRM markets must enable the borrow controller's staleness check.
contract ChainlinkCurveWindDownFeed {
    uint256 public constant WIND_DOWN_TRIGGER_EMA = 1.9e18;
    // Rounding buffer for downstream LP/vault conversions; deployment must check their combined effect.
    uint256 public constant TERMINAL_PRICE = 100;
    uint256 public constant TARGET_INDEX = 0;
    IERC20 public constant DOLA = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);

    IChainlinkBasePriceFeed public immutable ASSET_TO_USD;
    ICurvePool public immutable CURVE_POOL;
    uint256 public immutable REFERENCE_ORACLE_INDEX;
    uint32 public immutable WIND_DOWN_DURATION;
    address public immutable RWG;
    string public description;

    uint256 public windDownStartedAt;
    // A positive recorded price marks an active wind-down; RWG can clear it.
    uint256 public windDownStartPrice;

    error InvalidConfiguration();
    error InvalidBasePrice();
    error TriggerNotReached();
    error WindDownAlreadyStarted();
    error OnlyRWG();

    event WindDownStarted(
        address indexed caller,
        uint256 startedAt,
        uint256 startPrice,
        uint256 triggerEma,
        uint256 duration,
        uint256 reward
    );
    event WindDownStopped(address indexed caller);

    /// @param _assetToUsd 18-decimal USD base feed for the asset represented by oracle index _k.
    /// @param _curvePool Curve pool with the priced target asset at coin index zero.
    /// @param _k Oracle index: 0 represents coins[1], 1 represents coins[2], etc.
    /// @param _duration Seconds from activation until the terminal price.
    /// @param _rwg RWG multisig allowed to stop wind-down; fixed at deployment.
    constructor(address _assetToUsd, address _curvePool, uint256 _k, uint32 _duration, address _rwg) {
        ASSET_TO_USD = IChainlinkBasePriceFeed(_assetToUsd);
        if (ASSET_TO_USD.decimals() != 18 || _duration == 0 || _rwg == address(0)) revert InvalidConfiguration();
        CURVE_POOL = ICurvePool(_curvePool);
        REFERENCE_ORACLE_INDEX = _k;
        WIND_DOWN_DURATION = _duration;
        RWG = _rwg;
        // Check that the selected oracle index is populated and infer the target description.
        if (CURVE_POOL.coins(_k + 1) == address(0)) revert InvalidConfiguration();
        string memory coin = IERC20(CURVE_POOL.coins(TARGET_INDEX)).symbol();
        description = string(abi.encodePacked(coin, " / USD"));
    }

    /// @notice Whether the EMA permits activation and wind-down has not already started.
    /// @dev Only checks the trigger. Execution still needs a USD price >= TERMINAL_PRICE and a successful DOLA call.
    function canStartWindDown() external view returns (bool) {
        return windDownStartPrice == 0 && CURVE_POOL.price_oracle(REFERENCE_ORACLE_INDEX) >= WIND_DOWN_TRIGGER_EMA;
    }

    /// @notice Activates decay and immediately pays the caller this feed's entire DOLA balance.
    /// @dev Anyone may call; price and time cannot be supplied. Zero-balance activation is supported.
    /// @dev A rejected borrowing transaction cannot be used to persist activation: its state
    ///      changes would revert too. The keeper should submit this as a separate transaction.
    function startWindDown() external {
        if (windDownStartPrice != 0) revert WindDownAlreadyStarted();
        uint256 ema = CURVE_POOL.price_oracle(REFERENCE_ORACLE_INDEX);
        if (ema < WIND_DOWN_TRIGGER_EMA) revert TriggerNotReached();
        (, int256 price,,,) = latestRoundData();
        if (price < int256(TERMINAL_PRICE)) revert InvalidBasePrice();
        windDownStartedAt = block.timestamp;
        windDownStartPrice = uint256(price);

        // Finalize activation before interacting with DOLA. Its transfer supports zero amounts.
        uint256 reward = DOLA.balanceOf(address(this));
        DOLA.transfer(msg.sender, reward);
        emit WindDownStarted(msg.sender, block.timestamp, uint256(price), ema, WIND_DOWN_DURATION, reward);
    }

    /// @notice RWG-only reset to live pricing, including after the terminal price is reached.
    /// @dev Does not clear FiRM's recorded daily lows. EMA >= 1.9e18 keeps updatedAt zero and permits reactivation.
    function stopWindDown() external {
        if (msg.sender != RWG) revert OnlyRWG();
        windDownStartPrice = 0;
        windDownStartedAt = 0;
        emit WindDownStopped(msg.sender);
    }

    function latestRoundData()
        public
        view
        returns (uint80 roundId, int256 usdPrice, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (windDownStartPrice != 0) {
            // Zero timestamps intentionally signal unusable-for-borrowing data to FiRM.
            uint256 elapsed = block.timestamp - windDownStartedAt;
            uint256 price = TERMINAL_PRICE;
            if (elapsed < WIND_DOWN_DURATION) {
                // Linear decay from windDownStartPrice to TERMINAL_PRICE over WIND_DOWN_DURATION.
                price += (windDownStartPrice - TERMINAL_PRICE) * (WIND_DOWN_DURATION - elapsed) / WIND_DOWN_DURATION;
            }
            return (0, int256(price), 0, 0, 0);
        }
        int256 assetToUsdPrice;
        (roundId, assetToUsdPrice, startedAt, updatedAt, answeredInRound) = ASSET_TO_USD.latestRoundData();
        uint256 ema = CURVE_POOL.price_oracle(REFERENCE_ORACLE_INDEX);
        usdPrice = (assetToUsdPrice * int256(10 ** decimals())) / int256(ema);
        // Accepted precision boundary (V12 F-291933): https://v12.sh/runs/8388/public#finding-291933
        // For 0 < EMA <= 2e18, a positive base USD input can round to zero only at 1 raw unit
        // ($1e-18), with EMA > 1e18. This intentionally remains invalid instead of clamping to 1:
        // FiRM rejects price-dependent operations, including liquidations, and startWindDown()
        // rejects activation even if canStartWindDown() is true. Active decay is unaffected.
        if (usdPrice <= 0) return (0, 0, 0, 0, 0);
        if (ema >= WIND_DOWN_TRIGGER_EMA) updatedAt = 0;
        return (roundId, usdPrice, startedAt, updatedAt, answeredInRound);
    }

    function latestAnswer() external view returns (int256) {
        (, int256 latestPrice,,,) = latestRoundData();
        return latestPrice;
    }

    function decimals() public pure returns (uint256) {
        return 18;
    }
}
