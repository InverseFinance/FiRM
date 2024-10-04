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
}
