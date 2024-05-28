// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./FiRMBaseTest.sol";

contract FedTest is FiRMBaseTest {
    bytes onlyGovUpper = "ONLY GOV";
    bytes unsupportedMarket = "UNSUPPORTED MARKET";
    bytes tooBig = "AMOUNT TOO BIG";
    bytes pausedMarkets = "CANNOT EXPAND PAUSED MARKETS";

    IMarket marketParameter;

    uint testAmount = 1_000_000e18;

    function setUp() public {
        initialize(replenishmentPriceBps, collateralFactorBps, replenishmentIncentiveBps, liquidationBonusBps, callOnDepositCallback);

        marketParameter = IMarket(address(market));
        vm.startPrank(chair);
        fed.contraction(marketParameter, fed.supplies(marketParameter)); 
        vm.stopPrank();
    }

    function testExpansion(uint256 amount) public {
        amount = bound(amount, 0, 1e50);
        uint startingDolaBal = DOLA.balanceOf(address(marketParameter));

        vm.startPrank(chair);
        fed.expansion(marketParameter, amount);

        assertEq(startingDolaBal + amount, DOLA.balanceOf(address(marketParameter)), "Expansion failed - dola balance");
        assertEq(fed.supplies(marketParameter), amount, "Expansion failed - fed accounting");
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

    function testContraction(uint256 amount) public {
        amount = bound(amount, 0, 1e50);
        vm.startPrank(chair);
        fed.expansion(marketParameter, amount);
        assertEq(fed.supplies(marketParameter), amount, "expansion failed - fed accounting");
        assertEq(DOLA.balanceOf(address(marketParameter)), amount, "expansion failed - dola balance");

        fed.contraction(marketParameter, amount);
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

    function testGetProfit_Returns0_If_SuppliedDola_GT_MarketDolaValue() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(chair);
        fed.expansion(marketParameter, testAmount);

        vm.stopPrank();
        vm.startPrank(user, user);
        deposit(wethTestAmount);
        market.borrow(getMaxBorrowAmount(wethTestAmount));

        assertLt(DOLA.balanceOf(address(market)), testAmount, "Market DOLA value > Supplied Dola");
        assertEq(fed.getProfit(marketParameter), 0, "getProfit should return 0 since market DOLA value > fed's supplied DOLA");
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

    function test_takeProfit_doesNothing_WhenProfitIs0() public {
        vm.startPrank(chair);
        fed.expansion(marketParameter, testAmount);

        uint startingDolaBal = DOLA.balanceOf(gov);
        fed.takeProfit(marketParameter);
        
        assertEq(startingDolaBal, DOLA.balanceOf(gov), "DOLA balance should be unchanged, there is no profit");
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

    function test_changeSupplyCeiling() public {
        vm.expectRevert("ONLY GOV");
        fed.changeSupplyCeiling(1);
        vm.prank(gov);
        fed.changeSupplyCeiling(1);
        assertEq(fed.supplyCeiling(), 1);
    }

    function test_changeMarketCeiling() public {
        vm.expectRevert("ONLY GOV");
        fed.changeMarketCeiling(IMarket(address(0)), 1);
        vm.prank(gov);
        fed.changeMarketCeiling(IMarket(address(0)), 1);
        assertEq(fed.ceilings(IMarket(address(0))), 1);
    }
}
