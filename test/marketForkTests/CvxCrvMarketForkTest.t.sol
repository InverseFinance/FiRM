// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketForkTest.sol";
import {ConvexCurvePriceFeed} from "src/feeds/ConvexCurvePriceFeed.sol";
import "src/DBR.sol";
import "src/Fed.sol";
import {Market} from "src/Market.sol";
import "src/Oracle.sol";
import {ConvexCurveEscrow, ICvxCrvStakingWrapper} from "src/escrows/ConvexCurveEscrow.sol";

import {BorrowContract} from "test/mocks/BorrowContract.sol";

contract CvxCrvMarketForkTest is MarketForkTest {
    bytes onlyGovUnpause = "Only governance can unpause";
    bytes onlyPauseGuardianOrGov =
        "Only pause guardian or governance can pause";
    address lender = 0x2b34548b865ad66A2B046cb82e59eE43F75B90fd;
    IERC20 cvxCrv = IERC20(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7);
    ICvxCrvStakingWrapper stakingWrapper =
        ICvxCrvStakingWrapper(0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434);

    BorrowContract borrowContract;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 18000000);
        ConvexCurvePriceFeed cvxCrvFeed = ConvexCurvePriceFeed(
            0x0266445Ea652F8467cbaA344Fcf531FF8f3d6462
        );
        Market cvxCrvMarket = Market(
            0x3474ad0e3a9775c9F68B415A7a9880B0CAB9397a
        ); //new Market(gov, lender, pauseGuardian, address(escrow), IDolaBorrowingRights(address(dbr)), cvxCrv, IOracle(address(oracle)), 5000, 5000, 1000, true);
        init(address(cvxCrvMarket), address(cvxCrvFeed));
        if (market.borrowPaused()) {
            vm.prank(gov, gov);
            market.pauseBorrows(false);
        }
        vm.startPrank(chair, chair);
        fed.expansion(IMarket(address(market)), 100_000e18);
        vm.stopPrank();

        borrowContract = new BorrowContract(
            address(market),
            payable(address(collateral))
        );
    }

    function testDeposit() public {
        gibCollateral(user, testAmount);
        uint balanceUserBefore = collateral.balanceOf(user);

        vm.startPrank(user, user);
        deposit(testAmount);
        assertEq(
            stakingWrapper.balanceOf(address(market.predictEscrow(user))),
            testAmount,
            "Escrow balance did not increase"
        );
        assertEq(
            collateral.balanceOf(user),
            balanceUserBefore - testAmount,
            "User balance did not decrease"
        );
    }

    function testDeposit2() public {
        gibCollateral(user, testAmount);
        uint balanceUserBefore = collateral.balanceOf(user);

        vm.startPrank(user, user);
        collateral.approve(address(market), testAmount);
        market.deposit(user2, testAmount);
        assertEq(
            stakingWrapper.balanceOf(address(market.predictEscrow(user))),
            0,
            "User balance not 0"
        );
        assertEq(
            stakingWrapper.balanceOf(address(market.predictEscrow(user2))),
            testAmount,
            "User2 escrow balance did not increase "
        );
        assertEq(
            collateral.balanceOf(user),
            balanceUserBefore - testAmount,
            "User balance did not decrease"
        );
        assertEq(collateral.balanceOf(user2), 0, "User2 not 0");
    }

    function testBorrow() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);
        uint initialDolaBalance = DOLA.balanceOf(user);
        deposit(testAmount);

        uint borrowAmount = getMaxBorrowAmount(testAmount);
        market.borrow(borrowAmount);

        assertEq(
            DOLA.balanceOf(user),
            initialDolaBalance + borrowAmount,
            "User balance did not increase by borrowAmount"
        );
    }

    function testBorrow_BurnsCorrectAmountOfDBR_WhenTimePasses() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);
        uint initialDolaBalance = DOLA.balanceOf(user);
        deposit(testAmount);

        uint borrowAmount = getMaxBorrowAmount(testAmount);
        uint timestamp = block.timestamp;
        vm.warp(timestamp + 1_000_000);
        uint dbrBal = dbr.balanceOf(user);
        market.borrow(borrowAmount);
        assertEq(
            dbrBal,
            testAmount,
            "DBR balance burned immediately after borrow"
        );
        vm.warp(timestamp + 1_000_001);
        dbr.accrueDueTokens(user);
        assertEq(
            dbr.balanceOf(user),
            dbrBal - borrowAmount / 365 days,
            "DBR balance didn't drop by 1 second worth"
        );

        assertEq(
            DOLA.balanceOf(user),
            initialDolaBalance + borrowAmount,
            "User balance did not increase by borrowAmount"
        );
    }

    function testDepositAndBorrow() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);

        uint initialDolaBalance = DOLA.balanceOf(user);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        uint balanceUserBefore = collateral.balanceOf(user);
        collateral.approve(address(market), testAmount);
        market.depositAndBorrow(testAmount, borrowAmount);

        assertEq(
            DOLA.balanceOf(user),
            initialDolaBalance + borrowAmount,
            "User balance did not increase by borrowAmount"
        );
        assertEq(
            stakingWrapper.balanceOf(address(market.predictEscrow(user))),
            testAmount,
            "Escrow balance did not increase"
        );
        assertEq(
            collateral.balanceOf(user),
            balanceUserBefore - testAmount,
            "User balance did not decrease"
        );
    }

    function testBorrowOnBehalf() public {
        address userPk = vm.addr(1);
        gibCollateral(userPk, testAmount);
        gibDBR(userPk, testAmount);

        vm.startPrank(userPk, userPk);
        uint maxBorrowAmount = getMaxBorrowAmount(testAmount);
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

        deposit(testAmount);
        vm.stopPrank();

        assertEq(
            stakingWrapper.balanceOf(address(market.predictEscrow(userPk))),
            testAmount,
            "failed to deposit collateral"
        );
        assertEq(
            collateral.balanceOf(userPk),
            0,
            "failed to deposit collateral"
        );

        vm.startPrank(user2, user2);
        market.borrowOnBehalf(
            userPk,
            maxBorrowAmount,
            block.timestamp,
            v,
            r,
            s
        );

        assertEq(
            DOLA.balanceOf(userPk),
            0,
            "borrowed DOLA went to the wrong user"
        );
        assertEq(
            DOLA.balanceOf(user2),
            maxBorrowAmount,
            "failed to borrow DOLA"
        );
    }

    function testBorrowOnBehalf_Fails_When_InvalidateNonceCalledPrior() public {
        address userPk = vm.addr(1);
        gibCollateral(userPk, testAmount);
        gibDBR(userPk, testAmount);

        vm.startPrank(userPk);
        uint maxBorrowAmount = getMaxBorrowAmount(testAmount);
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

        deposit(testAmount);
        market.invalidateNonce();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert("INVALID_SIGNER");
        market.borrowOnBehalf(
            userPk,
            maxBorrowAmount,
            block.timestamp,
            v,
            r,
            s
        );
    }

    function testBorrowOnBehalf_Fails_When_DeadlineHasPassed() public {
        address userPk = vm.addr(1);
        gibCollateral(userPk, testAmount);
        gibDBR(userPk, testAmount);

        uint timestamp = block.timestamp;

        vm.startPrank(userPk);
        uint maxBorrowAmount = getMaxBorrowAmount(testAmount);
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

        deposit(testAmount);
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

        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);

        deposit(testAmount);

        uint borrowAmount = getMaxBorrowAmount(testAmount);
        vm.expectRevert("Borrowing is paused");
        market.borrow(borrowAmount);
    }

    function testBorrow_Fails_When_DeniedByBorrowController() public {
        vm.startPrank(gov);
        market.setBorrowController(
            IBorrowController(address(borrowController))
        );
        vm.stopPrank();

        gibCollateral(address(borrowContract), testAmount);
        gibDBR(address(borrowContract), testAmount);
        vm.startPrank(user, user);

        borrowContract.deposit(testAmount);

        uint borrowAmount = getMaxBorrowAmount(testAmount);
        vm.expectRevert("Denied by borrow controller");
        borrowContract.borrow(borrowAmount);
    }

    function testBorrow_Fails_When_AmountGTCreditLimit() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);

        deposit(testAmount);

        uint borrowAmount = convertCollatToDola(testAmount);
        vm.expectRevert("Exceeded credit limit");
        market.borrow(borrowAmount);
    }

    function testBorrow_Fails_When_NotEnoughDolaInMarket() public {
        vm.startPrank(market.lender());
        market.recall(DOLA.balanceOf(address(market)));
        vm.stopPrank();

        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);

        vm.startPrank(user, user);

        uint borrowAmount = getMaxBorrowAmount(testAmount);
        deposit(testAmount);

        vm.expectRevert("SafeMath: subtraction underflow");
        market.borrow(borrowAmount);
    }

    /**
    function testLiquidate_NoLiquidationFee(uint depositAmount, uint liqAmount, uint16 borrowMulti_) public {
        depositAmount = bound(depositAmount, 1e18, 100_000e18);
        liqAmount = bound(liqAmount, 500e18, 200_000_000e18);
        uint borrowMulti = bound(borrowMulti_, 0, 100);

        uint maxBorrowAmount = convertCollatToDola(depositAmount) * market.collateralFactorBps() / 10_000;
        uint borrowAmount = maxBorrowAmount * borrowMulti / 100;

        gibCollateral(user, depositAmount);
        gibDBR(user, depositAmount);

        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), convertCollatToDola(depositAmount));
        vm.stopPrank();

        vm.startPrank(user, user);
        deposit(depositAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        feed.changeAnswer(oracle.getFeedPrice(address(collateral)) * 9 / 10);

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

            uint expectedReward = convertDolaToCollat(liqAmount);
            expectedReward += expectedReward * market.liquidationIncentiveBps() / 10_000;
            assertEq(expectedReward, collateral.balanceOf(user2), "user2 didn't receive proper liquidation reward");
            assertEq(DOLA.balanceOf(address(market)), marketDolaBal + liqAmount, "market didn't receive repaid DOLA");
            assertEq(DOLA.balanceOf(gov), govDolaBal, "gov should not receive liquidation fee when it's set to 0");
        }
    }
    function testLiquidate_WithLiquidationFee(uint depositAmount, uint liqAmount, uint256 liquidationFeeBps, uint16 borrowMulti_) public {
        depositAmount = bound(depositAmount, 1e18, 100_000e18);
        liqAmount = bound(liqAmount, 500e18, 200_000_000e18);
        uint borrowMulti = bound(borrowMulti_, 0, 100);

        gibCollateral(user, depositAmount);
        gibDBR(user, depositAmount);

        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), convertCollatToDola(depositAmount));
        vm.stopPrank();

        vm.startPrank(gov);
        liquidationFeeBps = bound(liquidationFeeBps, 1, 10_000);
        vm.assume(liquidationFeeBps > 0 && liquidationFeeBps + market.liquidationIncentiveBps() < 10000);
        market.setLiquidationFeeBps(liquidationFeeBps);
        vm.stopPrank();

        vm.startPrank(user, user);
        deposit(depositAmount);
        uint maxBorrowAmount = convertCollatToDola(depositAmount) * market.collateralFactorBps() / 10_000;
        uint borrowAmount = maxBorrowAmount * borrowMulti / 100;
        market.borrow(borrowAmount);
        vm.stopPrank();

        feed.changeAnswer(oracle.getFeedPrice(address(collateral)) * 9 / 10);

        vm.startPrank(user2);
        gibDOLA(user2, liqAmount);
        DOLA.approve(address(market), type(uint).max);

        uint marketDolaBal = DOLA.balanceOf(address(market));
        uint govWethBal = collateral.balanceOf(gov);
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

            uint expectedReward = convertDolaToCollat(liqAmount);
            expectedReward += expectedReward * market.liquidationIncentiveBps() / 10_000;
            uint expectedLiquidationFee = convertDolaToCollat(liqAmount) * market.liquidationFeeBps() / 10_000;
            assertEq(expectedReward, collateral.balanceOf(user2), "user2 didn't receive proper liquidation reward");
            assertEq(DOLA.balanceOf(address(market)), marketDolaBal + liqAmount, "market didn't receive repaid DOLA");
            assertEq(collateral.balanceOf(gov), govWethBal + expectedLiquidationFee, "gov didn't receive proper liquidation fee");
        }
    }

    function testLiquidate_Fails_When_repaidDebtIs0() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);

        vm.startPrank(user, user);

        deposit(testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        market.borrow(borrowAmount);

        vm.stopPrank();

        feed.changeAnswer(oracle.getFeedPrice(address(collateral)) * 9 / 10);

        vm.startPrank(user2);
        gibDOLA(user2, 5_000 ether);
        DOLA.approve(address(market), type(uint).max);
        vm.expectRevert("Must repay positive debt");
        market.liquidate(user, 0);
    }

    function testLiquidate_Fails_When_repaidDebtGtLiquidatableDebt() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);

        vm.startPrank(user, user);

        deposit(testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        market.borrow(borrowAmount);

        vm.stopPrank();

        feed.changeAnswer(oracle.getFeedPrice(address(collateral)) * 9 / 10);

        gibDOLA(user2, 5_000 ether);
        vm.startPrank(user2);
        DOLA.approve(address(market), type(uint).max);

        uint liquidationAmount = (market.debts(user) * market.liquidationFactorBps() / 10_000) + 1;
        vm.expectRevert("Exceeded liquidation factor");
        market.liquidate(user, liquidationAmount);
    }
    */

    function testLiquidate_Fails_When_UserDebtIsHealthy() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);

        vm.startPrank(user, user);
        deposit(testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        market.borrow(borrowAmount);

        vm.stopPrank();

        gibDOLA(user2, 5_000 ether);
        vm.startPrank(user2);
        DOLA.approve(address(market), type(uint).max);

        uint liquidationAmount = market.debts(user);
        vm.expectRevert("User debt is healthy");
        market.liquidate(user, liquidationAmount);
    }

    function testRepay_Successful_OwnBorrow_FullAmount() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);

        vm.startPrank(user, user);

        deposit(testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        market.borrow(borrowAmount);

        uint initialMarketBal = DOLA.balanceOf(address(market));
        uint initialUserDebt = market.debts(user);
        uint initialDolaBal = DOLA.balanceOf(user);

        DOLA.approve(address(market), market.debts(user));
        market.repay(user, market.debts(user));

        assertEq(market.debts(user), 0, "user's debt was not paid");
        assertEq(
            initialDolaBal - initialUserDebt,
            DOLA.balanceOf(user),
            "DOLA was not subtracted from user"
        );
        assertEq(
            initialMarketBal + initialUserDebt,
            DOLA.balanceOf(address(market)),
            "Market DOLA balance did not increase"
        );
    }

    function testRepay_Successful_OtherUserBorrow_FullAmount() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);

        vm.startPrank(user, user);

        deposit(testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        market.borrow(borrowAmount);

        vm.stopPrank();

        uint initialUserDebt = market.debts(user);
        uint initialDolaBal = initialUserDebt * 2;
        gibDOLA(user2, initialDolaBal);

        vm.startPrank(user2);
        DOLA.approve(address(market), market.debts(user));
        market.repay(user, market.debts(user));

        assertEq(market.debts(user), 0, "user's debt was not paid");
        assertEq(
            initialDolaBal - initialUserDebt,
            DOLA.balanceOf(user2),
            "DOLA was not subtracted from user2"
        );
    }

    function testRepay_RepaysDebt_WhenAmountSetToMaxUint() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        gibDOLA(user, 500e18);

        vm.startPrank(user, user);

        deposit(testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        market.borrow(borrowAmount);
        uint dolaBalAfterBorrow = DOLA.balanceOf(user);

        DOLA.approve(address(market), market.debts(user));
        market.repay(user, type(uint).max);
        assertEq(dolaBalAfterBorrow - borrowAmount, DOLA.balanceOf(user));
        assertEq(market.debts(user), 0);
    }

    function testRepay_Fails_WhenAmountGtThanDebt() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        gibDOLA(user, 500e18);

        vm.startPrank(user, user);

        deposit(testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        market.borrow(borrowAmount);

        vm.expectRevert("Repayment greater than debt");
        market.repay(user, borrowAmount + 1);
    }

    function testForceReplenish() public {
        gibCollateral(user, testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        gibDBR(user, borrowAmount / 365);
        uint initialReplenisherDola = DOLA.balanceOf(replenisher);

        vm.startPrank(user, user);
        deposit(testAmount);
        market.borrow(borrowAmount);
        uint initialUserDebt = market.debts(user);
        uint initialMarketDola = DOLA.balanceOf(address(market));
        vm.stopPrank();

        vm.warp(block.timestamp + 5 days);
        uint deficitBefore = dbr.deficitOf(user);
        vm.startPrank(replenisher);

        market.forceReplenish(user, deficitBefore);
        assertGt(
            DOLA.balanceOf(replenisher),
            initialReplenisherDola,
            "DOLA balance of replenisher did not increase"
        );
        assertLt(
            DOLA.balanceOf(address(market)),
            initialMarketDola,
            "DOLA balance of market did not decrease"
        );
        assertEq(
            DOLA.balanceOf(replenisher) - initialReplenisherDola,
            initialMarketDola - DOLA.balanceOf(address(market)),
            "DOLA balance of market did not decrease by amount paid to replenisher"
        );
        assertEq(
            dbr.deficitOf(user),
            0,
            "Deficit of borrower was not fully replenished"
        );
        assertEq(
            market.debts(user) - initialUserDebt,
            (deficitBefore * replenishmentPriceBps) / 10000,
            "Debt of borrower did not increase by replenishment price"
        );
    }

    function testForceReplenish_Fails_When_UserHasNoDbrDeficit() public {
        gibCollateral(user, testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        gibDBR(user, testAmount * 100);

        vm.startPrank(user, user);

        deposit(testAmount);
        market.borrow(borrowAmount);
        uint deficit = dbr.deficitOf(user);

        vm.stopPrank();
        vm.startPrank(user2);

        vm.expectRevert("No DBR deficit");
        market.forceReplenish(user, deficit);
    }

    function testForceReplenish_Fails_When_NotEnoughDolaInMarket() public {
        gibCollateral(user, testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        gibDBR(user, borrowAmount / 365);

        vm.startPrank(user, user);
        deposit(testAmount);
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

    function testForceReplenish_Fails_When_DebtWouldExceedCollateralValue()
        public
    {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount / 14);

        vm.startPrank(user, user);
        deposit(testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        market.borrow(borrowAmount);

        vm.warp(block.timestamp + 10000 days);
        uint deficit = dbr.deficitOf(user);
        vm.stopPrank();

        vm.startPrank(replenisher);
        vm.expectRevert("Exceeded collateral value");
        market.forceReplenish(user, deficit);
    }

    function testForceReplenish_Succeed_When_PartiallyReplenishedDebtExceedCollateralValue()
        public
    {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount / 14);

        vm.startPrank(user, user);
        deposit(testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        market.borrow(borrowAmount);

        vm.warp(block.timestamp + 1000 days);
        uint deficit = dbr.deficitOf(user);
        vm.stopPrank();

        vm.startPrank(replenisher, replenisher);
        uint maxDebt = (market.getCollateralValue(user) *
            (10000 -
                market.liquidationIncentiveBps() -
                market.liquidationFeeBps())) / 10000;
        uint maxReplenish = ((maxDebt - market.debts(user)) * 10000) /
            dbr.replenishmentPriceBps();
        uint dolaBalBefore = DOLA.balanceOf(replenisher);
        uint expectedReward = (maxReplenish *
            dbr.replenishmentPriceBps() *
            market.replenishmentIncentiveBps()) / 100000000;
        market.forceReplenish(user, maxReplenish);

        assertLt(market.debts(user), (maxDebt * 10001) / 10000);
        assertGt(market.debts(user), (maxDebt * 9999) / 10000);
        assertLt(dbr.deficitOf(user), deficit, "Deficit didn't shrink");
        assertEq(
            (DOLA.balanceOf(replenisher) - dolaBalBefore),
            expectedReward,
            "Replenisher didn't receive enough DOLA"
        );
    }

    function testGetWithdrawalLimit_Returns_CollateralBalance() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);

        vm.startPrank(user, user);
        deposit(testAmount);

        uint collateralBalance = market.escrows(user).balance();
        assertEq(collateralBalance, testAmount);
        assertEq(
            market.getWithdrawalLimit(user),
            collateralBalance,
            "Should return collateralBalance when user's escrow balance > 0 & debts = 0"
        );
    }

    function testGetWithdrawalLimit_Returns_CollateralBalanceAdjustedForDebts()
        public
    {
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);

        vm.startPrank(user, user);
        deposit(testAmount);
        market.borrow(borrowAmount);
        uint collateralBalance = market.escrows(user).balance();
        uint collateralFactor = market.collateralFactorBps();
        uint minimumCollateral = (((borrowAmount * 1 ether) /
            oracle.viewPrice(address(collateral), collateralFactor)) * 10000) /
            collateralFactor;
        assertEq(
            market.getWithdrawalLimit(user),
            collateralBalance - minimumCollateral,
            "Should return collateral balance adjusted for debt"
        );
    }

    function testGetWithdrawalLimit_Returns_0_WhenEscrowBalanceIs0() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);

        vm.startPrank(user, user);
        deposit(testAmount);

        uint collateralBalance = market.escrows(user).balance();
        assertEq(collateralBalance, testAmount);

        market.withdraw(testAmount);
        assertEq(
            market.getWithdrawalLimit(user),
            0,
            "Should return 0 when user's escrow balance is 0"
        );
    }

    function testGetWithdrawalLimit_Returns_0_WhenMarketCollateralFactoris0()
        public
    {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);

        vm.startPrank(user, user);
        deposit(testAmount);
        market.borrow(1);
        vm.stopPrank();

        vm.startPrank(gov);
        market.setCollateralFactorBps(0);
        assertEq(
            market.getWithdrawalLimit(user),
            0,
            "Should return 0 when user has non-zero debt & collateralFactorBps = 0"
        );
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
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);

        deposit(testAmount);

        assertEq(
            stakingWrapper.balanceOf(address(market.predictEscrow(user))),
            testAmount,
            "failed to deposit collateral"
        );
        assertEq(collateral.balanceOf(user), 0, "failed to deposit collateral");

        market.withdraw(testAmount);

        assertEq(
            stakingWrapper.balanceOf(address(market.predictEscrow(user))),
            0,
            "failed to withdraw collateral"
        );
        assertEq(
            collateral.balanceOf(user),
            testAmount,
            "failed to withdraw collateral"
        );
    }

    function testWithdraw_Fail_When_WithdrawingCollateralBelowCF() public {
        gibCollateral(user, testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);

        deposit(testAmount);

        assertEq(
            stakingWrapper.balanceOf(address(market.predictEscrow(user))),
            testAmount,
            "failed to deposit collateral"
        );
        assertEq(collateral.balanceOf(user), 0, "failed to deposit collateral");

        market.borrow(borrowAmount);

        vm.expectRevert("Insufficient withdrawal limit");
        market.withdraw(testAmount);

        assertEq(
            stakingWrapper.balanceOf(address(market.predictEscrow(user))),
            testAmount,
            "successfully withdrew collateral"
        );
        assertEq(
            collateral.balanceOf(user),
            0,
            "successfully withdrew collateral"
        );
    }

    function testWithdrawOnBehalf() public {
        address userPk = vm.addr(1);
        gibCollateral(userPk, testAmount);
        gibDBR(userPk, testAmount);

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
                        testAmount,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(testAmount);
        vm.stopPrank();

        assertEq(
            stakingWrapper.balanceOf(address(market.predictEscrow(userPk))),
            testAmount,
            "failed to deposit collateral"
        );
        assertEq(
            collateral.balanceOf(userPk),
            0,
            "failed to deposit collateral"
        );

        vm.startPrank(user2);
        market.withdrawOnBehalf(userPk, testAmount, block.timestamp, v, r, s);

        assertEq(
            stakingWrapper.balanceOf(address(market.predictEscrow(userPk))),
            0,
            "failed to withdraw collateral"
        );
        assertEq(
            collateral.balanceOf(user2),
            testAmount,
            "failed to withdraw collateral"
        );
    }

    function testWithdrawOnBehalf_When_InvalidateNonceCalledPrior() public {
        address userPk = vm.addr(1);
        gibCollateral(userPk, testAmount);
        gibDBR(userPk, testAmount);

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
                        testAmount,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(testAmount);
        market.invalidateNonce();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert("INVALID_SIGNER");
        market.withdrawOnBehalf(userPk, testAmount, block.timestamp, v, r, s);
    }

    function testWithdrawOnBehalf_When_DeadlineHasPassed() public {
        address userPk = vm.addr(1);
        gibCollateral(userPk, testAmount);
        gibDBR(userPk, testAmount);

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
                        testAmount,
                        0,
                        timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(testAmount);
        market.invalidateNonce();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.warp(block.timestamp + 1);
        vm.expectRevert("DEADLINE_EXPIRED");
        market.withdrawOnBehalf(userPk, testAmount, timestamp, v, r, s);
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
