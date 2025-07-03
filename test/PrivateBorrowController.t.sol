// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "test/mocks/BorrowContract.sol";
import "test/FiRMBaseTest.sol";
import {PrivateBorrowController} from "src/PrivateBorrowController.sol";

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

contract PrivateBorrowControllerTest is FiRMBaseTest {
    BorrowContract borrowContract;
    PrivateBorrowController privateBorrowController;
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
        privateBorrowController = new PrivateBorrowController(gov, address(dbr));
        market.setBorrowController(IBorrowController(address(privateBorrowController)));

        gibWeth(address(borrowContract), 1 ether);
        vm.prank(gov);
        privateBorrowController.setStalenessThreshold(address(market), 10);
        require(
            address(market.borrowController()) != address(0),
            "Borrow controller not set"
        );
        //Let daily limit recover fully
        vm.warp(block.timestamp + 1 days);
        ethFeed.changeUpdatedAt(block.timestamp);
    }

    function test_BorrowAllowed_True_Where_UserIsAllowedForMarket() public {
        vm.prank(gov);
        privateBorrowController.allowBorrower(address(market), user, true);
        vm.startPrank(address(market), user);
        assertEq(
            privateBorrowController.borrowAllowed(user, address(0), 0),
            true,
            "EOA not allowed to borrow"
        );
    }

    function test_BorrowAllowed_False_Where_UserIsUnallowedForMarket() public {
        vm.prank(address(market), user);
        assertEq(
            privateBorrowController.borrowAllowed(
                address(borrowContract),
                address(0),
                0
            ),
            false,
            "Unallowed contract allowed to borrow"
        );
    }

    function test_BorrowAllowed_False_Where_EdgeCaseBugTriggeredAndNotAMinter()
        public
    {
        vm.prank(gov);
        privateBorrowController.allowBorrower(address(market), user, true);
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
            privateBorrowController.borrowAllowed(user, user, 1),
            "User was allowed to borrow"
        );
    }

    function test_BorrowAllowed_True_Where_EdgeCaseBugDebtNonZero()
        public
    {
        vm.prank(gov);
        privateBorrowController.allowBorrower(address(market), user, true);

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
        dbr.addMinter(address(privateBorrowController));
        vm.prank(address(market), user);
        assertTrue(
            privateBorrowController.borrowAllowed(user, user, 1)
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
        privateBorrowController.allowBorrower(address(market), user, true);

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
        dbr.addMinter(address(privateBorrowController));
        vm.prank(address(market), user);
        assertTrue(
            privateBorrowController.borrowAllowed(user, user, 1)
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
        privateBorrowController.allowBorrower(address(market), user, true);
        
        timeElapsed =  timeElapsed % 365 days;
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
        dbr.addMinter(address(privateBorrowController));
        vm.prank(address(market), user);
        assertTrue(
            privateBorrowController.borrowAllowed(user, user, 1)
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
        privateBorrowController.allowBorrower(address(market), user, true);


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
            privateBorrowController.borrowAllowed(user, user, 1),
            "User was allowed to borrow"
        );
    }


    function test_BorrowAllowed_True_Where_EdgeCaseBugTriggeredAndAMinter()
        public
    {
        vm.prank(gov);
        privateBorrowController.allowBorrower(address(market), user, true);


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
        dbr.addMinter(address(privateBorrowController));
        vm.prank(address(market), user);
        assertEq(
            privateBorrowController.borrowAllowed(user, user, 1),
            true,
            "User was not allowed to borrow"
        );
    }

    function test_BorrowAllowed_Revert_When_EdgeCaseBugTriggeredAndCalledByNonApprovedMarket()
        public
    {
        vm.prank(gov);
        privateBorrowController.allowBorrower(address(market), user, true);

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
        dbr.addMinter(address(privateBorrowController));
        vm.prank(address(0xdeadbeef), address(0xdeadbeef));
        vm.expectRevert("Message sender is not a market");
        privateBorrowController.borrowAllowed(user, user, 0);
    }

    function test_BorrowAllowed_False_Where_PriceIsStale() public {
        vm.prank(gov);
        privateBorrowController.allowBorrower(address(market), user, true);

        vm.warp(block.timestamp + 1000);

        vm.startPrank(address(market), user);
        assertEq(privateBorrowController.isPriceStale(address(market)), true);
        assertEq(
            privateBorrowController.borrowAllowed(user, address(0), 0),
            false,
            "Allowed contract not allowed to borrow"
        );
        vm.stopPrank();
    }

    function test_BorrowAllowed_False_Where_DebtIsBelowMininimum() public {
        vm.startPrank(gov);
        privateBorrowController.setMinDebt(address(market), 1 ether);
        privateBorrowController.allowBorrower(address(market), user, true);
        vm.stopPrank();

        vm.startPrank(address(market), user);
        assertEq(
            privateBorrowController.isBelowMinDebt(address(market), user, 0.5 ether),
            true
        );
        assertEq(
            privateBorrowController.borrowAllowed(user, address(0), 0.5 ether),
            false,
            "Allowed contract not allowed to borrow"
        );
        vm.stopPrank();
    }

    function test_addAddressToAllowlist() public {
        bool allowed = privateBorrowController.allowedBorrowers(
            address(market),
            user
        );
        assertEq(allowed, false, "User was allowed before call to allow");

        vm.startPrank(gov);
        privateBorrowController.allowBorrower(address(market), user, true);
        vm.stopPrank();

        assertEq(
            privateBorrowController.allowedBorrowers(address(market), user),
            true,
            "Contract was not added to allowlist successfully"
        );
    }

    function test_removesAddressFromAllowlist() public {
        test_addAddressToAllowlist();

        vm.startPrank(gov);
        privateBorrowController.allowBorrower(address(market), user, false);

        assertEq(
            privateBorrowController.allowedBorrowers(address(market), user),
            false,
            "Contract was not removed from allowlist successfully"
        );
    }
    //Access Control
    function test_accessControl_setOperator() public {
        vm.prank(gov);
        privateBorrowController.setOperator(address(0));

        vm.expectRevert(onlyOperatorLowercase);
        privateBorrowController.setOperator(address(0));
    }

    function test_accessControl_setStalenessThresshold() public {
        vm.prank(gov);
        privateBorrowController.setStalenessThreshold(address(market), 1);
        assertEq(privateBorrowController.stalenessThreshold(address(market)), 1);

        vm.expectRevert(onlyOperatorLowercase);
        privateBorrowController.setStalenessThreshold(address(market), 2);
    }

    function test_accessControl_setMinDebtThresshold() public {
        vm.prank(gov);
        privateBorrowController.setMinDebt(address(market), 500 ether);
        assertEq(privateBorrowController.minDebts(address(market)), 500 ether);

        vm.expectRevert(onlyOperatorLowercase);
        privateBorrowController.setMinDebt(address(market), 200 ether);
    }

    function test_accessControl_allowBorrower() public {
        vm.prank(gov);
        privateBorrowController.allowBorrower(address(0), address(0), true);

        vm.expectRevert(onlyOperatorLowercase);
        privateBorrowController.allowBorrower(address(0), address(0), true);
    }
}
