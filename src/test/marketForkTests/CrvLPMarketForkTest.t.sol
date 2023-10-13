// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketForkTest.sol";
import {TriFraxPoolPriceFeed, IAggregator} from "../../feeds/TriFraxPoolPriceFeed.sol";
import "../../BorrowController.sol";
import "../../DBR.sol";
import "../../Fed.sol";
import "../../Market.sol";
import "../../Oracle.sol";
import {SimpleERC20Escrow} from "../../escrows/SimpleERC20Escrow.sol";

import "../mocks/ERC20.sol";
import "../mocks/BorrowContract.sol";

interface IBorrowControllerLatest {
    function borrowAllowed(
        address msgSender,
        address borrower,
        uint amount
    ) external returns (bool);

    function onRepay(uint amount) external;

    function setStalenessThreshold(
        address market,
        uint stalenessThreshold
    ) external;

    function operator() external view returns (address);

    function isBelowMinDebt(
        address market,
        address borrower,
        uint amount
    ) external view returns (bool);

    function isPriceStale(address market) external view returns (bool);

    function dailyLimits(address market) external view returns (uint);
}

contract CrvLPMarketForkTest is MarketForkTest {
    bytes onlyGovUnpause = "Only governance can unpause";
    bytes onlyPauseGuardianOrGov =
        "Only pause guardian or governance can pause";
    address lender = 0x2b34548b865ad66A2B046cb82e59eE43F75B90fd;
    IERC20 crvLP = IERC20(0xE57180685E3348589E9521aa53Af0BCD497E884d);

    SimpleERC20Escrow escrow;

    BorrowContract borrowContract;

    TriFraxPoolPriceFeed fraxPoolFeed;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 18272690); // FRAX < USDC at this block
        escrow = new SimpleERC20Escrow();
        fraxPoolFeed = new TriFraxPoolPriceFeed();
        Market crvLPMarket = new Market(
            gov,
            lender,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbr)),
            crvLP,
            IOracle(address(oracle)),
            5000,
            5000,
            1000,
            true
        );
        init(address(crvLPMarket), address(fraxPoolFeed));
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
            crvLP.balanceOf(address(market.predictEscrow(user))),
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
            crvLP.balanceOf(address(market.predictEscrow(user))),
            0,
            "User balance not 0"
        );
        assertEq(
            crvLP.balanceOf(address(market.predictEscrow(user2))),
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
            crvLP.balanceOf(address(market.predictEscrow(user))),
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
            crvLP.balanceOf(address(market.predictEscrow(userPk))),
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
        gibCollateral(user, testAmount);
        uint borrowAmount = getMaxBorrowAmount(testAmount);
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
            crvLP.balanceOf(address(market.predictEscrow(user))),
            testAmount,
            "failed to deposit collateral"
        );
        assertEq(collateral.balanceOf(user), 0, "failed to deposit collateral");

        market.withdraw(testAmount);

        assertEq(
            crvLP.balanceOf(address(market.predictEscrow(user))),
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
            crvLP.balanceOf(address(market.predictEscrow(user))),
            testAmount,
            "failed to deposit collateral"
        );
        assertEq(collateral.balanceOf(user), 0, "failed to deposit collateral");

        market.borrow(borrowAmount);

        vm.expectRevert("Insufficient withdrawal limit");
        market.withdraw(testAmount);

        assertEq(
            crvLP.balanceOf(address(market.predictEscrow(user))),
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
            crvLP.balanceOf(address(market.predictEscrow(userPk))),
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
            crvLP.balanceOf(address(market.predictEscrow(userPk))),
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

    function testBorrow_Fails_if_price_stale_usdcToUsd_chainlink_and_FRAX_gt_USDC() public {
        _setNewBorrowController();

        testAmount = 10000 ether;
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);
        deposit(testAmount);

        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.fraxToUsd())),
            110000000
        ); // Frax > than USDC

        _mockChainlinkUpdatedAt(
            IChainlinkFeed(address(fraxPoolFeed.usdcToUsd())),
            -86461
        ); // price stale for usdcToUsd

        assertTrue(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isPriceStale(address(market))
        );
        assertFalse(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isBelowMinDebt(address(market), user, 1300 ether)
        ); // Minimum debt is 1250 DOLA

        vm.expectRevert(bytes("Denied by borrow controller"));
        market.borrow(1300 ether);
    }

    function testBorrow_Fails_if_price_stale_ethToUsd_when_usdcToUsd_MIN_out_of_bounds_and_FRAX_gt_USDC()
        public
    {
        _setNewBorrowController();

        testAmount = 10000 ether;
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);
        deposit(testAmount);
        
        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.fraxToUsd())),
            110000000
        ); // Frax > than USDC

        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.usdcToUsd())),
            IAggregator(fraxPoolFeed.usdcToUsd().aggregator()).minAnswer() - 1
        ); // min out of bounds
        _mockChainlinkUpdatedAt(
            IChainlinkFeed(address(fraxPoolFeed.ethToUsd())),
            -3601
        ); // staleness for ethToUsd

        assertTrue(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isPriceStale(address(market))
        );
        assertFalse(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isBelowMinDebt(address(market), user, 1300 ether)
        ); // Minimum debt is 1250 DOLA

        vm.expectRevert(bytes("Denied by borrow controller"));
        market.borrow(1300 ether);
    }

    function testBorrow_Fails_if_price_stale_ethToUsd_when_usdcToUsd_MAX_out_of_bounds_and_FRAX_gt_USDC()
        public
    {
        _setNewBorrowController();

        testAmount = 10000 ether;
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);
        deposit(testAmount);

        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.fraxToUsd())),
            110000000
        ); // Frax > than USDC

        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.usdcToUsd())),
            IAggregator(fraxPoolFeed.usdcToUsd().aggregator()).maxAnswer() + 1
        ); // Max out of bounds
        _mockChainlinkUpdatedAt(
            IChainlinkFeed(address(fraxPoolFeed.ethToUsd())),
            -3601
        ); // staleness for ethToUsd

        assertTrue(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isPriceStale(address(market))
        );
        assertFalse(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isBelowMinDebt(address(market), user, 1300 ether)
        ); // Minimum debt is 1250 DOLA

        vm.expectRevert(bytes("Denied by borrow controller"));
        market.borrow(1300 ether);
    }

    function testBorrow_Fails_if_price_stale_crvUSDToUsd_and_ethToUsd_when_fraxToUsd_and_usdcToUsd_MAX_out_of_bounds_and_USDC_gt_FRAX()
        public
    {
        _setNewBorrowController();

        testAmount = 10000 ether;
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);
        deposit(testAmount);

        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.fraxToUsd())),
            IAggregator(fraxPoolFeed.fraxToUsd().aggregator()).maxAnswer() + 1
        ); // Frax MAX out of bounds


        _mockChainlinkUpdatedAt(
            IChainlinkFeed(address(fraxPoolFeed.crvUSDToUsd())),
            -24 hours
        ); // staleness for crvUSDToUsd

        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.usdcToUsd())),
            IAggregator(fraxPoolFeed.usdcToUsd().aggregator()).maxAnswer() + 1
        ); // Max out of bounds

        _mockChainlinkUpdatedAt(
            IChainlinkFeed(address(fraxPoolFeed.ethToUsd())),
            -3601
        ); // staleness for ethToUsd

        assertTrue(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isPriceStale(address(market))
        );
        assertFalse(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isBelowMinDebt(address(market), user, 1300 ether)
        ); // Minimum debt is 1250 DOLA

        vm.expectRevert(bytes("Denied by borrow controller"));
        market.borrow(1300 ether);
    }

    function testBorrow_Fails_if_ethToUsd_MIN_out_of_bounds_when_usdcToUsd_MAX_out_of_bounds()
        public
    {
        _setNewBorrowController();

        testAmount = 10000 ether;
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);
        deposit(testAmount);

        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.usdcToUsd())),
            IAggregator(fraxPoolFeed.usdcToUsd().aggregator()).maxAnswer() + 1
        ); // Max out of bounds
        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.ethToUsd())),
            IAggregator(fraxPoolFeed.ethToUsd().aggregator()).minAnswer() - 1
        ); // Min out of bounds for ethToUsd

        assertTrue(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isPriceStale(address(market))
        );
        assertFalse(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isBelowMinDebt(address(market), user, 1300 ether)
        ); // Minimum debt is 1250 DOLA

        vm.expectRevert(bytes("Denied by borrow controller"));
        market.borrow(1300 ether);
    }

    function testBorrow_Fails_if_ethToUsd_and_crvUSDtoUSD_MAX_out_of_bounds_when_usdcToUsd_and_fraxToUsd_MAX_out_of_bounds_and_FRAX_gt_USDC()
        public
    {
        _setNewBorrowController();

        testAmount = 10000 ether;
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);
        deposit(testAmount);

        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.fraxToUsd())),
            IAggregator(fraxPoolFeed.fraxToUsd().aggregator()).maxAnswer() + 1
        ); // Frax out of bounds

        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.crvUSDToUsd())),
            IAggregator(fraxPoolFeed.crvUSDToUsd().aggregator()).maxAnswer() + 1
        );

        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.usdcToUsd())),
            IAggregator(fraxPoolFeed.usdcToUsd().aggregator()).maxAnswer() + 1
        );

        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.ethToUsd())),
            IAggregator(fraxPoolFeed.ethToUsd().aggregator()).maxAnswer() + 1
        ); // Max out of bounds

        console.log(IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isPriceStale(address(market)));
        assertFalse(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isBelowMinDebt(address(market), user, 1300 ether)
        ); // Minimum debt is 1250 DOLA

        vm.expectRevert(bytes("Denied by borrow controller"));
        market.borrow(1300 ether);
    }

    function testBorrow_if_price_NOT_stale_ethToUsd_when_usdcToUsd_MAX_out_of_bounds_and_FRAX_gt_USDC()
        public
    {
        _setNewBorrowController();

        testAmount = 10000 ether;
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);
        deposit(testAmount);

        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.usdcToUsd())),
            IAggregator(fraxPoolFeed.usdcToUsd().aggregator()).maxAnswer() + 1
        ); // Max out of bounds

          
        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.fraxToUsd())),
            110000000
        ); // Frax > than USDC


        assertFalse(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isPriceStale(address(market))
        );

        assertFalse(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isBelowMinDebt(address(market), user, 1300 ether)
        ); // Minimum debt is 1250 DOLA

        market.borrow(1300 ether);
        assertEq(DOLA.balanceOf(user), 1300 ether);
    }

    function testBorrow_if_price_NOT_stale_ethToUsd_when_usdcToUsd_MIN_out_of_bounds()
        public
    {
        _setNewBorrowController();

        testAmount = 10000 ether;
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);
        deposit(testAmount);

        _mockChainlinkPrice(
            IChainlinkFeed(address(fraxPoolFeed.usdcToUsd())),
            IAggregator(fraxPoolFeed.usdcToUsd().aggregator()).minAnswer() - 1
        ); // min out of bounds

        assertFalse(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isPriceStale(address(market))
        );
        assertFalse(
            IBorrowControllerLatest(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
                .isBelowMinDebt(address(market), user, 1300 ether)
        ); // Minimum debt is 1250 DOLA

        market.borrow(1300 ether);
        assertEq(DOLA.balanceOf(user), 1300 ether);
    }

    function _mockChainlinkPrice(
        IChainlinkFeed clFeed,
        int mockPrice
    ) internal {
        (
            uint80 roundId,
            ,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = clFeed.latestRoundData();
        vm.mockCall(
            address(clFeed),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                roundId,
                mockPrice,
                startedAt,
                updatedAt,
                answeredInRound
            )
        );
    }

    function _mockChainlinkUpdatedAt(
        IChainlinkFeed clFeed,
        int updatedAtDelta
    ) internal {
        (
            uint80 roundId,
            int price,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = clFeed.latestRoundData();
        vm.mockCall(
            address(clFeed),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                roundId,
                price,
                startedAt,
                uint(int(updatedAt) + updatedAtDelta),
                answeredInRound
            )
        );
    }

    function _setNewBorrowController() internal {
        vm.startPrank(gov);
        market.setBorrowController(
            IBorrowController(0x44B7895989Bc7886423F06DeAa844D413384b0d6)
        );
        BorrowController(address(market.borrowController())).setDailyLimit(
            address(market),
            3000000 ether
        ); // at the current block there's there's only 75 Dola to borrow
        IBorrowControllerLatest(address(market.borrowController())).setStalenessThreshold(
            address(market),
            24 hours
        );
        vm.stopPrank();
    }
}
