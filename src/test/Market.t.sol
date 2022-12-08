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
        uint balanceUserBefore = WETH.balanceOf(user); 

        vm.startPrank(user, user);
        deposit(wethTestAmount);
        assertEq(WETH.balanceOf(address(market.predictEscrow(user))), wethTestAmount, "Escrow balance did not increase");
        assertEq(WETH.balanceOf(user), balanceUserBefore - wethTestAmount, "User balance did not decrease");
    }

    function testDeposit2() public {
        gibWeth(user, wethTestAmount);
        uint balanceUserBefore = WETH.balanceOf(user); 

        vm.startPrank(user, user);
        WETH.approve(address(market), wethTestAmount);
        market.deposit(user2, wethTestAmount);
        assertEq(WETH.balanceOf(address(market.predictEscrow(user))), 0, "User balance not 0");
        assertEq(WETH.balanceOf(address(market.predictEscrow(user2))), wethTestAmount, "User2 escrow balance did not increase ");
        assertEq(WETH.balanceOf(user), balanceUserBefore - wethTestAmount, "User balance did not decrease");
        assertEq(WETH.balanceOf(user2), 0, "User2 not 0");
    }

    function testBorrow() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);
        vm.startPrank(user, user);
        uint initialDolaBalance = DOLA.balanceOf(user);
        deposit(wethTestAmount);

        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        market.borrow(borrowAmount);

        assertEq(DOLA.balanceOf(user), initialDolaBalance + borrowAmount, "User balance did not increase by borrowAmount");
    }

    function testBorrow_BurnsCorrectAmountOfDBR_WhenTimePasses() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);
        vm.startPrank(user, user);
        uint initialDolaBalance = DOLA.balanceOf(user);
        deposit(wethTestAmount);

        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        vm.warp(1_000_000);
        uint dbrBal = dbr.balanceOf(user);
        market.borrow(borrowAmount);
        assertEq(dbrBal, wethTestAmount, "DBR balance burned immediately after borrow");
        vm.warp(1_000_001);
        dbr.accrueDueTokens(user);
        assertEq(dbr.balanceOf(user), dbrBal - borrowAmount / 365 days, "DBR balance didn't drop by 1 second worth");

        assertEq(DOLA.balanceOf(user), initialDolaBalance + borrowAmount, "User balance did not increase by borrowAmount");
    }



    function testDepositAndBorrow() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);
        vm.startPrank(user, user);

        uint initialDolaBalance = DOLA.balanceOf(user);
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        uint balanceUserBefore = WETH.balanceOf(user); 
        WETH.approve(address(market), wethTestAmount);
        market.depositAndBorrow(wethTestAmount, borrowAmount);

        assertEq(DOLA.balanceOf(user), initialDolaBalance + borrowAmount, "User balance did not increase by borrowAmount");
        assertEq(WETH.balanceOf(address(market.predictEscrow(user))), wethTestAmount, "Escrow balance did not increase");
        assertEq(WETH.balanceOf(user), balanceUserBefore - wethTestAmount, "User balance did not decrease");
    }

    function testBorrowOnBehalf() public {
        address userPk = vm.addr(1);
        gibWeth(userPk, wethTestAmount);
        gibDBR(userPk, wethTestAmount);
        
        vm.startPrank(userPk, userPk);
        uint maxBorrowAmount = getMaxBorrowAmount(wethTestAmount);
        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                user2,
                                userPk,
                                maxBorrowAmount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(wethTestAmount);
        vm.stopPrank();

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), wethTestAmount, "failed to deposit WETH");
        assertEq(WETH.balanceOf(userPk), 0, "failed to deposit WETH");

        vm.startPrank(user2, user2);
        market.borrowOnBehalf(userPk, maxBorrowAmount, block.timestamp, v, r, s);

        assertEq(DOLA.balanceOf(userPk), 0, "borrowed DOLA went to the wrong user");
        assertEq(DOLA.balanceOf(user2), maxBorrowAmount, "failed to borrow DOLA");
    }

    function testBorrowOnBehalf_Fails_When_InvalidateNonceCalledPrior() public {
        address userPk = vm.addr(1);
        gibWeth(userPk, wethTestAmount);
        gibDBR(userPk, wethTestAmount);
        
        vm.startPrank(userPk);
        uint maxBorrowAmount = getMaxBorrowAmount(wethTestAmount);
        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                user2,
                                userPk,
                                maxBorrowAmount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(wethTestAmount);
        market.invalidateNonce();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert("INVALID_SIGNER");
        market.borrowOnBehalf(userPk, maxBorrowAmount, block.timestamp, v, r, s);
    }

    function testBorrowOnBehalf_Fails_When_DeadlineHasPassed() public {
        address userPk = vm.addr(1);
        gibWeth(userPk, wethTestAmount);
        gibDBR(userPk, wethTestAmount);

        uint timestamp = block.timestamp;
        
        vm.startPrank(userPk);
        uint maxBorrowAmount = getMaxBorrowAmount(wethTestAmount);
        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                user2,
                                userPk,
                                maxBorrowAmount,
                                0,
                                timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(wethTestAmount);
        market.invalidateNonce();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.warp(block.timestamp + 1);
        vm.expectRevert("DEADLINE_EXPIRED");
        market.borrowOnBehalf(userPk, maxBorrowAmount, timestamp, v, r, s);
    }

    function testBorrow_Fails_When_BorrowingPaused() public {
        vm.startPrank(gov);
        market.pauseBorrows(true);
        vm.stopPrank();

        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);
        vm.startPrank(user, user);

        deposit(wethTestAmount);

        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        vm.expectRevert("Borrowing is paused");
        market.borrow(borrowAmount);
    }

    function testBorrow_Fails_When_DeniedByBorrowController() public {
        vm.startPrank(gov);
        market.setBorrowController(IBorrowController(address(borrowController)));
        vm.stopPrank();

        gibWeth(address(borrowContract), wethTestAmount);
        gibDBR(address(borrowContract), wethTestAmount);
        vm.startPrank(user, user);

        borrowContract.deposit(wethTestAmount);

        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        vm.expectRevert("Denied by borrow controller");
        borrowContract.borrow(borrowAmount);
    }

    function testBorrow_Fails_When_AmountGTCreditLimit() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);
        vm.startPrank(user, user);

        deposit(wethTestAmount);

        uint borrowAmount = convertWethToDola(wethTestAmount);
        vm.expectRevert("Exceeded credit limit");
        market.borrow(borrowAmount);
    }

    function testBorrow_Fails_When_NotEnoughDolaInMarket() public {
        vm.startPrank(market.lender());
        market.recall(DOLA.balanceOf(address(market)));
        vm.stopPrank();

        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user, user);
        
        deposit(wethTestAmount);

        vm.expectRevert("SafeMath: subtraction underflow");
        market.borrow(1 ether);
    }

    function testLiquidate_NoLiquidationFee(uint depositAmount, uint liqAmount, uint16 borrowMulti_) public {
        depositAmount = bound(depositAmount, 1e18, 100_000e18);
        liqAmount = bound(liqAmount, 500e18, 200_000_000e18);
        uint borrowMulti = bound(borrowMulti_, 0, 100);

        uint maxBorrowAmount = convertWethToDola(depositAmount) * market.collateralFactorBps() / 10_000;
        uint borrowAmount = maxBorrowAmount * borrowMulti / 100;

        gibWeth(user, depositAmount);
        gibDBR(user, depositAmount);

        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), convertWethToDola(depositAmount));
        vm.stopPrank();

        vm.startPrank(user, user);
        deposit(depositAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        ethFeed.changeAnswer(oracle.getFeedPrice(address(WETH)) * 9 / 10);

        vm.startPrank(user2);
        gibDOLA(user2, liqAmount);
        DOLA.approve(address(market), type(uint).max);

        uint marketDolaBal = DOLA.balanceOf(address(market));
        uint govDolaBal = DOLA.balanceOf(gov);
        uint repayAmount = market.debts(user) * market.liquidationFactorBps() / 10_000;

        if (market.debts(user) <= market.getCreditLimit(user)) {
            vm.expectRevert("User debt is healthy");
            market.liquidate(user, liqAmount);
        } else if (repayAmount < liqAmount) {
            vm.expectRevert("Exceeded liquidation factor");
            market.liquidate(user, liqAmount);
        } else {
            //Successful liquidation
            market.liquidate(user, liqAmount);

            uint expectedReward = convertDolaToWeth(liqAmount);
            expectedReward += expectedReward * market.liquidationIncentiveBps() / 10_000;
            assertEq(expectedReward, WETH.balanceOf(user2), "user2 didn't receive proper liquidation reward");
            assertEq(DOLA.balanceOf(address(market)), marketDolaBal + liqAmount, "market didn't receive repaid DOLA");
            assertEq(DOLA.balanceOf(gov), govDolaBal, "gov should not receive liquidation fee when it's set to 0");
        }
    }

    function testLiquidate_WithLiquidationFee(uint depositAmount, uint liqAmount, uint256 liquidationFeeBps, uint16 borrowMulti_) public {
        depositAmount = bound(depositAmount, 1e18, 100_000e18);
        liqAmount = bound(liqAmount, 500e18, 200_000_000e18);
        uint borrowMulti = bound(borrowMulti_, 0, 100);

        gibWeth(user, depositAmount);
        gibDBR(user, depositAmount);

        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), convertWethToDola(depositAmount));
        vm.stopPrank();

        vm.startPrank(gov);
        liquidationFeeBps = bound(liquidationFeeBps, 1, 10_000);
        vm.assume(liquidationFeeBps > 0 && liquidationFeeBps + market.liquidationIncentiveBps() < 10000);
        market.setLiquidationFeeBps(liquidationFeeBps);
        vm.stopPrank();

        vm.startPrank(user, user);
        deposit(depositAmount);
        uint maxBorrowAmount = convertWethToDola(depositAmount) * market.collateralFactorBps() / 10_000;
        uint borrowAmount = maxBorrowAmount * borrowMulti / 100;
        market.borrow(borrowAmount);
        vm.stopPrank();

        ethFeed.changeAnswer(oracle.getFeedPrice(address(WETH)) * 9 / 10);

        vm.startPrank(user2);
        gibDOLA(user2, liqAmount);
        DOLA.approve(address(market), type(uint).max);

        uint marketDolaBal = DOLA.balanceOf(address(market));
        uint govWethBal = WETH.balanceOf(gov);
        uint repayAmount = market.debts(user) * market.liquidationFactorBps() / 10_000;

        if (market.debts(user) <= market.getCreditLimit(user)) {
            vm.expectRevert("User debt is healthy");
            market.liquidate(user, liqAmount);
        } else if (repayAmount < liqAmount) {
            vm.expectRevert("Exceeded liquidation factor");
            market.liquidate(user, liqAmount);
        } else {
            //Successful liquidation
            market.liquidate(user, liqAmount);

            uint expectedReward = convertDolaToWeth(liqAmount);
            expectedReward += expectedReward * market.liquidationIncentiveBps() / 10_000;
            uint expectedLiquidationFee = convertDolaToWeth(liqAmount) * market.liquidationFeeBps() / 10_000;
            assertEq(expectedReward, WETH.balanceOf(user2), "user2 didn't receive proper liquidation reward");
            assertEq(DOLA.balanceOf(address(market)), marketDolaBal + liqAmount, "market didn't receive repaid DOLA");
            assertEq(WETH.balanceOf(gov), govWethBal + expectedLiquidationFee, "gov didn't receive proper liquidation fee");
        }
    }

    function testLiquidate_Fails_When_repaidDebtIs0() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user, user);

        deposit(wethTestAmount);
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        market.borrow(borrowAmount);

        vm.stopPrank();

        ethFeed.changeAnswer(oracle.getFeedPrice(address(WETH)) * 9 / 10);

        vm.startPrank(user2);
        gibDOLA(user2, 5_000 ether);
        DOLA.approve(address(market), type(uint).max);
        vm.expectRevert("Must repay positive debt");
        market.liquidate(user, 0);
    }

    function testLiquidate_Fails_When_repaidDebtGtLiquidatableDebt() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user, user);

        deposit(wethTestAmount);
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        market.borrow(borrowAmount);

        vm.stopPrank();

        ethFeed.changeAnswer(oracle.getFeedPrice(address(WETH)) * 9 / 10);

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

        vm.startPrank(user, user);

        deposit(wethTestAmount);
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        market.borrow(borrowAmount);

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

        vm.startPrank(user, user);

        deposit(wethTestAmount);
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        market.borrow(borrowAmount);
        
        uint initialMarketBal = DOLA.balanceOf(address(market));
        uint initialUserDebt = market.debts(user);
        uint initialDolaBal = DOLA.balanceOf(user);

        market.repay(user, market.debts(user));

        assertEq(market.debts(user), 0, "user's debt was not paid");
        assertEq(initialDolaBal - initialUserDebt, DOLA.balanceOf(user), "DOLA was not subtracted from user");
        assertEq(initialMarketBal + initialUserDebt, DOLA.balanceOf(address(market)), "Market DOLA balance did not increase");
    }

    function testRepay_Successful_OtherUserBorrow_FullAmount() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user, user);

        deposit(wethTestAmount);
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        market.borrow(borrowAmount);

        vm.stopPrank();
        vm.startPrank(user2);

        uint initialUserDebt = market.debts(user);
        uint initialDolaBal = initialUserDebt * 2;
        gibDOLA(user2, initialDolaBal);

        market.repay(user, market.debts(user));

        assertEq(market.debts(user), 0, "user's debt was not paid");
        assertEq(initialDolaBal - initialUserDebt, DOLA.balanceOf(user2), "DOLA was not subtracted from user2");
    }

    function testRepay_RepaysDebt_WhenAmountSetToMaxUint() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);
        gibDOLA(user, 500e18);

        vm.startPrank(user, user);

        deposit(wethTestAmount);
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        market.borrow(borrowAmount);
        uint dolaBalAfterBorrow = DOLA.balanceOf(user);
        uint debtAfterBorrow = market.debts(user);

        market.repay(user, type(uint).max);
        assertEq(dolaBalAfterBorrow-borrowAmount, DOLA.balanceOf(user));
        assertEq(market.debts(user), 0);
    }


    function testRepay_Fails_WhenAmountGtThanDebt() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);
        gibDOLA(user, 500e18);

        vm.startPrank(user);

        deposit(wethTestAmount);
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        market.borrow(borrowAmount);
        uint dolaBalAfterBorrow = DOLA.balanceOf(user);
        uint debtAfterBorrow = market.debts(user);
        
        vm.expectRevert("Repayment greater than debt");
        market.repay(user, borrowAmount + 1);
    }

    function testForceReplenish() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount / 14);
        uint initialReplenisherDola = DOLA.balanceOf(replenisher);

        vm.startPrank(user, user);
        deposit(wethTestAmount);
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        market.borrow(borrowAmount);
        uint initialUserDebt = market.debts(user);
        uint initialMarketDola = DOLA.balanceOf(address(market));
        vm.stopPrank();

        vm.warp(block.timestamp + 5 days);
        uint deficitBefore = dbr.deficitOf(user);
        vm.startPrank(replenisher);

        market.forceReplenish(user, deficitBefore);
        assertGt(DOLA.balanceOf(replenisher), initialReplenisherDola, "DOLA balance of replenisher did not increase");
        assertLt(DOLA.balanceOf(address(market)), initialMarketDola, "DOLA balance of market did not decrease");
        assertEq(DOLA.balanceOf(replenisher) - initialReplenisherDola, initialMarketDola - DOLA.balanceOf(address(market)), "DOLA balance of market did not decrease by amount paid to replenisher");
        assertEq(dbr.deficitOf(user), 0, "Deficit of borrower was not fully replenished");
        assertEq(market.debts(user) - initialUserDebt, deficitBefore * replenishmentPriceBps / 10000, "Debt of borrower did not increase by replenishment price");
    }

    function testForceReplenish_Fails_When_UserHasNoDbrDeficit() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount * 100);

        vm.startPrank(user, user);

        deposit(wethTestAmount);
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        market.borrow(borrowAmount);
        uint deficit = dbr.deficitOf(user);

        vm.stopPrank();
        vm.startPrank(user2);

        vm.expectRevert("No DBR deficit");
        market.forceReplenish(user, deficit);
    }

    function testForceReplenish_Fails_When_NotEnoughDolaInMarket() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount / 14);

        vm.startPrank(user, user);
        deposit(wethTestAmount);
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        market.borrow(borrowAmount);

        vm.warp(block.timestamp + 5 days);
        vm.stopPrank();
        vm.startPrank(market.lender());
        market.recall(DOLA.balanceOf(address(market)));
        uint deficit = dbr.deficitOf(user);
        vm.stopPrank();
        vm.startPrank(replenisher);   
        vm.expectRevert("SafeMath: subtraction underflow");
        market.forceReplenish(user, deficit);   
    }

    function testForceReplenish_Fails_When_DebtWouldExceedCollateralValue() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount / 14);

        vm.startPrank(user, user);
        deposit(wethTestAmount);
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        market.borrow(borrowAmount);

        vm.warp(block.timestamp + 10000 days);
        uint deficit = dbr.deficitOf(user);
        vm.stopPrank();

        vm.startPrank(replenisher);
        vm.expectRevert("Exceeded collateral value");
        market.forceReplenish(user, deficit);   
    }

    function testForceReplenish_Succeed_When_PartiallyReplenishedDebtExceedCollateralValue() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount / 14);

        vm.startPrank(user, user);
        deposit(wethTestAmount);
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        market.borrow(borrowAmount);

        vm.warp(block.timestamp + 10000 days);
        uint deficit = dbr.deficitOf(user);
        vm.stopPrank();

        vm.startPrank(replenisher, replenisher);
        uint maxDebt = market.getCollateralValue(user) * (10000 - market.liquidationIncentiveBps() - market.liquidationFeeBps()) / 10000;
        market.forceReplenish(user, maxDebt - market.debts(user));
        assertEq(market.debts(user), maxDebt);
        assertLt(dbr.deficitOf(user), deficit, "Deficit didn't shrink");
    }

    function testGetWithdrawalLimit_Returns_CollateralBalance() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user, user);
        deposit(wethTestAmount);

        uint collateralBalance = market.escrows(user).balance();
        assertEq(collateralBalance, wethTestAmount);
        assertEq(market.getWithdrawalLimit(user), collateralBalance, "Should return collateralBalance when user's escrow balance > 0 & debts = 0");
    }

    function testGetWithdrawalLimit_Returns_CollateralBalanceAdjustedForDebts() public {
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user, user);
        deposit(wethTestAmount);
        market.borrow(borrowAmount);
        uint collateralBalance = market.escrows(user).balance();
        uint collateralFactor = market.collateralFactorBps();
        uint minimumCollateral = borrowAmount * 1 ether / oracle.viewPrice(address(WETH), collateralFactor) * 10000 / collateralFactor;
        assertEq(market.getWithdrawalLimit(user), collateralBalance - minimumCollateral, "Should return collateral balance adjusted for debt");
    }

    function testGetWithdrawalLimit_Returns_0_WhenEscrowBalanceIs0() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user, user);
        deposit(wethTestAmount);

        uint collateralBalance = market.escrows(user).balance();
        assertEq(collateralBalance, wethTestAmount);

        market.withdraw(wethTestAmount);
        assertEq(market.getWithdrawalLimit(user), 0, "Should return 0 when user's escrow balance is 0");
    }

    function testGetWithdrawalLimit_Returns_0_WhenCollateralValueLtDebts() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user, user);
        deposit(wethTestAmount);

        uint collateralBalance = market.escrows(user).balance();
        assertEq(collateralBalance, wethTestAmount);
        market.withdraw(wethTestAmount);

        uint ethPrice = oracle.getFeedPrice(address(WETH));
        ethFeed.changeAnswer(ethPrice * 6 / 10);
        assertEq(market.getWithdrawalLimit(user), 0, "Should return 0 when user's collateral value is less than debts");
        ethFeed.changeAnswer(ethPrice);
    }

    function testGetWithdrawalLimit_Returns_0_WhenMarketCollateralFactoris0() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user, user);
        deposit(wethTestAmount);
        market.borrow(1);
        vm.stopPrank();

        vm.startPrank(gov);
        market.setCollateralFactorBps(0);
        assertEq(market.getWithdrawalLimit(user), 0, "Should return 0 when user has non-zero debt & collateralFactorBps = 0");
    }

    function testGetLiquidatableDebt_Returns_0_WhenUserHasNoDebt() public {
        assertEq(market.getLiquidatableDebt(user), 0, "Should return 0 when user has no debt");
    }

    function testGetLiquidatableDebt_Returns_0_WhenUserCreditEqualsDebt() public {
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user, user);
        deposit(wethTestAmount);
        market.borrow(borrowAmount);

        assertEq(market.getLiquidatableDebt(user), 0, "Should return 0 when user credit = debt");
    }

    function testGetLiquidatableDebt_Returns_LiquidatableDebt_WhenUserDebtGtCredit() public {
        uint borrowAmount = getMaxBorrowAmount(wethTestAmount);
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user, user);
        deposit(wethTestAmount);
        market.borrow(borrowAmount);

        ethFeed.changeAnswer(oracle.getFeedPrice(address(WETH)) * 5 / 10);

        assertGt(market.getLiquidatableDebt(user), 0, "Should return liquidatable debt when user debt > credit");
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

        vm.startPrank(user, user);
        vm.expectRevert(onlyPauseGuardianOrGov);
        market.pauseBorrows(true);

        vm.expectRevert(onlyGovUnpause);
        market.pauseBorrows(false);
    }

    function testWithdraw() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);
        vm.startPrank(user, user);

        deposit(wethTestAmount);

        assertEq(WETH.balanceOf(address(market.escrows(user))), wethTestAmount, "failed to deposit WETH");
        assertEq(WETH.balanceOf(user), 0, "failed to deposit WETH");

        market.withdraw(wethTestAmount);

        assertEq(WETH.balanceOf(address(market.escrows(user))), 0, "failed to withdraw WETH");
        assertEq(WETH.balanceOf(user), wethTestAmount, "failed to withdraw WETH");
    }

    function testWithdraw_Fail_When_WithdrawingCollateralBelowCF() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);
        vm.startPrank(user, user);

        deposit(wethTestAmount);

        assertEq(WETH.balanceOf(address(market.escrows(user))), wethTestAmount, "failed to deposit WETH");
        assertEq(WETH.balanceOf(user), 0, "failed to deposit WETH");

        market.borrow(1 ether);

        vm.expectRevert("Insufficient withdrawal limit");
        market.withdraw(wethTestAmount);

        assertEq(WETH.balanceOf(address(market.escrows(user))), wethTestAmount, "successfully withdrew WETH");
        assertEq(WETH.balanceOf(user), 0, "successfully withdrew WETH");
    }

    function testWithdrawOnBehalf() public {
        address userPk = vm.addr(1);
        gibWeth(userPk, wethTestAmount);
        gibDBR(userPk, wethTestAmount);
        
        vm.startPrank(userPk);
        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                user2,
                                userPk,
                                wethTestAmount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(wethTestAmount);
        vm.stopPrank();

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), wethTestAmount, "failed to deposit WETH");
        assertEq(WETH.balanceOf(userPk), 0, "failed to deposit WETH");

        vm.startPrank(user2);
        market.withdrawOnBehalf(userPk, wethTestAmount, block.timestamp, v, r, s);

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), 0, "failed to withdraw WETH");
        assertEq(WETH.balanceOf(user2), wethTestAmount, "failed to withdraw WETH");
    }

    function testWithdrawOnBehalf_When_InvalidateNonceCalledPrior() public {
        address userPk = vm.addr(1);
        gibWeth(userPk, wethTestAmount);
        gibDBR(userPk, wethTestAmount);
        
        vm.startPrank(userPk);
        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                user2,
                                userPk,
                                wethTestAmount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(wethTestAmount);
        market.invalidateNonce();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert("INVALID_SIGNER");
        market.withdrawOnBehalf(userPk, wethTestAmount, block.timestamp, v, r, s);
    }

    function testWithdrawOnBehalf_When_DeadlineHasPassed() public {
        address userPk = vm.addr(1);
        gibWeth(userPk, wethTestAmount);
        gibDBR(userPk, wethTestAmount);

        uint timestamp = block.timestamp;
        
        vm.startPrank(userPk);
        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                user2,
                                userPk,
                                wethTestAmount,
                                0,
                                timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(wethTestAmount);
        market.invalidateNonce();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.warp(block.timestamp + 1);
        vm.expectRevert("DEADLINE_EXPIRED");
        market.withdrawOnBehalf(userPk, wethTestAmount, timestamp, v, r, s);
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

        vm.expectRevert("Invalid collateral factor");
        market.setCollateralFactorBps(10001);
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setCollateralFactorBps(100);
    }

    function test_accessControl_setReplenismentIncentiveBps() public {
        vm.startPrank(gov);
        market.setReplenismentIncentiveBps(100);

        vm.expectRevert("Invalid replenishment incentive");
        market.setReplenismentIncentiveBps(10001);
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setReplenismentIncentiveBps(100);
    }

    function test_accessControl_setLiquidationIncentiveBps() public {
        vm.startPrank(gov);
        market.setLiquidationIncentiveBps(100);

        vm.expectRevert("Invalid liquidation incentive");
        market.setLiquidationIncentiveBps(0);
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setLiquidationIncentiveBps(100);
    }

    function test_accessControl_setLiquidationFactorBps() public {
        vm.startPrank(gov);
        market.setLiquidationFactorBps(100);

        vm.expectRevert("Invalid liquidation factor");
        market.setLiquidationFactorBps(0);
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setLiquidationFactorBps(100);
    }

    function test_accessControl_setLiquidationFeeBps() public {
        vm.startPrank(gov);
        market.setLiquidationFeeBps(100);

        vm.expectRevert("Invalid liquidation fee");
        market.setLiquidationFeeBps(0);
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setLiquidationFeeBps(100);
    }

    function test_accessControl_recall() public {
        vm.startPrank(address(fed));
        market.recall(100e18);
        vm.stopPrank();

        vm.expectRevert(onlyLender);
        market.recall(100e18);
    }
}
