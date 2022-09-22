// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../Fed.sol";
import "./FrontierV2Test.sol";

contract FedTest is FrontierV2Test {
    bytes onlyGovUpper = "ONLY GOV";
    bytes unsupportedMarket = "UNSUPPORTED MARKET";
    bytes tooBig = "AMOUNT TOO BIG";
    bytes pausedMarkets = "CANNOT EXPAND PAUSED MARKETS";

    IMarket marketParameter;

    uint testAmount = 1_000_000e18;

    function setUp() public {
        initialize(replenishmentPriceBps, collateralFactorBps, replenishmentIncentiveBps, liquidationBonusBps, callOnDepositCallback);

        marketParameter = IMarket(address(market));
    }

    function testExpansion() public {
        uint startingDolaBal = DOLA.balanceOf(address(marketParameter));

        vm.startPrank(chair);
        fed.expansion(marketParameter, testAmount);

        assertEq(startingDolaBal + testAmount, DOLA.balanceOf(address(marketParameter)), "Expansion failed - dola balanace");
        assertEq(fed.supplies(marketParameter), testAmount, "Expansion failed - fed accounting");
    }

    function testExpansion_Fails_If_UnsupportedMarket() public {
        vm.startPrank(chair);
        vm.expectRevert(unsupportedMarket);
        fed.expansion(IMarket(address(0)), testAmount);
    }

    function testExpansion_Fails_While_MarketPaused() public {
        vm.startPrank(gov);
        market.pauseBorrows(true);
        vm.stopPrank();

        vm.startPrank(chair);
        vm.expectRevert(pausedMarkets);
        fed.expansion(marketParameter, testAmount);
    }

    function testContraction() public {
        vm.startPrank(chair);
        fed.expansion(marketParameter, testAmount);
        assertEq(fed.supplies(marketParameter), testAmount, "expansion failed - fed accounting");
        assertEq(DOLA.balanceOf(address(marketParameter)), testAmount, "expansion failed - dola balance");

        fed.contraction(marketParameter, testAmount);
        assertEq(fed.supplies(marketParameter), 0, "contraction failed - fed accounting");
        assertEq(DOLA.balanceOf(address(marketParameter)), 0, "contraction failed - dola balance");
    }

    function testContraction_Fails_If_UnsupportedMarket() public {
        vm.startPrank(chair);
        vm.expectRevert(unsupportedMarket);
        fed.contraction(IMarket(address(0)), testAmount);
    }

    function testContraction_Fails_If_Amount_GT_SuppliedDOLA() public {
        vm.startPrank(chair);
        fed.expansion(marketParameter, testAmount);

        vm.expectRevert(tooBig);
        fed.contraction(marketParameter, testAmount + 1);
    }

    function test_takeProfit() public {
        vm.startPrank(chair);
        fed.expansion(marketParameter, testAmount);

        gibDOLA(address(marketParameter), testAmount * 2);

        vm.stopPrank();
        
        uint startingDolaBal = DOLA.balanceOf(gov);
        fed.takeProfit(marketParameter);
        
        assertEq(startingDolaBal + testAmount, DOLA.balanceOf(gov), "takeProfit failed");
    }

    //Access Control
    function test_accessControl_changeGov() public {
        vm.startPrank(gov);
        fed.changeGov(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyGovUpper);
        fed.changeGov(address(0));
    }

    function test_accessControl_changeChair() public {
        vm.startPrank(gov);
        fed.changeChair(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyGovUpper);
        fed.changeChair(address(0));
    }

    function test_accessControl_resign() public {
        vm.startPrank(chair);
        fed.resign();
        vm.stopPrank();

        vm.expectRevert(onlyChair);
        fed.resign();
    }

    function test_accessControl_expansion() public {
        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), 100e18);
        vm.stopPrank();

        vm.expectRevert(onlyChair);
        fed.expansion(IMarket(address(market)), 100e18);
    }

    function test_accessControl_contraction() public {
        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), 100e18);
        fed.contraction(IMarket(address(market)), 100e18);
        fed.expansion(IMarket(address(market)), 100e18);
        vm.stopPrank();

        vm.expectRevert(onlyChair);
        fed.contraction(IMarket(address(market)), 100e18);
    }
}