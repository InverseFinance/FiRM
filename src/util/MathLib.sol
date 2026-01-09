// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title MathLib
 * @notice A library providing safe math operations and utilities for DeFi calculations
 * @dev Designed for use across FiRM protocol contracts. All operations include
 *      overflow/underflow protection and proper rounding behavior.
 */
library MathLib {
    /// @notice The basis points denominator (100% = 10000 bps)
    uint256 public constant BPS_DENOMINATOR = 10_000;
    
    /// @notice The precision factor for percentage calculations (1e18)
    uint256 public constant PRECISION = 1e18;
    
    /// @notice Seconds per day for time-based calculations
    uint256 public constant SECONDS_PER_DAY = 1 days;
    
    /// @notice Seconds per year (365 days) for annual rate calculations
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    /**
     * @notice Calculates the minimum of two values
     * @param a The first value
     * @param b The second value
     * @return The smaller of the two values
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Calculates the maximum of two values
     * @param a The first value
     * @param b The second value
     * @return The larger of the two values
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @notice Clamps a value between a minimum and maximum
     * @param value The value to clamp
     * @param minValue The minimum allowed value
     * @param maxValue The maximum allowed value
     * @return The clamped value
     * @dev If minValue > maxValue, returns minValue
     */
    function clamp(uint256 value, uint256 minValue, uint256 maxValue) internal pure returns (uint256) {
        if (minValue > maxValue) return minValue;
        if (value < minValue) return minValue;
        if (value > maxValue) return maxValue;
        return value;
    }

    /**
     * @notice Calculates the absolute difference between two values
     * @param a The first value
     * @param b The second value
     * @return The absolute difference |a - b|
     */
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    /**
     * @notice Safe division that returns 0 if divisor is 0
     * @param a The numerator
     * @param b The divisor
     * @return The result of a/b, or 0 if b is 0
     */
    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) return 0;
        return a / b;
    }

    /**
     * @notice Division with rounding up
     * @param a The numerator
     * @param b The divisor
     * @return The result of a/b rounded up
     * @dev Reverts if b is 0
     */
    function divUp(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "MathLib: division by zero");
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Multiplies two numbers and divides by a third, with protection against overflow
     * @param a The first multiplicand
     * @param b The second multiplicand
     * @param c The divisor
     * @return The result of (a * b) / c
     * @dev Reverts if c is 0
     */
    function mulDiv(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        require(c > 0, "MathLib: division by zero");
        return (a * b) / c;
    }

    /**
     * @notice Multiplies two numbers and divides by a third, rounding up
     * @param a The first multiplicand
     * @param b The second multiplicand
     * @param c The divisor
     * @return The result of (a * b) / c, rounded up
     * @dev Reverts if c is 0
     */
    function mulDivUp(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        require(c > 0, "MathLib: division by zero");
        uint256 product = a * b;
        return product == 0 ? 0 : (product - 1) / c + 1;
    }

    /**
     * @notice Converts a value from basis points to a decimal multiplier
     * @param bps The value in basis points (e.g., 500 = 5%)
     * @return The decimal representation with PRECISION (e.g., 500 bps = 0.05e18)
     */
    function bpsToDecimal(uint256 bps) internal pure returns (uint256) {
        return (bps * PRECISION) / BPS_DENOMINATOR;
    }

    /**
     * @notice Applies a basis points multiplier to a value
     * @param value The base value
     * @param bps The multiplier in basis points
     * @return The result of value * bps / 10000
     */
    function applyBps(uint256 value, uint256 bps) internal pure returns (uint256) {
        return (value * bps) / BPS_DENOMINATOR;
    }

    /**
     * @notice Calculates the percentage of a value
     * @param value The base value
     * @param percentage The percentage with PRECISION (1e18 = 100%)
     * @return The result
     */
    function applyPercentage(uint256 value, uint256 percentage) internal pure returns (uint256) {
        return (value * percentage) / PRECISION;
    }

    /**
     * @notice Calculates the ratio of two values with precision
     * @param numerator The numerator
     * @param denominator The denominator
     * @return The ratio with PRECISION (1e18)
     */
    function ratio(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
        if (denominator == 0) return 0;
        return (numerator * PRECISION) / denominator;
    }

    /**
     * @notice Calculates pro-rata share based on time elapsed
     * @param totalAmount The total amount to distribute
     * @param elapsed The elapsed time
     * @param period The total period
     * @return The pro-rata share
     * @dev Commonly used for vesting, streaming, or time-weighted distributions
     */
    function proRata(uint256 totalAmount, uint256 elapsed, uint256 period) internal pure returns (uint256) {
        if (period == 0) return 0;
        if (elapsed >= period) return totalAmount;
        return (totalAmount * elapsed) / period;
    }

    /**
     * @notice Calculates annual rate applied over a time period
     * @param principal The principal amount
     * @param annualRateBps The annual rate in basis points
     * @param duration The duration in seconds
     * @return The amount accrued
     * @dev Used for interest calculations in lending protocols
     */
    function calculateInterest(
        uint256 principal,
        uint256 annualRateBps,
        uint256 duration
    ) internal pure returns (uint256) {
        return (principal * annualRateBps * duration) / (BPS_DENOMINATOR * SECONDS_PER_YEAR);
    }

    /**
     * @notice Safely subtracts b from a, returning 0 if b > a
     * @param a The value to subtract from
     * @param b The value to subtract
     * @return The result of a - b, or 0 if b > a
     */
    function safeSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }

    /**
     * @notice Checks if a value is within a tolerance of a target
     * @param value The value to check
     * @param target The target value
     * @param toleranceBps The tolerance in basis points
     * @return True if value is within tolerance of target
     */
    function isWithinTolerance(
        uint256 value,
        uint256 target,
        uint256 toleranceBps
    ) internal pure returns (bool) {
        if (target == 0) return value == 0;
        uint256 diff = absDiff(value, target);
        uint256 maxDiff = applyBps(target, toleranceBps);
        return diff <= maxDiff;
    }

    /**
     * @notice Converts token amount from one decimal precision to another
     * @param amount The amount to convert
     * @param fromDecimals The source decimal precision
     * @param toDecimals The target decimal precision
     * @return The converted amount
     */
    function convertDecimals(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) return amount;
        if (fromDecimals < toDecimals) {
            return amount * 10 ** (toDecimals - fromDecimals);
        }
        return amount / 10 ** (fromDecimals - toDecimals);
    }

    /**
     * @notice Gets the current day number (for daily tracking)
     * @return The current day number since epoch
     */
    function currentDay() internal view returns (uint256) {
        return block.timestamp / SECONDS_PER_DAY;
    }

    /**
     * @notice Calculates collateralization ratio
     * @param collateralValue The value of collateral
     * @param debtValue The value of debt
     * @return The collateralization ratio with PRECISION (1e18)
     * @dev Returns type(uint256).max if debtValue is 0 (fully collateralized)
     */
    function collateralizationRatio(
        uint256 collateralValue,
        uint256 debtValue
    ) internal pure returns (uint256) {
        if (debtValue == 0) return type(uint256).max;
        return (collateralValue * PRECISION) / debtValue;
    }

    /**
     * @notice Checks if a position is healthy (above minimum collateralization)
     * @param collateralValue The value of collateral
     * @param debtValue The value of debt
     * @param minRatioBps The minimum collateralization ratio in bps (e.g., 15000 = 150%)
     * @return True if position is healthy
     */
    function isPositionHealthy(
        uint256 collateralValue,
        uint256 debtValue,
        uint256 minRatioBps
    ) internal pure returns (bool) {
        if (debtValue == 0) return true;
        // collateralValue / debtValue >= minRatioBps / BPS_DENOMINATOR
        // collateralValue * BPS_DENOMINATOR >= debtValue * minRatioBps
        return collateralValue * BPS_DENOMINATOR >= debtValue * minRatioBps;
    }

    /**
     * @notice Calculates liquidation amount needed to restore health
     * @param collateralValue The current collateral value
     * @param debtValue The current debt value
     * @param targetRatioBps The target collateralization ratio in bps
     * @param liquidationIncentiveBps The liquidation incentive in bps
     * @return The amount of debt to liquidate
     */
    function calculateLiquidationAmount(
        uint256 collateralValue,
        uint256 debtValue,
        uint256 targetRatioBps,
        uint256 liquidationIncentiveBps
    ) internal pure returns (uint256) {
        // If already healthy, no liquidation needed
        if (isPositionHealthy(collateralValue, debtValue, targetRatioBps)) {
            return 0;
        }
        
        // Calculate how much debt needs to be repaid
        // (collateral - repay * (1 + incentive)) / (debt - repay) = targetRatio
        uint256 incentiveMultiplier = BPS_DENOMINATOR + liquidationIncentiveBps;
        uint256 targetCollateral = (debtValue * targetRatioBps) / BPS_DENOMINATOR;
        
        if (collateralValue >= targetCollateral) {
            return 0;
        }
        
        uint256 collateralDeficit = targetCollateral - collateralValue;
        uint256 effectiveRepayMultiplier = targetRatioBps - incentiveMultiplier;
        
        if (effectiveRepayMultiplier == 0) {
            return debtValue; // Full liquidation needed
        }
        
        return (collateralDeficit * BPS_DENOMINATOR) / effectiveRepayMultiplier;
    }
}
