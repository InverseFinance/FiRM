// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/util/PositionLib.sol";

contract PositionLibTest is Test {
    using PositionLib for uint256;

    uint256 constant BPS = 10_000;
    uint256 constant PRECISION = 1e18;

    // ============ Constants Tests ============

    function test_Constants() public pure {
        assertEq(PositionLib.BPS_DENOMINATOR, 10_000);
        assertEq(PositionLib.PRECISION, 1e18);
    }

    // ============ getCollateralizationRatio Tests ============

    function test_GetCollateralizationRatio() public pure {
        // 150% collateralized
        assertEq(PositionLib.getCollateralizationRatio(150e18, 100e18), 15000);
        
        // 100% collateralized
        assertEq(PositionLib.getCollateralizationRatio(100e18, 100e18), 10000);
        
        // 200% collateralized
        assertEq(PositionLib.getCollateralizationRatio(200e18, 100e18), 20000);
        
        // No debt - max ratio
        assertEq(PositionLib.getCollateralizationRatio(100e18, 0), type(uint256).max);
    }

    function testFuzz_GetCollateralizationRatio(uint256 collateral, uint256 debt) public pure {
        vm.assume(debt > 0 && debt < type(uint128).max);
        vm.assume(collateral < type(uint128).max);
        
        uint256 ratio = PositionLib.getCollateralizationRatio(collateral, debt);
        assertEq(ratio, (collateral * BPS) / debt);
    }

    // ============ getHealthStatus Tests ============

    function test_GetHealthStatus_Healthy() public pure {
        // 180% collateralized, liquidation at 120%, warning at 150%
        PositionLib.HealthStatus status = PositionLib.getHealthStatus(
            180e18, 100e18, 12000, 15000
        );
        assertEq(uint(status), uint(PositionLib.HealthStatus.Healthy));
    }

    function test_GetHealthStatus_AtRisk() public pure {
        // 130% collateralized, liquidation at 120%, warning at 150%
        PositionLib.HealthStatus status = PositionLib.getHealthStatus(
            130e18, 100e18, 12000, 15000
        );
        assertEq(uint(status), uint(PositionLib.HealthStatus.AtRisk));
    }

    function test_GetHealthStatus_Liquidatable() public pure {
        // 110% collateralized, liquidation at 120%
        PositionLib.HealthStatus status = PositionLib.getHealthStatus(
            110e18, 100e18, 12000, 15000
        );
        assertEq(uint(status), uint(PositionLib.HealthStatus.Liquidatable));
    }

    function test_GetHealthStatus_BadDebt() public pure {
        // Collateral worth less than debt
        PositionLib.HealthStatus status = PositionLib.getHealthStatus(
            80e18, 100e18, 12000, 15000
        );
        assertEq(uint(status), uint(PositionLib.HealthStatus.BadDebt));
    }

    function test_GetHealthStatus_NoDebt() public pure {
        PositionLib.HealthStatus status = PositionLib.getHealthStatus(
            100e18, 0, 12000, 15000
        );
        assertEq(uint(status), uint(PositionLib.HealthStatus.Healthy));
    }

    // ============ getAvailableToBorrow Tests ============

    function test_GetAvailableToBorrow() public pure {
        // 100 collateral, max LTV 80%, no current debt
        assertEq(PositionLib.getAvailableToBorrow(100e18, 0, 8000), 80e18);
        
        // 100 collateral, max LTV 80%, 50 current debt
        assertEq(PositionLib.getAvailableToBorrow(100e18, 50e18, 8000), 30e18);
        
        // 100 collateral, max LTV 80%, 80 current debt (at max)
        assertEq(PositionLib.getAvailableToBorrow(100e18, 80e18, 8000), 0);
        
        // 100 collateral, max LTV 80%, 90 current debt (over max)
        assertEq(PositionLib.getAvailableToBorrow(100e18, 90e18, 8000), 0);
    }

    function testFuzz_GetAvailableToBorrow(uint256 collateral, uint256 debt, uint256 maxLtv) public pure {
        vm.assume(collateral < type(uint128).max);
        vm.assume(debt < type(uint128).max);
        vm.assume(maxLtv > 0 && maxLtv <= 10000);
        
        uint256 available = PositionLib.getAvailableToBorrow(collateral, debt, maxLtv);
        uint256 maxDebt = (collateral * maxLtv) / BPS;
        
        if (debt >= maxDebt) {
            assertEq(available, 0);
        } else {
            assertEq(available, maxDebt - debt);
        }
    }

    // ============ getValueAtRisk Tests ============

    function test_GetValueAtRisk() public pure {
        // 150 collateral, 100 debt, 120% liquidation threshold
        // Min collateral = 100 * 1.2 = 120
        // Buffer = 150 - 120 = 30
        assertEq(PositionLib.getValueAtRisk(150e18, 100e18, 12000), 30e18);
        
        // At liquidation threshold
        assertEq(PositionLib.getValueAtRisk(120e18, 100e18, 12000), 0);
        
        // Below liquidation threshold
        assertEq(PositionLib.getValueAtRisk(110e18, 100e18, 12000), 0);
    }

    // ============ getWithdrawableCollateral Tests ============

    function test_GetWithdrawableCollateral() public pure {
        // 200 collateral, 100 debt, min 150% ratio
        // Required = 100 * 1.5 = 150
        // Withdrawable = 200 - 150 = 50
        assertEq(PositionLib.getWithdrawableCollateral(200e18, 100e18, 15000), 50e18);
        
        // No debt - all withdrawable
        assertEq(PositionLib.getWithdrawableCollateral(100e18, 0, 15000), 100e18);
        
        // At minimum ratio
        assertEq(PositionLib.getWithdrawableCollateral(150e18, 100e18, 15000), 0);
    }

    // ============ getRepaymentForTargetRatio Tests ============

    function test_GetRepaymentForTargetRatio() public pure {
        // 120 collateral, 100 debt, want 150% ratio
        // Target debt = 120 / 1.5 = 80
        // Repayment = 100 - 80 = 20
        assertEq(PositionLib.getRepaymentForTargetRatio(120e18, 100e18, 15000), 20e18);
        
        // Already at target ratio
        assertEq(PositionLib.getRepaymentForTargetRatio(150e18, 100e18, 15000), 0);
        
        // Above target ratio
        assertEq(PositionLib.getRepaymentForTargetRatio(200e18, 100e18, 15000), 0);
    }

    // ============ getLiquidationBonus Tests ============

    function test_GetLiquidationBonus() public pure {
        // 100 liquidation, 5% incentive
        assertEq(PositionLib.getLiquidationBonus(100e18, 500), 5e18);
        
        // 100 liquidation, 10% incentive
        assertEq(PositionLib.getLiquidationBonus(100e18, 1000), 10e18);
    }

    // ============ getMaxLiquidatableAmount Tests ============

    function test_GetMaxLiquidatableAmount() public pure {
        // 100 debt, max 50% liquidatable
        assertEq(PositionLib.getMaxLiquidatableAmount(100e18, 5000), 50e18);
        
        // 100 debt, max 100% liquidatable
        assertEq(PositionLib.getMaxLiquidatableAmount(100e18, 10000), 100e18);
    }

    // ============ getCollateralToSeize Tests ============

    function test_GetCollateralToSeize() public pure {
        // 100 debt repay, price 1.0, 5% incentive
        // Collateral value to seize = 100 * 1.05 = 105
        // Collateral amount = 105 * 1e18 / 1e18 = 105
        assertEq(PositionLib.getCollateralToSeize(100e18, 1e18, 500), 105e18);
        
        // 100 debt repay, price 2.0, 5% incentive
        // Collateral value to seize = 100 * 1.05 = 105
        // Collateral amount = 105 * 1e18 / 2e18 = 52.5
        assertEq(PositionLib.getCollateralToSeize(100e18, 2e18, 500), 525e17);
        
        // Zero price
        assertEq(PositionLib.getCollateralToSeize(100e18, 0, 500), 0);
    }

    // ============ isLiquidatable Tests ============

    function test_IsLiquidatable() public pure {
        // 150% collateralized, 120% threshold - not liquidatable
        assertFalse(PositionLib.isLiquidatable(150e18, 100e18, 12000));
        
        // 120% collateralized, 120% threshold - not liquidatable (at threshold)
        assertFalse(PositionLib.isLiquidatable(120e18, 100e18, 12000));
        
        // 110% collateralized, 120% threshold - liquidatable
        assertTrue(PositionLib.isLiquidatable(110e18, 100e18, 12000));
        
        // No debt - never liquidatable
        assertFalse(PositionLib.isLiquidatable(0, 0, 12000));
    }

    function testFuzz_IsLiquidatable(uint256 collateral, uint256 debt, uint256 threshold) public pure {
        vm.assume(debt > 0 && debt < type(uint128).max);
        vm.assume(collateral < type(uint128).max);
        vm.assume(threshold > 0 && threshold < type(uint64).max);
        
        bool liquidatable = PositionLib.isLiquidatable(collateral, debt, threshold);
        bool expected = collateral * BPS < debt * threshold;
        assertEq(liquidatable, expected);
    }

    // ============ getPositionMetrics Tests ============

    function test_GetPositionMetrics() public pure {
        PositionLib.PositionMetrics memory metrics = PositionLib.getPositionMetrics(
            150e18,  // collateralValue
            100e18,  // collateralAmount
            100e18,  // debtValue
            8000,    // maxLtvBps (80%)
            12000,   // liquidationThresholdBps (120%)
            15000    // warningThresholdBps (150%)
        );
        
        assertEq(metrics.collateralValue, 150e18);
        assertEq(metrics.debtValue, 100e18);
        assertEq(metrics.collateralizationRatio, 15000); // 150%
        assertEq(metrics.availableToBorrow, 20e18); // 150 * 0.8 - 100 = 20
        assertEq(uint(metrics.status), uint(PositionLib.HealthStatus.Healthy));
    }

    function test_GetPositionMetrics_Liquidatable() public pure {
        PositionLib.PositionMetrics memory metrics = PositionLib.getPositionMetrics(
            110e18,  // collateralValue
            100e18,  // collateralAmount
            100e18,  // debtValue
            8000,    // maxLtvBps
            12000,   // liquidationThresholdBps
            15000    // warningThresholdBps
        );
        
        assertEq(uint(metrics.status), uint(PositionLib.HealthStatus.Liquidatable));
        assertEq(metrics.availableToBorrow, 0);
    }
}
