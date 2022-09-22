// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./FrontierV2Test.sol";
import "../BorrowController.sol";
import "../DBR.sol";
import "../Fed.sol";
import {SimpleERC20Escrow} from "../escrows/SimpleERC20Escrow.sol";
import "../Market.sol";
import "../Oracle.sol";

import "./mocks/ERC20.sol";
import "./mocks/WETH9.sol";
import "./mocks/BorrowContract.sol";
import {EthFeed} from "./mocks/EthFeed.sol";

contract MarketTest is FrontierV2Test {
    bytes onlyGovUnpause = "Only governance can unpause";
    bytes onlyPauseGuardianOrGov = "Only pause guardian or governance can pause";

    BorrowContract borrowContract;

    function setUp() public {
        initialize(replenishmentPriceBps, collateralFactorBps, replenishmentIncentiveBps, liquidationBonusBps, callOnDepositCallback);

        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), 1_000_000e18);
        vm.stopPrank();

        borrowContract = new BorrowContract(address(market), payable(address(WETH)));
    }

    function testDeposit() public {
        gibWeth(user, wethTestAmount);

        vm.startPrank(user);
        deposit(wethTestAmount);
    }

    function testBorrow() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);
        vm.startPrank(user);

        deposit(wethTestAmount);
        market.borrow(wethTestAmount * ethFeed.latestAnswer() * collateralFactorBps / 1e18 / 10_000);
    }

    function testBorrow_Fails_When_BorrowingPaused() public {
        vm.startPrank(gov);
        market.pauseBorrows(true);
        vm.stopPrank();

        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);
        vm.startPrank(user);

        deposit(wethTestAmount);

        uint ethPrice = ethFeed.latestAnswer();
        vm.expectRevert("Borrowing is paused");
        market.borrow(wethTestAmount * ethPrice * collateralFactorBps / 1e18 / 10_000);
    }

    function testBorrow_Fails_When_DeniedByBorrowController() public {
        vm.startPrank(gov);
        market.setBorrowController(IBorrowController(address(borrowController)));
        vm.stopPrank();

        gibWeth(address(borrowContract), wethTestAmount);
        gibDBR(address(borrowContract), wethTestAmount);
        vm.startPrank(user);

        borrowContract.deposit(wethTestAmount);

        uint ethPrice = ethFeed.latestAnswer();
        vm.expectRevert("Denied by borrow controller");
        borrowContract.borrow(wethTestAmount * ethPrice * collateralFactorBps / 1e18 / 10_000);
    }

    function testBorrow_Fails_When_AmountGTCreditLimit() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);
        vm.startPrank(user);

        deposit(wethTestAmount);

        uint ethPrice = ethFeed.latestAnswer();
        vm.expectRevert("Exceeded credit limit");
        market.borrow(wethTestAmount * ethPrice / 1e18);
    }

    function testLiquidate() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user);

        deposit(wethTestAmount);
        market.borrow(wethTestAmount * ethFeed.latestAnswer() * collateralFactorBps / 1e18 / 10_000);

        vm.stopPrank();

        ethFeed.changeAnswer(ethFeed.latestAnswer() * 9 / 10);

        vm.startPrank(user2);
        gibDOLA(user2, 5_000 ether);
        DOLA.approve(address(market), type(uint).max);
        market.liquidate(user, market.debts(user) * market.liquidationFactorBps() / 10_000);
    }

    function testLiquidate_Fails_When_repaidDebtIs0() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user);

        deposit(wethTestAmount);
        market.borrow(wethTestAmount * ethFeed.latestAnswer() * collateralFactorBps / 1e18 / 10_000);

        vm.stopPrank();

        ethFeed.changeAnswer(ethFeed.latestAnswer() * 9 / 10);

        vm.startPrank(user2);
        gibDOLA(user2, 5_000 ether);
        DOLA.approve(address(market), type(uint).max);
        vm.expectRevert("Must repay positive debt");
        market.liquidate(user, 0);
    }

    function testLiquidate_Fails_When_repaidDebtGtLiquidatableDebt() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user);

        deposit(wethTestAmount);
        market.borrow(wethTestAmount * ethFeed.latestAnswer() * collateralFactorBps / 1e18 / 10_000);

        vm.stopPrank();

        ethFeed.changeAnswer(ethFeed.latestAnswer() * 9 / 10);

        vm.startPrank(user2);
        gibDOLA(user2, 5_000 ether);
        DOLA.approve(address(market), type(uint).max);

        uint liquidationAmount = (market.debts(user) * market.liquidationFactorBps() / 10_000) + 1;
        vm.expectRevert("Exceeded liquidation factor");
        market.liquidate(user, liquidationAmount);
    }

    function testLiquidate_Fails_When_UserDebtIsHealthy() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user);

        deposit(wethTestAmount);
        market.borrow(wethTestAmount * ethFeed.latestAnswer() * collateralFactorBps / 1e18 / 10_000);

        vm.stopPrank();

        vm.startPrank(user2);
        gibDOLA(user2, 5_000 ether);
        DOLA.approve(address(market), type(uint).max);

        uint liquidationAmount = market.debts(user);
        vm.expectRevert("User debt is healthy");
        market.liquidate(user, liquidationAmount);
    }

    function testRepay_Successful_OwnBorrow_FullAmount() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user);

        deposit(wethTestAmount);
        market.borrow(wethTestAmount * ethFeed.latestAnswer() * collateralFactorBps / 1e18 / 10_000);

        uint initialUserDebt = market.debts(user);
        uint initialDolaBal = DOLA.balanceOf(user);

        market.repay(user, market.debts(user));

        assertEq(market.debts(user), 0, "user's debt was not paid");
        assertEq(initialDolaBal - initialUserDebt, DOLA.balanceOf(user), "DOLA was not subtracted from user");
    }

    function testRepay_Successful_OtherUserBorrow_FullAmount() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user);

        deposit(wethTestAmount);
        market.borrow(wethTestAmount * ethFeed.latestAnswer() * collateralFactorBps / 1e18 / 10_000);

        vm.stopPrank();
        vm.startPrank(user2);

        uint initialUserDebt = market.debts(user);
        uint initialDolaBal = initialUserDebt * 2;
        gibDOLA(user2, initialDolaBal);

        market.repay(user, market.debts(user));

        assertEq(market.debts(user), 0, "user's debt was not paid");
        assertEq(initialDolaBal - initialUserDebt, DOLA.balanceOf(user2), "DOLA was not subtracted from user2");
    }

    function testForceReplenish() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount / 14);

        vm.startPrank(user);

        deposit(wethTestAmount);
        market.borrow(wethTestAmount * ethFeed.latestAnswer() * collateralFactorBps / 1e18 / 10_000);

        vm.stopPrank();

        vm.warp(block.timestamp + 5 days);
        vm.startPrank(user2);

        market.forceReplenish(user);
    }

    function testForceReplenish_Fails_When_UserHasNoDbrDeficit() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount * 100);

        vm.startPrank(user);

        deposit(wethTestAmount);
        market.borrow(wethTestAmount * ethFeed.latestAnswer() * collateralFactorBps / 1e18 / 10_000);

        vm.stopPrank();
        vm.startPrank(user2);

        vm.expectRevert("No DBR deficit");
        market.forceReplenish(user);
    }

    function testPauseBorrows() public {
        vm.startPrank(gov);

        market.pauseBorrows(true);
        assertEq(market.borrowPaused(), true, "Market wasn't paused");
        market.pauseBorrows(false);
        assertEq(market.borrowPaused(), false, "Market wasn't unpaused");

        vm.stopPrank();
        vm.startPrank(pauseGuardian);
        market.pauseBorrows(true);
        assertEq(market.borrowPaused(), true, "Market wasn't paused");
        vm.expectRevert(onlyGovUnpause);
        market.pauseBorrows(false);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(onlyPauseGuardianOrGov);
        market.pauseBorrows(true);

        vm.expectRevert(onlyGovUnpause);
        market.pauseBorrows(false);
    }

    //Access Control Tests

    function test_accessControl_setOracle() public {
        vm.startPrank(gov);
        market.setOracle(IOracle(address(0)));
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setOracle(IOracle(address(0)));
    }

    function test_accessControl_setBorrowController() public {
        vm.startPrank(gov);
        market.setBorrowController(IBorrowController(address(0)));
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setBorrowController(IBorrowController(address(0)));
    }

    function test_accessControl_setGov() public {
        vm.startPrank(gov);
        market.setGov(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setGov(address(0));
    }

    function test_accessControl_setLender() public {
        vm.startPrank(gov);
        market.setLender(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setLender(address(0));
    }

    function test_accessControl_setPauseGuardian() public {
        vm.startPrank(gov);
        market.setPauseGuardian(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setPauseGuardian(address(0));
    }

    function test_accessControl_setCollateralFactorBps() public {
        vm.startPrank(gov);
        market.setCollateralFactorBps(100);
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setCollateralFactorBps(100);
    }

    function test_accessControl_setReplenismentIncentiveBps() public {
        vm.startPrank(gov);
        market.setReplenismentIncentiveBps(100);
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setReplenismentIncentiveBps(100);
    }

    function test_accessControl_setLiquidationIncentiveBps() public {
        vm.startPrank(gov);
        market.setLiquidationIncentiveBps(100);
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setLiquidationIncentiveBps(100);
    }

    function test_accessControl_recall() public {
        vm.startPrank(address(fed));
        market.recall(100e18);
        vm.stopPrank();

        vm.expectRevert(onlyLender);
        market.recall(100e18);
    }
}