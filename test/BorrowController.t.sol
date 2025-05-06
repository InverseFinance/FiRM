// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "test/mocks/BorrowContract.sol";
import "test/FiRMBaseTest.sol";
import {BorrowController} from "src/BorrowController.sol";

contract BorrowContractTxOrigin {
    uint256 constant AMOUNT = 1 ether;
    uint256 constant PRICE = 1000;
    uint256 constant COLLATERAL_FACTOR_BPS = 8500;
    uint256 constant BPS_BASIS = 10_000;

    constructor(Market market, WETH9 weth) payable {
        weth.approve(address(market), type(uint).max);
        weth.deposit{value: msg.value}();
        market.deposit(address(this), AMOUNT);
        market.borrow((AMOUNT * COLLATERAL_FACTOR_BPS * PRICE) / BPS_BASIS);
    }
}
contract BatchApprove {
    IDBR immutable dbr;

    constructor(address _dbr){
        dbr = IDBR(_dbr);
    }

    function approveDepositAndBorrow(address _market, uint depositAmount, uint borrowAmount) external {
        require(msg.sender == address(this), "Invalid authority");
        require(tx.origin == address(this), "Invalid origin");
        require(dbr.markets(_market), "Invalid market");
        IMarket market = IMarket(_market);
        IERC20(market.collateral()).approve(_market, depositAmount);
        market.depositAndBorrow(depositAmount, borrowAmount);
    }
}

