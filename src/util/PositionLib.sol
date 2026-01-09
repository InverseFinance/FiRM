// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title PositionLib
 * @notice A library providing position health and liquidation utilities
 * @dev Designed for lending protocol position management calculations
 */
library PositionLib {
    /// @notice The basis points denominator (100% = 10000 bps)
    uint256 public constant BPS_DENOMINATOR = 10_000;
    
    /// @notice The precision factor for calculations (1e18)
    uint256 public constant PRECISION = 1e18;

    /// @notice Position health status
    enum HealthStatus {
        Healthy,        // Above liquidation threshold
        AtRisk,         // Below warning threshold but above liquidation
        Liquidatable,   // Below liquidation threshold
        BadDebt         // Collateral worth less than debt
    }

    /// @notice Position metrics struct
    struct PositionMetrics {
        uint256 collateralValue;
        uint256 debtValue;
        uint256 collateralizationRatio;
        uint256 availableToBorrow;
        uint256 liquidationPrice;
        HealthStatus status;
    }

    /**
     * @notice Calculates the collateralization ratio of a position
     * @param collateralValue The value of collateral in base units
     * @param debtValue The value of debt in base units
     * @return ratio The collateralization ratio in bps (e.g., 15000 = 150%)
     */
    function getCollateralizationRatio(
        uint256 collateralValue,
        uint256 debtValue
    ) internal pure returns (uint256 ratio) {
        if (debtValue == 0) return type(uint256).max;
        return (collateralValue * BPS_DENOMINATOR) / debtValue;
    }

    /**
     * @notice Determines the health status of a position
     * @param collateralValue The value of collateral
     * @param debtValue The value of debt
     * @param liquidationThresholdBps The liquidation threshold in bps
     * @param warningThresholdBps The warning threshold in bps (should be > liquidationThresholdBps)
     * @return The health status of the position
     */
    function getHealthStatus(
        uint256 collateralValue,
        uint256 debtValue,
        uint256 liquidationThresholdBps,
        uint256 warningThresholdBps
    ) internal pure returns (HealthStatus) {
        if (debtValue == 0) return HealthStatus.Healthy;
        if (collateralValue < debtValue) return HealthStatus.BadDebt;
        
        uint256 ratio = getCollateralizationRatio(collateralValue, debtValue);
        
        if (ratio < liquidationThresholdBps) return HealthStatus.Liquidatable;
        if (ratio < warningThresholdBps) return HealthStatus.AtRisk;
        return HealthStatus.Healthy;
    }

    /**
     * @notice Calculates the maximum additional debt that can be safely borrowed
     * @param collateralValue The value of collateral
     * @param currentDebt The current debt value
     * @param maxLtvBps The maximum loan-to-value ratio in bps
     * @return The maximum additional borrowable amount
     */
    function getAvailableToBorrow(
        uint256 collateralValue,
        uint256 currentDebt,
        uint256 maxLtvBps
    ) internal pure returns (uint256) {
        uint256 maxDebt = (collateralValue * maxLtvBps) / BPS_DENOMINATOR;
        if (currentDebt >= maxDebt) return 0;
        return maxDebt - currentDebt;
    }

    /**
     * @notice Calculates the collateral price at which position becomes liquidatable
     * @param collateralAmount The amount of collateral (not value)
     * @param debtValue The debt value
     * @param liquidationThresholdBps The liquidation threshold in bps
     * @return The liquidation price per unit of collateral
     */
    function getLiquidationPrice(
        uint256 collateralAmount,
        uint256 debtValue,
        uint256 liquidationThresholdBps
    ) internal pure returns (uint256) {
        if (collateralAmount == 0) return 0;
        // liquidationPrice = (debtValue * liquidationThreshold) / collateralAmount
        return (debtValue * liquidationThresholdBps) / (collateralAmount * BPS_DENOMINATOR / PRECISION);
    }

    /**
     * @notice Calculates the value at risk (how much value needs to drop for liquidation)
     * @param collateralValue The current collateral value
     * @param debtValue The current debt value
     * @param liquidationThresholdBps The liquidation threshold in bps
     * @return The buffer value before liquidation
     */
    function getValueAtRisk(
        uint256 collateralValue,
        uint256 debtValue,
        uint256 liquidationThresholdBps
    ) internal pure returns (uint256) {
        uint256 minCollateral = (debtValue * liquidationThresholdBps) / BPS_DENOMINATOR;
        if (collateralValue <= minCollateral) return 0;
        return collateralValue - minCollateral;
    }

    /**
     * @notice Calculates the amount of collateral that can be safely withdrawn
     * @param collateralValue The current collateral value
     * @param debtValue The current debt value
     * @param minCollateralRatioBps The minimum collateral ratio to maintain in bps
     * @return The maximum withdrawable collateral value
     */
    function getWithdrawableCollateral(
        uint256 collateralValue,
        uint256 debtValue,
        uint256 minCollateralRatioBps
    ) internal pure returns (uint256) {
        if (debtValue == 0) return collateralValue;
        
        uint256 requiredCollateral = (debtValue * minCollateralRatioBps) / BPS_DENOMINATOR;
        if (collateralValue <= requiredCollateral) return 0;
        return collateralValue - requiredCollateral;
    }

    /**
     * @notice Calculates the debt repayment needed to reach a target collateralization ratio
     * @param collateralValue The current collateral value
     * @param debtValue The current debt value
     * @param targetRatioBps The target collateralization ratio in bps
     * @return The amount of debt to repay
     */
    function getRepaymentForTargetRatio(
        uint256 collateralValue,
        uint256 debtValue,
        uint256 targetRatioBps
    ) internal pure returns (uint256) {
        if (targetRatioBps == 0) return 0;
        
        // targetRatio = collateralValue / (debtValue - repayment)
        // debtValue - repayment = collateralValue / targetRatio
        // repayment = debtValue - (collateralValue * BPS / targetRatio)
        uint256 targetDebt = (collateralValue * BPS_DENOMINATOR) / targetRatioBps;
        
        if (debtValue <= targetDebt) return 0;
        return debtValue - targetDebt;
    }

    /**
     * @notice Calculates liquidation incentive/bonus for liquidators
     * @param liquidationAmount The amount being liquidated
     * @param incentiveBps The liquidation incentive in bps
     * @return The bonus amount for the liquidator
     */
    function getLiquidationBonus(
        uint256 liquidationAmount,
        uint256 incentiveBps
    ) internal pure returns (uint256) {
        return (liquidationAmount * incentiveBps) / BPS_DENOMINATOR;
    }

    /**
     * @notice Calculates the maximum liquidatable amount for partial liquidation
     * @param debtValue The total debt value
     * @param maxLiquidationBps The maximum percentage that can be liquidated in bps
     * @return The maximum liquidatable debt amount
     */
    function getMaxLiquidatableAmount(
        uint256 debtValue,
        uint256 maxLiquidationBps
    ) internal pure returns (uint256) {
        return (debtValue * maxLiquidationBps) / BPS_DENOMINATOR;
    }

    /**
     * @notice Calculates collateral to seize during liquidation
     * @param debtToRepay The amount of debt being repaid
     * @param collateralPrice The price of collateral (per unit with PRECISION)
     * @param incentiveBps The liquidation incentive in bps
     * @return The amount of collateral to seize
     */
    function getCollateralToSeize(
        uint256 debtToRepay,
        uint256 collateralPrice,
        uint256 incentiveBps
    ) internal pure returns (uint256) {
        if (collateralPrice == 0) return 0;
        
        uint256 incentiveMultiplier = BPS_DENOMINATOR + incentiveBps;
        uint256 collateralValueToSeize = (debtToRepay * incentiveMultiplier) / BPS_DENOMINATOR;
        
        return (collateralValueToSeize * PRECISION) / collateralPrice;
    }

    /**
     * @notice Checks if a position can be liquidated
     * @param collateralValue The value of collateral
     * @param debtValue The value of debt
     * @param liquidationThresholdBps The liquidation threshold in bps
     * @return True if position is liquidatable
     */
    function isLiquidatable(
        uint256 collateralValue,
        uint256 debtValue,
        uint256 liquidationThresholdBps
    ) internal pure returns (bool) {
        if (debtValue == 0) return false;
        return collateralValue * BPS_DENOMINATOR < debtValue * liquidationThresholdBps;
    }

    /**
     * @notice Gets comprehensive position metrics
     * @param collateralValue The value of collateral
     * @param collateralAmount The amount of collateral
     * @param debtValue The value of debt
     * @param maxLtvBps The maximum LTV in bps
     * @param liquidationThresholdBps The liquidation threshold in bps
     * @param warningThresholdBps The warning threshold in bps
     * @return metrics The comprehensive position metrics
     */
    function getPositionMetrics(
        uint256 collateralValue,
        uint256 collateralAmount,
        uint256 debtValue,
        uint256 maxLtvBps,
        uint256 liquidationThresholdBps,
        uint256 warningThresholdBps
    ) internal pure returns (PositionMetrics memory metrics) {
        metrics.collateralValue = collateralValue;
        metrics.debtValue = debtValue;
        metrics.collateralizationRatio = getCollateralizationRatio(collateralValue, debtValue);
        metrics.availableToBorrow = getAvailableToBorrow(collateralValue, debtValue, maxLtvBps);
        metrics.liquidationPrice = getLiquidationPrice(collateralAmount, debtValue, liquidationThresholdBps);
        metrics.status = getHealthStatus(collateralValue, debtValue, liquidationThresholdBps, warningThresholdBps);
    }
}
