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
        marketParams = createMarketParams(
            8000, //cf
            9000, //max liquidation incentive threshold
            1000, //max liquidation incentive
            1000, //max liquidation fee
            9000, //zero liquidaiton fee threshold
            10000, //max liquidation factor threshold in whole tokens
            30000, //min liquidation factor threshold in whole tokens
            1000, //min liquidation factor at 10%
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

    function createMarketParams(
        uint16 collateralFactorBps,
        uint16 maxLiquidationIncentiveThresholdBps,
        uint16 maxLiquidationIncentiveBps,
        uint16 maxLiquidationFeeBps,
        uint16 zeroLiquidationFeeThresholdBps,
        uint64 maxLiquidationFactorThreshold,
        uint64 minLiquidationFactorThreshold,
        uint16 minLiquidationFactorBps,
        bool borrowPaused
    ) public pure returns(MarketV2.MarketParams memory){
        MarketV2.MarketParams memory mp;
        mp.collateralFactorBps = collateralFactorBps;
        mp.maxLiquidationIncentiveThresholdBps = maxLiquidationIncentiveThresholdBps;
        mp.maxLiquidationIncentiveBps = maxLiquidationIncentiveBps;
        mp.maxLiquidationFeeBps = maxLiquidationFeeBps;
        mp.zeroLiquidationFeeThresholdBps = zeroLiquidationFeeThresholdBps;
        mp.maxLiquidationFactorThreshold = maxLiquidationFactorThreshold;
        mp.minLiquidationFactorThreshold = minLiquidationFactorThreshold;
        mp.minLiquidationFactorBps = minLiquidationFactorBps;
        mp.borrowPaused = borrowPaused;
        return mp;
    }

    function testCalcLiquidationFactor() external {
        uint collateralValue = marketParams.maxLiquidationFactorThreshold * market.decimals() - 1;
        uint liquidationFactor = market.calcLiquidationFactor(marketParams, collateralValue, market.decimals());
        uint thresholdDiff = marketParams.minLiquidationFactorThreshold * market.decimals() - marketParams.maxLiquidationFactorThreshold * market.decimals();
        assertEq(10000, liquidationFactor, "Liquidation factor not 100% when below max threshold");

        collateralValue = marketParams.maxLiquidationFactorThreshold * market.decimals();
        liquidationFactor = market.calcLiquidationFactor(marketParams, collateralValue, market.decimals());
        assertEq(10000, liquidationFactor, "Liquidation factor not 100% when at max threshold");

        collateralValue = marketParams.minLiquidationFactorThreshold * market.decimals();
        liquidationFactor = market.calcLiquidationFactor(marketParams, collateralValue, market.decimals());
        assertEq(1000, liquidationFactor, "Liquidation factor not 10% when at min threshold");

        collateralValue = marketParams.minLiquidationFactorThreshold * market.decimals() + 1;
        liquidationFactor = market.calcLiquidationFactor(marketParams, collateralValue, market.decimals());
        assertEq(1000, liquidationFactor, "Liquidation factor not 10% when above min threshold");

        collateralValue = thresholdDiff / 10 + marketParams.maxLiquidationFactorThreshold * market.decimals();
        liquidationFactor = market.calcLiquidationFactor(marketParams, collateralValue, market.decimals());
        assertEq(9100, liquidationFactor, "Liquidation factor not 91% when 10% way between max and min threshold");

        collateralValue = thresholdDiff / 4 + marketParams.maxLiquidationFactorThreshold * market.decimals();
        liquidationFactor = market.calcLiquidationFactor(marketParams, collateralValue, market.decimals());
        assertEq(7750, liquidationFactor, "Liquidation factor not 7750% when a quarter way between max and min threshold");

        collateralValue = marketParams.minLiquidationFactorThreshold * market.decimals() / 2 +
            marketParams.maxLiquidationFactorThreshold * market.decimals() / 2;
        liquidationFactor = market.calcLiquidationFactor(marketParams, collateralValue, market.decimals());
        assertEq(5500, liquidationFactor, "Liquidation factor not 55% when midway between max and min threshold");

        collateralValue = thresholdDiff * 3 / 4 + marketParams.maxLiquidationFactorThreshold * market.decimals();
        liquidationFactor = market.calcLiquidationFactor(marketParams, collateralValue, market.decimals());
        assertEq(3250, liquidationFactor, "Liquidation factor not 3250% when three quarter way between max and min threshold");
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
