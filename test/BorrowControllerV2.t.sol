// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "test/mocks/BorrowContract.sol";
import "test/FiRMBaseTest.sol";
import {BorrowControllerV2} from "src/BorrowControllerV2.sol";

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

contract BorrowControllerV2Test is FiRMBaseTest {
    BorrowContract borrowContract;
    bytes onlyOperatorLowercase = "Only operator";
    BorrowControllerV2 borrowControllerV2;
    function setUp() public {
        initialize(
            replenishmentPriceBps,
            collateralFactorBps,
            replenishmentIncentiveBps,
            liquidationBonusBps,
            callOnDepositCallback
        );
        borrowControllerV2 = new BorrowControllerV2(gov, address(dbr));
        vm.startPrank(gov);
        market.setBorrowController(IBorrowController(address(borrowControllerV2)));
        borrowControllerV2.setDailyBorrowLimit(address(market), 1 ether);

        borrowContract = new BorrowContract(
            address(market),
            payable(address(WETH))
        );
        gibWeth(address(borrowContract), 1 ether);
        vm.prank(gov);
        borrowControllerV2.setStalenessThreshold(address(market), 10);
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
            borrowControllerV2.borrowAllowed(user, address(0), 0),
            true,
            "EOA not allowed to borrow"
        );
    }

    function test_BorrowAllowed_False_Where_UserIsUnallowedContract() public {
        vm.prank(address(market), user);
        assertEq(
            borrowControllerV2.borrowAllowed(
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
            borrowControllerV2.borrowAllowed(user, address(0), 0.5 ether),
            true,
            "Not allowed to borrow below limit"
        );
        assertEq(
            borrowControllerV2.borrowAllowed(user, address(0), 1 ether),
            false,
            "Allowed to borrow above limit"
        );
        assertEq(
            borrowControllerV2.borrowAllowed(user, address(0), 0.5 ether + 1),
            false,
            "Allowed to borrow above limit"
        );
        assertEq(
            borrowControllerV2.remainingDailyBorrowLimit(
                address(market)
            ),
            0.5 ether,
            "Unexpected daily borrows"
        );
    }

    function test_dailyLimit_replenishesAsExpected() public {
        vm.startPrank(address(market), user);
        assertEq(
            borrowControllerV2.borrowAllowed(user, address(0), 0.5 ether),
            true,
            "Not allowed to borrow below limit"
        );
        assertEq(borrowControllerV2.availableBorrowLimit(address(market)), 0.5 ether);
        vm.warp(block.timestamp + 1 days / 4);
        ethFeed.changeUpdatedAt(block.timestamp);
        assertEq(borrowControllerV2.availableBorrowLimit(address(market)), 0.75 ether);
        assertEq(
            borrowControllerV2.borrowAllowed(user, address(0), 1 ether),
            false,
            "Allowed to borrow above limit"
        );
        assertEq(
            borrowControllerV2.borrowAllowed(user, address(0), 0.75 ether),
            true,
            "Not allowed to borrow limit"
        );
        assertEq(borrowControllerV2.availableBorrowLimit(address(market)), 0);

        vm.warp(block.timestamp + 2 days);
        ethFeed.changeUpdatedAt(block.timestamp);

        assertEq(borrowControllerV2.availableBorrowLimit(address(market)), 1 ether);
        assertEq(
            borrowControllerV2.borrowAllowed(user, address(0), 1 ether),
            true,
            "Not allowed to borrow limit"
        );
    }


    function test_BorrowAllowed_True_Where_UserIsAllowedContract() public {
        vm.startPrank(gov);
        borrowControllerV2.allow(address(borrowContract));
        vm.stopPrank();

        vm.prank(address(market), user);
        assertEq(
            borrowControllerV2.borrowAllowed(
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
            borrowControllerV2.borrowAllowed(user, user, 1),
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
        dbr.addMinter(address(borrowControllerV2));
        vm.prank(address(market), user);
        assertEq(
            borrowControllerV2.borrowAllowed(user, user, 1),
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
        dbr.addMinter(address(borrowControllerV2));
        vm.prank(address(0xdeadbeef), address(0xdeadbeef));
        vm.expectRevert("Message sender is not a market");
        borrowControllerV2.borrowAllowed(user, user, 0);
    }

    function test_BorrowAllowed_False_Where_PriceIsStale() public {
        vm.startPrank(gov);
        borrowControllerV2.allow(address(borrowContract));
        vm.stopPrank();
        vm.warp(block.timestamp + 1000);

        vm.startPrank(address(market), user);
        assertEq(borrowControllerV2.isPriceStale(address(market)), true);
        assertEq(
            borrowControllerV2.borrowAllowed(user, address(0), 0),
            false,
            "Allowed contract not allowed to borrow"
        );
        vm.stopPrank();
    }

    function test_BorrowAllowed_False_Where_DebtIsBelowMininimum() public {
        vm.startPrank(gov);
        borrowControllerV2.setMinDebt(address(market), 1 ether);
        vm.stopPrank();

        vm.startPrank(address(market), user);
        assertEq(
            borrowControllerV2.isBelowMinDebt(address(market), user, 0.5 ether),
            true
        );
        assertEq(
            borrowControllerV2.borrowAllowed(user, address(0), 0.5 ether),
            false,
            "Allowed contract not allowed to borrow"
        );
        vm.stopPrank();
    }

    function test_Allow_Successfully_AddsAddressToAllowlist() public {
        bool allowed = borrowControllerV2.contractAllowlist(
            address(borrowContract)
        );
        assertEq(allowed, false, "Contract was allowed before call to allow");

        vm.startPrank(gov);
        borrowControllerV2.allow(address(borrowContract));
        vm.stopPrank();

        assertEq(
            borrowControllerV2.contractAllowlist(address(borrowContract)),
            true,
            "Contract was not added to allowlist successfully"
        );
    }

    function test_Deny_Successfully_RemovesAddressFromAllowlist() public {
        test_Allow_Successfully_AddsAddressToAllowlist();

        vm.startPrank(gov);
        borrowControllerV2.deny(address(borrowContract));

        assertEq(
            borrowControllerV2.contractAllowlist(address(borrowContract)),
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
        vm.prank(borrowControllerV2.operator());
        borrowControllerV2.setDailyBorrowLimit(address(market), 10 ether);
        vm.startPrank(address(market), user);
        borrowControllerV2.borrowAllowed(user, address(0), 1 ether);
        assertEq(
            borrowControllerV2.remainingDailyBorrowLimit(
                address(market)
            ),
            9 ether
        );
        borrowControllerV2.onRepay(0.5 ether);
        assertEq(
            borrowControllerV2.remainingDailyBorrowLimit(
                address(market)
            ),
            9.5 ether
        );
    }

    function test_setDailyBorrowLimit() public {
        vm.expectRevert(onlyOperatorLowercase);
        borrowControllerV2.setDailyBorrowLimit(address(0), 1);

        vm.prank(borrowControllerV2.operator());
        borrowControllerV2.setDailyBorrowLimit(address(0), 1);
        assertEq(borrowControllerV2.dailyBorrowLimit(address(0)), 1);
    }

    //Access Control

    function test_accessControl_setOperator() public {
        vm.prank(gov);
        borrowControllerV2.setOperator(address(0));

        vm.expectRevert(onlyOperatorLowercase);
        borrowControllerV2.setOperator(address(0));
    }

    function test_accessControl_setStalenessThresshold() public {
        vm.prank(gov);
        borrowControllerV2.setStalenessThreshold(address(market), 1);
        assertEq(borrowControllerV2.stalenessThreshold(address(market)), 1);

        vm.expectRevert(onlyOperatorLowercase);
        borrowControllerV2.setStalenessThreshold(address(market), 2);
    }

    function test_accessControl_setMinDebtThresshold() public {
        vm.prank(gov);
        borrowControllerV2.setMinDebt(address(market), 500 ether);
        assertEq(borrowControllerV2.minDebts(address(market)), 500 ether);

        vm.expectRevert(onlyOperatorLowercase);
        borrowControllerV2.setMinDebt(address(market), 200 ether);
    }

    function test_accessControl_allow() public {
        vm.startPrank(gov);
        borrowControllerV2.allow(address(0));

        vm.stopPrank();

        vm.expectRevert(onlyOperatorLowercase);
        borrowControllerV2.allow(address(0));
    }

    function test_accessControl_deny() public {
        vm.startPrank(gov);
        borrowControllerV2.deny(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyOperatorLowercase);
        borrowControllerV2.deny(address(0));
    }
}
