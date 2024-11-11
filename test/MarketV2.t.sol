pragma solidity ^0.8.20;
import {MarketV2, IDolaBorrowingRights, IERC20, IOracle} from "src/MarketV2.sol";
import {ERC20} from "test/mocks/ERC20.sol";
import "forge-std/Test.sol";

contract MarketV2Test is Test {
    
    MarketV2 market;
    address gov = address(1);
    address lender;
    address pauseGuardian = address(2);
    address escrowImplementation;
    address fixedDebtManager;
    IDolaBorrowingRights dbr;
    IERC20 collateral;
    IOracle oracle;
    MarketV2.MarketParams marketParams;

    function setUp() external{
        marketParams = MarketV2.MarketParams(
            8000, //cf
            9000, //max liquidation incentive threshold
            1000, //max liquidation incentive
            1000, //max liquidation fee
            9000, //zero liquidaiton fee threshold
            10_000 * 1e18,
            false
        );
        collateral = IERC20(address(new ERC20("Mock Collateral", "MOCK", 18)));
        market = new MarketV2(
                gov,
                lender,
                pauseGuardian,
                escrowImplementation,
                fixedDebtManager,
                dbr,
                collateral,
                oracle,
                marketParams
            );
    }

    function testGetLiquidationIncentiveBps() external {
        uint collateralFactor = marketParams.collateralFactorBps - 1;
        uint liquidationIncentive = market.getLiquidationIncentiveBps(collateralFactor);
        uint maxLiquidationIncentive = marketParams.maxLiquidationIncentiveBps;
        uint thresholdDiff = marketParams.maxLiquidationIncentiveThresholdBps - marketParams.collateralFactorBps;
        assertEq(0, liquidationIncentive, "Liquidation Incentive not 0% when CF below liquidation levels");

        collateralFactor = marketParams.collateralFactorBps;
        liquidationIncentive = market.getLiquidationIncentiveBps(collateralFactor);
        assertEq(0, liquidationIncentive, "Liquidation Incentive not 0% when CF at liquidation threshold");

        collateralFactor = marketParams.maxLiquidationIncentiveThresholdBps;
        liquidationIncentive = market.getLiquidationIncentiveBps(collateralFactor);
        assertEq(maxLiquidationIncentive, liquidationIncentive, "Liquidation Incentive not max when CF at max liquidation threshold");

        collateralFactor = marketParams.maxLiquidationIncentiveThresholdBps + 1;
        liquidationIncentive = market.getLiquidationIncentiveBps(collateralFactor);
        assertEq(maxLiquidationIncentive, liquidationIncentive, "Liquidation Incentive not max when CF above max liquidation threshold");

        collateralFactor = marketParams.collateralFactorBps + thresholdDiff / 10;
        liquidationIncentive = market.getLiquidationIncentiveBps(collateralFactor);
        assertEq(100, liquidationIncentive, "Liquidation Incentive not 1% when 10% to liquidation threshold");

        collateralFactor = marketParams.collateralFactorBps + thresholdDiff / 4;
        liquidationIncentive = market.getLiquidationIncentiveBps(collateralFactor);
        assertEq(250, liquidationIncentive, "Liquidation Incentive not 2.5% when 25% to liquidation threshold");

        collateralFactor = marketParams.collateralFactorBps + thresholdDiff / 2;
        liquidationIncentive = market.getLiquidationIncentiveBps(collateralFactor);
        assertEq(500, liquidationIncentive, "Liquidation Incentive not 5% when 50% to liquidation threshold");

        collateralFactor = marketParams.collateralFactorBps + thresholdDiff * 3 / 4;
        liquidationIncentive = market.getLiquidationIncentiveBps(collateralFactor);
        assertEq(750, liquidationIncentive, "Liquidation Incentive not 7.5% when 75% to liquidation threshold");
    }

    function testGetLiquidationFeeBps() external {
        uint collateralFactor = marketParams.collateralFactorBps - 1;
        uint thresholdDiff = marketParams.zeroLiquidationFeeThresholdBps - marketParams.collateralFactorBps;
        uint liquidationFee = market.getLiquidationFeeBps(collateralFactor);
        uint maxLiquidationFee = marketParams.maxLiquidationFeeBps;
        assertEq(0, liquidationFee, "Liquidation fee not 0% when CF below liquidation levels");
        
        collateralFactor = marketParams.collateralFactorBps;
        liquidationFee = market.getLiquidationFeeBps(collateralFactor);
        assertEq(maxLiquidationFee, liquidationFee, "Liquidation fee not 10% when CF at liquidation levels");

        collateralFactor = marketParams.zeroLiquidationFeeThresholdBps;
        liquidationFee = market.getLiquidationFeeBps(collateralFactor);
        assertEq(0, liquidationFee, "Liquidation fee not 0% when CF at zero fee threshold");

        collateralFactor = marketParams.zeroLiquidationFeeThresholdBps + 1;
        liquidationFee = market.getLiquidationFeeBps(collateralFactor);
        assertEq(0, liquidationFee, "Liquidation fee not 0% when CF above zero fee threshold");

        collateralFactor = marketParams.collateralFactorBps + thresholdDiff/10;
        liquidationFee = market.getLiquidationFeeBps(collateralFactor);
        assertEq(900, liquidationFee, "Liquidation fee not 9% when 10% towards zero fee threshold");

        collateralFactor = marketParams.collateralFactorBps + thresholdDiff/4;
        liquidationFee = market.getLiquidationFeeBps(collateralFactor);
        assertEq(750, liquidationFee, "Liquidation fee not 7.5% when 25% towards zero fee threshold");

        collateralFactor = marketParams.collateralFactorBps + thresholdDiff/2;
        liquidationFee = market.getLiquidationFeeBps(collateralFactor);
        assertEq(500, liquidationFee, "Liquidation fee not 5% when 50% towards zero fee threshold");

        collateralFactor = marketParams.collateralFactorBps + thresholdDiff*3/4;
        liquidationFee = market.getLiquidationFeeBps(collateralFactor);
        assertEq(250, liquidationFee, "Liquidation fee not 2.5% when 75% towards zero fee threshold");

        collateralFactor = marketParams.collateralFactorBps + thresholdDiff*99/100;
        liquidationFee = market.getLiquidationFeeBps(collateralFactor);
        assertEq(10, liquidationFee, "Liquidation fee not 0.1% when 99% towards zero fee threshold");
    }
}
