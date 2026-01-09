// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/util/MathLib.sol";

contract MathLibTest is Test {
    using MathLib for uint256;

    // ============ Constants Tests ============

    function test_Constants() public pure {
        assertEq(MathLib.BPS_DENOMINATOR, 10_000);
        assertEq(MathLib.PRECISION, 1e18);
        assertEq(MathLib.SECONDS_PER_DAY, 86400);
        assertEq(MathLib.SECONDS_PER_YEAR, 365 days);
    }

    // ============ min/max Tests ============

    function test_Min() public pure {
        assertEq(MathLib.min(10, 20), 10);
        assertEq(MathLib.min(20, 10), 10);
        assertEq(MathLib.min(10, 10), 10);
        assertEq(MathLib.min(0, 100), 0);
        assertEq(MathLib.min(type(uint256).max, 0), 0);
    }

    function test_Max() public pure {
        assertEq(MathLib.max(10, 20), 20);
        assertEq(MathLib.max(20, 10), 20);
        assertEq(MathLib.max(10, 10), 10);
        assertEq(MathLib.max(0, 100), 100);
        assertEq(MathLib.max(type(uint256).max, 0), type(uint256).max);
    }

    function testFuzz_MinMax(uint256 a, uint256 b) public pure {
        uint256 minVal = MathLib.min(a, b);
        uint256 maxVal = MathLib.max(a, b);
        
        assertTrue(minVal <= a && minVal <= b);
        assertTrue(maxVal >= a && maxVal >= b);
        assertTrue(minVal <= maxVal);
    }

    // ============ clamp Tests ============

    function test_Clamp() public pure {
        assertEq(MathLib.clamp(50, 0, 100), 50);
        assertEq(MathLib.clamp(0, 10, 100), 10);
        assertEq(MathLib.clamp(150, 10, 100), 100);
        assertEq(MathLib.clamp(10, 10, 10), 10);
    }

    function test_Clamp_InvalidRange() public pure {
        // When min > max, returns min
        assertEq(MathLib.clamp(50, 100, 10), 100);
    }

    function testFuzz_Clamp(uint256 value, uint256 minVal, uint256 maxVal) public pure {
        vm.assume(minVal <= maxVal);
        uint256 result = MathLib.clamp(value, minVal, maxVal);
        assertTrue(result >= minVal && result <= maxVal);
    }

    // ============ absDiff Tests ============

    function test_AbsDiff() public pure {
        assertEq(MathLib.absDiff(100, 30), 70);
        assertEq(MathLib.absDiff(30, 100), 70);
        assertEq(MathLib.absDiff(100, 100), 0);
        assertEq(MathLib.absDiff(0, 0), 0);
    }

    function testFuzz_AbsDiff(uint256 a, uint256 b) public pure {
        uint256 diff = MathLib.absDiff(a, b);
        if (a > b) {
            assertEq(diff, a - b);
        } else {
            assertEq(diff, b - a);
        }
    }

    // ============ safeDiv Tests ============

    function test_SafeDiv() public pure {
        assertEq(MathLib.safeDiv(100, 10), 10);
        assertEq(MathLib.safeDiv(100, 0), 0);
        assertEq(MathLib.safeDiv(0, 10), 0);
        assertEq(MathLib.safeDiv(7, 3), 2);
    }

    // ============ divUp Tests ============

    function test_DivUp() public pure {
        assertEq(MathLib.divUp(100, 10), 10);
        assertEq(MathLib.divUp(101, 10), 11);
        assertEq(MathLib.divUp(99, 10), 10);
        assertEq(MathLib.divUp(0, 10), 0);
        assertEq(MathLib.divUp(1, 10), 1);
    }

    function test_DivUp_RevertOnZero() public {
        // Library functions revert inline, so we test by wrapping in a try/catch
        bool reverted = false;
        try this.callDivUp(100, 0) returns (uint256) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "Should revert on division by zero");
    }

    // Helper function for testing reverts in library calls
    function callDivUp(uint256 a, uint256 b) external pure returns (uint256) {
        return MathLib.divUp(a, b);
    }

    // ============ mulDiv Tests ============

    function test_MulDiv() public pure {
        assertEq(MathLib.mulDiv(100, 50, 100), 50);
        assertEq(MathLib.mulDiv(1e18, 5000, 10000), 5e17);
        assertEq(MathLib.mulDiv(0, 100, 100), 0);
    }

    function test_MulDiv_RevertOnZero() public {
        bool reverted = false;
        try this.callMulDiv(100, 50, 0) returns (uint256) {
            reverted = false;
        } catch {
            reverted = true;
        }
        assertTrue(reverted, "Should revert on division by zero");
    }

    // Helper function for testing reverts in library calls
    function callMulDiv(uint256 a, uint256 b, uint256 c) external pure returns (uint256) {
        return MathLib.mulDiv(a, b, c);
    }

    function test_MulDivUp() public pure {
        assertEq(MathLib.mulDivUp(100, 50, 100), 50);
        assertEq(MathLib.mulDivUp(101, 1, 100), 2);
        assertEq(MathLib.mulDivUp(0, 100, 100), 0);
    }

    // ============ BPS Conversion Tests ============

    function test_BpsToDecimal() public pure {
        assertEq(MathLib.bpsToDecimal(10000), 1e18); // 100%
        assertEq(MathLib.bpsToDecimal(5000), 5e17);  // 50%
        assertEq(MathLib.bpsToDecimal(100), 1e16);   // 1%
        assertEq(MathLib.bpsToDecimal(1), 1e14);     // 0.01%
    }

    function test_ApplyBps() public pure {
        assertEq(MathLib.applyBps(1000, 10000), 1000); // 100%
        assertEq(MathLib.applyBps(1000, 5000), 500);   // 50%
        assertEq(MathLib.applyBps(1000, 100), 10);     // 1%
        assertEq(MathLib.applyBps(10000, 250), 250);   // 2.5%
    }

    function test_ApplyPercentage() public pure {
        assertEq(MathLib.applyPercentage(1000, 1e18), 1000);   // 100%
        assertEq(MathLib.applyPercentage(1000, 5e17), 500);    // 50%
        assertEq(MathLib.applyPercentage(1000, 1e16), 10);     // 1%
    }

    // ============ ratio Tests ============

    function test_Ratio() public pure {
        assertEq(MathLib.ratio(100, 100), 1e18);      // 1:1
        assertEq(MathLib.ratio(50, 100), 5e17);       // 1:2
        assertEq(MathLib.ratio(150, 100), 15e17);     // 3:2
        assertEq(MathLib.ratio(100, 0), 0);           // div by zero returns 0
    }

    // ============ proRata Tests ============

    function test_ProRata() public pure {
        assertEq(MathLib.proRata(1000, 50, 100), 500);   // 50% elapsed
        assertEq(MathLib.proRata(1000, 100, 100), 1000); // 100% elapsed
        assertEq(MathLib.proRata(1000, 150, 100), 1000); // over 100% capped
        assertEq(MathLib.proRata(1000, 0, 100), 0);      // 0% elapsed
        assertEq(MathLib.proRata(1000, 50, 0), 0);       // zero period
    }

    // ============ calculateInterest Tests ============

    function test_CalculateInterest() public pure {
        // 1000 principal, 10% annual rate, 1 year
        uint256 interest = MathLib.calculateInterest(1000e18, 1000, 365 days);
        assertEq(interest, 100e18);

        // 1000 principal, 10% annual rate, 6 months (half year)
        interest = MathLib.calculateInterest(1000e18, 1000, 365 days / 2);
        assertEq(interest, 50e18);

        // 1000 principal, 5% annual rate, 1 year
        interest = MathLib.calculateInterest(1000e18, 500, 365 days);
        assertEq(interest, 50e18);
    }

    // ============ safeSub Tests ============

    function test_SafeSub() public pure {
        assertEq(MathLib.safeSub(100, 30), 70);
        assertEq(MathLib.safeSub(30, 100), 0);
        assertEq(MathLib.safeSub(100, 100), 0);
    }

    // ============ isWithinTolerance Tests ============

    function test_IsWithinTolerance() public pure {
        assertTrue(MathLib.isWithinTolerance(100, 100, 100));   // exact match
        assertTrue(MathLib.isWithinTolerance(101, 100, 100));   // 1% tolerance, 1% diff
        assertTrue(MathLib.isWithinTolerance(99, 100, 100));    // 1% tolerance, 1% diff
        assertFalse(MathLib.isWithinTolerance(110, 100, 100));  // 1% tolerance, 10% diff
        assertTrue(MathLib.isWithinTolerance(0, 0, 100));       // zero target
    }

    // ============ convertDecimals Tests ============

    function test_ConvertDecimals() public pure {
        // 6 decimals to 18 decimals
        assertEq(MathLib.convertDecimals(1e6, 6, 18), 1e18);
        
        // 18 decimals to 6 decimals
        assertEq(MathLib.convertDecimals(1e18, 18, 6), 1e6);
        
        // Same decimals
        assertEq(MathLib.convertDecimals(1000, 8, 8), 1000);
        
        // 8 to 18
        assertEq(MathLib.convertDecimals(1e8, 8, 18), 1e18);
    }

    // ============ currentDay Tests ============

    function test_CurrentDay() public {
        uint256 day = MathLib.currentDay();
        assertEq(day, block.timestamp / 1 days);

        // Warp to a specific time and verify
        vm.warp(86400 * 100); // Day 100
        assertEq(MathLib.currentDay(), 100);
    }

    // ============ collateralizationRatio Tests ============

    function test_CollateralizationRatio() public pure {
        // 150% collateralized
        assertEq(MathLib.collateralizationRatio(150e18, 100e18), 15e17);
        
        // 100% collateralized
        assertEq(MathLib.collateralizationRatio(100e18, 100e18), 1e18);
        
        // No debt - max ratio
        assertEq(MathLib.collateralizationRatio(100e18, 0), type(uint256).max);
    }

    // ============ isPositionHealthy Tests ============

    function test_IsPositionHealthy() public pure {
        // 150% collateral, min 120% required - healthy
        assertTrue(MathLib.isPositionHealthy(150e18, 100e18, 12000));
        
        // 110% collateral, min 120% required - unhealthy
        assertFalse(MathLib.isPositionHealthy(110e18, 100e18, 12000));
        
        // No debt - always healthy
        assertTrue(MathLib.isPositionHealthy(0, 0, 12000));
    }

    // ============ calculateLiquidationAmount Tests ============

    function test_CalculateLiquidationAmount() public pure {
        // Already healthy - no liquidation needed
        assertEq(MathLib.calculateLiquidationAmount(200e18, 100e18, 15000, 500), 0);
        
        // Undercollateralized - needs liquidation
        uint256 amount = MathLib.calculateLiquidationAmount(100e18, 100e18, 15000, 500);
        assertTrue(amount > 0);
    }
}
