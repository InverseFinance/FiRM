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