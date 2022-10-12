// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../DBR.sol";
import "./FrontierV2Test.sol";

contract DBRTest is FrontierV2Test {
    address operator;

    bytes onlyPendingOperator = "ONLY PENDING OPERATOR";
    bytes onlyMinterOperator = "ONLY MINTERS OR OPERATOR";
    bytes onBorrowError = "Only markets can call onBorrow";
    bytes onRepayError = "Only markets can call onRepay";
    bytes onForceReplenishError = "Only markets can call onForceReplenish";

    function setUp() public {
        vm.label(gov, "operator");
        operator = gov;

        initialize(replenishmentPriceBps, collateralFactorBps, replenishmentIncentiveBps, liquidationBonusBps, callOnDepositCallback);

        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), 1_000_000e18);
        vm.stopPrank();
    }

    function testOnBorrow_Reverts_When_UserHasNoDbr() public {
        gibWeth(user, wethTestAmount);

        vm.startPrank(user);

        deposit(wethTestAmount);
        uint borrowAmount = wethTestAmount * ethFeed.latestAnswer() * collateralFactorBps / 1e18 / 10_000;
        vm.expectRevert("Insufficient balance");
        market.borrow(borrowAmount);
    }

    function testOnBorrow_Reverts_When_AccrueDueTokensBringsUserDbrBelow0() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user);

        deposit(wethTestAmount);
        uint borrowAmount = wethTestAmount * ethFeed.latestAnswer() * collateralFactorBps / 1e18 / 10_000;
        market.borrow(borrowAmount / 2);

        vm.warp(block.timestamp + 7 days);

        vm.expectRevert("Insufficient balance");
        market.borrow(borrowAmount / 2);
    }

    function test_BalanceFunctions_ReturnCorrectBalance_WhenAddressHasDeficit() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount / 20);

        vm.startPrank(user);
        deposit(wethTestAmount);
        uint borrowAmount = 1 ether;
        market.borrow(borrowAmount);

        vm.warp(block.timestamp + 365 days);

        assertEq(dbr.balanceOf(user), 0, "balanceOf should be 0 when user has deficit");
        //We give user 0.05 DBR. Borrow 1 DOLA for 1 year, expect to pay 1 DBR. -0.95 DBR should be the deficit.
        assertEq(dbr.deficitOf(user), borrowAmount * 19 / 20, "incorrect deficitOf");
        assertEq(dbr.signedBalanceOf(user), int(0) - int(dbr.deficitOf(user)), "signedBalanceOf should equal negative deficitOf when there is a deficit");

        //ensure balances are the same after accrueDueTokens is called
        dbr.accrueDueTokens(user);
        assertEq(dbr.balanceOf(user), 0, "balanceOf should be 0 when user has deficit");
        assertEq(dbr.deficitOf(user), borrowAmount * 19 / 20, "incorrect deficitOf");
        assertEq(dbr.signedBalanceOf(user), int(0) - int(dbr.deficitOf(user)), "signedBalanceOf should equal negative deficitOf when there is a deficit");
    }

    function test_BalanceFunctions_ReturnCorrectBalance_WhenAddressHasPositiveBalance() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount * 2);

        vm.startPrank(user);
        deposit(wethTestAmount);

        uint borrowAmount = wethTestAmount;
        market.borrow(borrowAmount);

        vm.warp(block.timestamp + 365 days);

        assertEq(dbr.deficitOf(user), 0, "deficitOf should be 0 when user has deficit");
        //We give user 2 DBR. Borrow 1 DOLA for 1 year, expect to pay 1 DBR. 1 DBR should be left as the balance.
        assertEq(dbr.balanceOf(user), borrowAmount, "incorrect dbr balance");
        assertEq(dbr.signedBalanceOf(user), int(dbr.balanceOf(user)), "signedBalanceOf should equal balanceOf when there is a positive balance");

         //ensure balances are the same after accrueDueTokens is called
        dbr.accrueDueTokens(user);
        assertEq(dbr.deficitOf(user), 0, "deficitOf should be 0 when user has deficit");
        assertEq(dbr.balanceOf(user), borrowAmount, "incorrect dbr balance");
        assertEq(dbr.signedBalanceOf(user), int(dbr.balanceOf(user)), "signedBalanceOf should equal balanceOf when there is a positive balance");
    }

    function test_BalanceFunctions_ReturnCorrectBalance_WhenAddressHasZeroBalance() public {
        assertEq(dbr.deficitOf(user), 0, "deficitOf should be 0 when user has no balance");
        assertEq(dbr.balanceOf(user), 0, "balanceOf should be 0 when user has no balance");
        assertEq(dbr.signedBalanceOf(user), 0, "signedBalanceOf should be 0 when user has no balance");

         //ensure balances are the same after accrueDueTokens is called
        dbr.accrueDueTokens(user);
        assertEq(dbr.deficitOf(user), 0, "deficitOf should be 0 when user has no balance");
        assertEq(dbr.balanceOf(user), 0, "balanceOf should be 0 when user has no balance");
        assertEq(dbr.signedBalanceOf(user), 0, "signedBalanceOf should be 0 when user has no balance");
    }

    //Access Control
    function test_accessControl_setPendingOperator() public {
        vm.startPrank(operator);
        dbr.setPendingOperator(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        dbr.setPendingOperator(address(0));
    }

    function test_accessControl_claimOperator() public {
        vm.startPrank(operator);
        dbr.setPendingOperator(user);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(onlyPendingOperator);
        dbr.claimOperator();
        vm.stopPrank();

        vm.startPrank(user);
        dbr.claimOperator();
        assertEq(dbr.operator(), user, "Call to claimOperator failed");
    }

    function test_accessControl_setReplenishmentPriceBps() public {
        vm.startPrank(operator);
        dbr.setReplenishmentPriceBps(100);
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        dbr.setReplenishmentPriceBps(100);
    }

    function test_accessControl_addMinter() public {
        vm.startPrank(operator);
        dbr.addMinter(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        dbr.addMinter(address(0));
    }

    function test_accessControl_removeMinter() public {
        vm.startPrank(operator);
        dbr.removeMinter(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        dbr.removeMinter(address(0));
    }

    function test_accessControl_addMarket() public {
        vm.startPrank(operator);
        dbr.addMarket(address(market));
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        dbr.addMarket(address(market));
    }
    
    function test_accessControl_mint() public {
        vm.startPrank(operator);
        dbr.mint(user, 100);
        assertEq(dbr.balanceOf(user), 100, "mint failed");
        vm.stopPrank();

        vm.startPrank(operator);
        dbr.addMinter(user);
        vm.stopPrank();
        vm.startPrank(user);
        dbr.mint(user, 100);
        assertEq(dbr.balanceOf(user), 200, "mint failed");
        vm.stopPrank();

        vm.expectRevert(onlyMinterOperator);
        dbr.mint(user, 100);
    }

    function test_accessControl_onBorrow() public {
        vm.startPrank(operator);
        vm.expectRevert(onBorrowError);
        dbr.onBorrow(user, 100e18);
    }

    function test_accessControl_onRepay() public {
        vm.startPrank(operator);
        vm.expectRevert(onRepayError);
        dbr.onRepay(user, 100e18);
    }

    function test_accessControl_onForceReplenish() public {
        vm.startPrank(operator);
        vm.expectRevert(onForceReplenishError);
        dbr.onForceReplenish(user);
    }
}