contract BorrowControllerTest is FiRMBaseTest {
    BorrowContract borrowContract;
    bytes onlyOperatorLowercase = "Only operator";
    function setUp() public {
        initialize(
            replenishmentPriceBps,
            collateralFactorBps,
            replenishmentIncentiveBps,
            liquidationBonusBps,
            callOnDepositCallback
        );
        vm.startPrank(gov);
        borrowController.setDailyLimit(address(market), 1 ether);

        borrowContract = new BorrowContract(
            address(market),
            payable(address(WETH))
        );
        gibWeth(address(borrowContract), 1 ether);
        vm.prank(gov);
        borrowController.setStalenessThreshold(address(market), 10);
        require(
            address(market.borrowController()) != address(0),
            "Borrow controller not set"
        );
        //Let daily limit recover fully
        vm.warp(block.timestamp + 1 days);
        ethFeed.changeUpdatedAt(block.timestamp);
    }

    function test_BorrowAllowed_True_Where_UserIsEOA() public {
        vm.startPrank(address(market), user);
        assertEq(
            borrowController.borrowAllowed(user, address(0), 0),
            true,
            "EOA not allowed to borrow"
        );
    }

    function test_BorrowAllowed_False_Where_UserIsUnallowedContract() public {
        vm.prank(address(market), user);
        assertEq(
            borrowController.borrowAllowed(
                address(borrowContract),
                address(0),
                0
            ),
            false,
            "Unallowed contract allowed to borrow"
        );
    }

    function test_dailyLimit() public {
        vm.startPrank(address(market), user);
        assertEq(
            borrowController.borrowAllowed(user, address(0), 0.5 ether),
            true,
            "Not allowed to borrow below limit"
        );
        assertEq(
            borrowController.borrowAllowed(user, address(0), 1 ether),
            false,
            "Allowed to borrow above limit"
        );
        assertEq(
            borrowController.borrowAllowed(user, address(0), 0.5 ether + 1),
            false,
            "Allowed to borrow above limit"
        );
        assertEq(
            borrowController.remainingDailyBorrowLimit(
                address(market)
            ),
            0.5 ether,
            "Unexpected daily borrows"
        );
    }

    function test_dailyLimit_replenishesAsExpected() public {
        vm.startPrank(address(market), user);
        assertEq(
            borrowController.borrowAllowed(user, address(0), 0.5 ether),
            true,
            "Not allowed to borrow below limit"
        );
        assertEq(borrowController.availableBorrowLimit(address(market)), 0.5 ether);
        vm.warp(block.timestamp + 1 days / 4);
        ethFeed.changeUpdatedAt(block.timestamp);
        assertEq(borrowController.availableBorrowLimit(address(market)), 0.75 ether);
        assertEq(
            borrowController.borrowAllowed(user, address(0), 1 ether),
            false,
            "Allowed to borrow above limit"
        );
        assertEq(
            borrowController.borrowAllowed(user, address(0), 0.75 ether),
            true,
            "Not allowed to borrow limit"
        );
        assertEq(borrowController.availableBorrowLimit(address(market)), 0);

        vm.warp(block.timestamp + 2 days);
        ethFeed.changeUpdatedAt(block.timestamp);

        assertEq(borrowController.availableBorrowLimit(address(market)), 1 ether);
        assertEq(
            borrowController.borrowAllowed(user, address(0), 1 ether),
            true,
            "Not allowed to borrow limit"
        );
    }


    function test_BorrowAllowed_True_Where_UserIsAllowedContract() public {
        vm.startPrank(gov);
        borrowController.allow(address(borrowContract));
        vm.stopPrank();

        vm.prank(address(market), user);
        assertEq(
            borrowController.borrowAllowed(
                address(borrowContract),
                address(0),
                0
            ),
            true,
            "Allowed contract not allowed to borrow"
        );
    }

    function test_BorrowAllowed_False_Where_EdgeCaseBugTriggeredAndNotAMinter()
        public
    {
        uint testAmount = 1e18;
        gibWeth(user, testAmount);
        uint maxBorrow = 1e18-1;
        gibDOLA(address(market), maxBorrow);
        vm.startPrank(user, user);
        deposit(testAmount);
        market.borrow(maxBorrow);
        market.repay(user, maxBorrow);
        vm.stopPrank();

        vm.warp(block.timestamp + 1);
        vm.prank(address(market), user);
        assertFalse(
            borrowController.borrowAllowed(user, user, 1),
            "User was allowed to borrow"
        );
    }

    function test_BorrowAllowed_True_Where_EdgeCaseBugDebtNonZero()
        public
    {
        vm.prank(gov);
        borrowController.setDailyLimit(address(market), 2000 ether);
        uint testAmount = 1e18;
        gibWeth(user, testAmount);
        uint halfBorrow = getMaxBorrowAmount(testAmount) / 2;
        gibDOLA(address(market), halfBorrow * 2);
        vm.startPrank(user, user);
        deposit(testAmount);
        market.borrow(halfBorrow);
        market.repay(user, halfBorrow-1);
        vm.stopPrank();

        assertEq(market.debts(user), 1, "User debt not 1");
        assertEq(dbr.balanceOf(user), 0, "DBR balance of user is not 0 before time skip");
        vm.warp(block.timestamp + 30 days);
        ethFeed.changeUpdatedAt(block.timestamp);
        vm.prank(gov);
        dbr.addMinter(address(borrowController));
        vm.prank(address(market), user);
        assertTrue(
            borrowController.borrowAllowed(user, user, 1)
        );
        vm.startPrank(user, user);
        assertGt(market.getCreditLimit(user), 0, "User has no credit limit");
        market.borrow(market.getCreditLimit(user) / 100);
        assertLe(dbr.deficitOf(user), 30 days * 1, "Deficit of user more than expected");
        assertEq(dbr.balanceOf(user), 0, "DBR balance of user is not 0");
    }

    function test_BorrowAllowed_True_Where_EdgeCaseBugDebtNonZero365Days()
        public
    {
        vm.prank(gov);
        borrowController.setDailyLimit(address(market), 2000 ether);
        uint testAmount = 1e18;
        gibWeth(user, testAmount);
        uint halfBorrow = getMaxBorrowAmount(testAmount) / 2;
        gibDOLA(address(market), halfBorrow * 2);
        vm.startPrank(user, user);
        deposit(testAmount);
        market.borrow(halfBorrow);
        market.repay(user, halfBorrow-1);
        vm.stopPrank();

        assertEq(market.debts(user), 1, "User debt not 1");
        assertEq(dbr.balanceOf(user), 0, "DBR balance of user is not 0 before time skip");
        vm.warp(block.timestamp + 365 days);
        ethFeed.changeUpdatedAt(block.timestamp);
        vm.prank(gov);
        dbr.addMinter(address(borrowController));
        vm.prank(address(market), user);
        assertTrue(
            borrowController.borrowAllowed(user, user, 1)
        );
        vm.startPrank(user, user);
        assertGt(market.getCreditLimit(user), 0, "User has no credit limit");
        uint creditLimit = market.getCreditLimit(user);
        vm.expectRevert("DBR Deficit");
        market.borrow(creditLimit / 100);
        dbr.accrueDueTokens(user);
        assertEq(dbr.deficitOf(user), 1);
    }


    function test_BorrowAllowed_True_Where_EdgeCaseBugDebtNonZeroFuzz(uint timeElapsed)
        public
    {
        vm.prank(gov);
        borrowController.setDailyLimit(address(market), 2000 ether);
        uint timeElapsed = timeElapsed % 365 days;
        uint testAmount = 1e18;
        gibWeth(user, testAmount);
        uint halfBorrow = getMaxBorrowAmount(testAmount) / 2;
        gibDOLA(address(market), halfBorrow * 2);
        vm.startPrank(user, user);
        deposit(testAmount);
        market.borrow(halfBorrow);
        market.repay(user, halfBorrow-1);
        vm.stopPrank();

        assertEq(market.debts(user), 1, "User debt not 1");
        assertEq(dbr.balanceOf(user), 0, "DBR balance of user is not 0 before time skip");
        vm.warp(block.timestamp + timeElapsed);
        ethFeed.changeUpdatedAt(block.timestamp);
        vm.prank(gov);
        dbr.addMinter(address(borrowController));
        vm.prank(address(market), user);
        assertTrue(
            borrowController.borrowAllowed(user, user, 1)
        );
        vm.startPrank(user, user);
        assertGt(market.getCreditLimit(user), 0, "User has no credit limit");
        market.borrow(market.getCreditLimit(user) / 100);
        assertLe(dbr.deficitOf(user), timeElapsed * 1, "Deficit of user more than expected");
        assertEq(dbr.balanceOf(user), 0, "DBR balance of user is not 0");
    }

    function test_BorrowAllowed_False_Where_EdgeCaseBugTriggeredWithMinimalDebt()
        public
    {
        vm.prank(gov);
        borrowController.setDailyLimit(address(market), 2000 ether);
        uint testAmount = 1e18;
        gibWeth(user, testAmount);
        uint maxBorrow = getMaxBorrowAmount(testAmount);
        gibDOLA(address(market), maxBorrow);
        vm.startPrank(user, user);
        deposit(testAmount);
        market.borrow(maxBorrow);
        market.repay(user, maxBorrow-1);
        vm.stopPrank();

        vm.warp(block.timestamp + 1);
        vm.prank(address(market), user);
        assertFalse(
            borrowController.borrowAllowed(user, user, 1),
            "User was allowed to borrow"
        );
    }


    function test_BorrowAllowed_True_Where_EdgeCaseBugTriggeredAndAMinter()
        public
    {
        uint testAmount = 1e18;
        gibWeth(user, testAmount);
        uint maxBorrow = 1e18-1;
        gibDOLA(address(market), maxBorrow);
        vm.startPrank(user, user);
        deposit(testAmount);
        market.borrow(maxBorrow);
        market.repay(user, maxBorrow);
        vm.stopPrank();

        vm.warp(block.timestamp + 1);
        vm.prank(gov);
        dbr.addMinter(address(borrowController));
        vm.prank(address(market), user);
        assertEq(
            borrowController.borrowAllowed(user, user, 1),
            true,
            "User was not allowed to borrow"
        );
    }

    function test_BorrowAllowed_Revert_When_EdgeCaseBugTriggeredAndCalledByNonApprovedMarket()
        public
    {
        uint testAmount = 1e18;
        gibWeth(user, testAmount);
        uint maxBorrow = 1e18-1;
        gibDOLA(address(market), maxBorrow);
        vm.startPrank(user, user);
        deposit(testAmount);
        market.borrow(maxBorrow);
        market.repay(user, maxBorrow);
        vm.stopPrank();

        vm.warp(block.timestamp + 1);
        vm.prank(gov);
        dbr.addMinter(address(borrowController));
        vm.prank(address(0xdeadbeef), address(0xdeadbeef));
        vm.expectRevert("Message sender is not a market");
        borrowController.borrowAllowed(user, user, 0);
    }

    function test_BorrowAllowed_False_Where_PriceIsStale() public {
        vm.startPrank(gov);
        borrowController.allow(address(borrowContract));
        vm.stopPrank();
        vm.warp(block.timestamp + 1000);

        vm.startPrank(address(market), user);
        assertEq(borrowController.isPriceStale(address(market)), true);
        assertEq(
            borrowController.borrowAllowed(user, address(0), 0),
            false,
            "Allowed contract not allowed to borrow"
        );
        vm.stopPrank();
    }

    function test_borrowAllowed_False_whenCalledByEIP7702tx() public {
        uint ALICE_PK = 1;
        address ALICE = vm.addr(ALICE_PK);
        BatchApprove implementation = new BatchApprove(address(dbr));
        //Simulated borrow
        uint testAmount = 1e18;
        gibWeth(ALICE, testAmount);
        uint maxBorrow = getMaxBorrowAmount(testAmount);
        gibDOLA(address(market), maxBorrow);
        vm.signAndAttachDelegation(address(implementation), ALICE_PK);
        vm.startPrank(ALICE, ALICE);
        vm.expectRevert("Denied by borrow controller");
        BatchApprove(ALICE).approveDepositAndBorrow(address(market), testAmount, maxBorrow);
        vm.stopPrank();
    }

    function test_BorrowAllowed_False_Where_DebtIsBelowMininimum() public {
        vm.startPrank(gov);
        borrowController.setMinDebt(address(market), 1 ether);
        vm.stopPrank();

        vm.startPrank(address(market), user);
        assertEq(
            borrowController.isBelowMinDebt(address(market), user, 0.5 ether),
            true
        );
        assertEq(
            borrowController.borrowAllowed(user, address(0), 0.5 ether),
            false,
            "Allowed contract not allowed to borrow"
        );
        vm.stopPrank();
    }

    function test_Allow_Successfully_AddsAddressToAllowlist() public {
        bool allowed = borrowController.contractAllowlist(
            address(borrowContract)
        );
        assertEq(allowed, false, "Contract was allowed before call to allow");

        vm.startPrank(gov);
        borrowController.allow(address(borrowContract));
        vm.stopPrank();

        assertEq(
            borrowController.contractAllowlist(address(borrowContract)),
            true,
            "Contract was not added to allowlist successfully"
        );
    }

    function test_Deny_Successfully_RemovesAddressFromAllowlist() public {
        test_Allow_Successfully_AddsAddressToAllowlist();

        vm.startPrank(gov);
        borrowController.deny(address(borrowContract));

        assertEq(
            borrowController.contractAllowlist(address(borrowContract)),
            false,
            "Contract was not removed from allowlist successfully"
        );
    }

    function test_BorrowAllowed_False_Where_UserIsUnallowedContractCallingFromConstructor()
        public
    {
        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), convertWethToDola(1 ether));
        vm.stopPrank();
        vm.deal(address(0xA), 1 ether);
        vm.startPrank(address(0xA), address(0xA));
        bytes memory denied = "Denied by borrow controller";
        vm.expectRevert(denied);
        new BorrowContractTxOrigin{value: 1 ether}(market, WETH);
    }

    function test_onRepay_ReducesDailyBorrowsByAmount() public {
        vm.prank(borrowController.operator());
        borrowController.setDailyLimit(address(market), 10 ether);
        vm.startPrank(address(market), user);
        borrowController.borrowAllowed(user, address(0), 1 ether);
        assertEq(
            borrowController.remainingDailyBorrowLimit(
                address(market)
            ),
            9 ether
        );
        borrowController.onRepay(0.5 ether);
        assertEq(
            borrowController.remainingDailyBorrowLimit(
                address(market)
            ),
            9.5 ether
        );
    }


    //Access Control

    function test_setDailyLimit() public {
        vm.expectRevert(onlyOperatorLowercase);
        borrowController.setDailyLimit(address(0), 1);

        vm.prank(borrowController.operator());
        borrowController.setDailyLimit(address(0), 1);
        assertEq(borrowController.dailyLimits(address(0)), 1);
    }

    function test_accessControl_setOperator() public {
        vm.prank(gov);
        borrowController.setOperator(address(0));

        vm.expectRevert(onlyOperatorLowercase);
        borrowController.setOperator(address(0));
    }

    function test_accessControl_setStalenessThresshold() public {
        vm.prank(gov);
        borrowController.setStalenessThreshold(address(market), 1);
        assertEq(borrowController.stalenessThreshold(address(market)), 1);

        vm.expectRevert(onlyOperatorLowercase);
        borrowController.setStalenessThreshold(address(market), 2);
    }

    function test_accessControl_setMinDebtThresshold() public {
        vm.prank(gov);
        borrowController.setMinDebt(address(market), 500 ether);
        assertEq(borrowController.minDebts(address(market)), 500 ether);

        vm.expectRevert(onlyOperatorLowercase);
        borrowController.setMinDebt(address(market), 200 ether);
    }

    function test_accessControl_allow() public {
        vm.startPrank(gov);
        borrowController.allow(address(0));

        vm.stopPrank();

        vm.expectRevert(onlyOperatorLowercase);
        borrowController.allow(address(0));
    }

    function test_accessControl_deny() public {
        vm.startPrank(gov);
        borrowController.deny(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyOperatorLowercase);
        borrowController.deny(address(0));
    }
}
