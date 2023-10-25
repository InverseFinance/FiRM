// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {BorrowController} from "src/BorrowController.sol";
import "./mocks/BorrowContract.sol";
import "./FrontierV2Test.sol";
import "src/Market.sol";
import "./mocks/WETH9.sol";

contract BorrowContractTxOrigin {
    
    uint256 constant AMOUNT = 1 ether;
    uint256 constant PRICE = 1000;
    uint256 constant COLLATERAL_FACTOR_BPS = 8500;
    uint256 constant BPS_BASIS = 10_000;

    constructor(Market market, WETH9 weth) payable {
        weth.approve(address(market), type(uint).max);
        weth.deposit{value: msg.value}();
        market.deposit(address(this), AMOUNT);
        market.borrow(AMOUNT * COLLATERAL_FACTOR_BPS * PRICE / BPS_BASIS);
    }
}  

contract BorrowControllerTest is FrontierV2Test {
    BorrowContract borrowContract;
    bytes onlyOperatorLowercase = "Only operator";

    function setUp() public {
        initialize(replenishmentPriceBps, collateralFactorBps, replenishmentIncentiveBps, liquidationBonusBps, callOnDepositCallback);

        borrowContract = new BorrowContract(address(market), payable(address(WETH)));
        gibWeth(address(borrowContract), 1 ether);
        vm.prank(gov);
        borrowController.setStalenessThreshold(address(market), 10);
        require(address(market.borrowController()) != address(0), "Borrow controller not set");
    }

    function test_BorrowAllowed_True_Where_UserIsEOA() public {
        vm.startPrank(address(market), user);
        assertEq(borrowController.borrowAllowed(user, address(0), 0), true, "EOA not allowed to borrow");
    }

    function test_BorrowAllowed_False_Where_UserIsUnallowedContract() public {
        vm.prank(address(market), user);
        assertEq(borrowController.borrowAllowed(address(borrowContract),address(0), 0), false, "Unallowed contract allowed to borrow");
    }

    function test_BorrowAllowed_True_Where_UserIsAllowedContract() public {
        vm.startPrank(gov);
        borrowController.allow(address(borrowContract));
        vm.stopPrank();
        
        vm.prank(address(market), user);
        assertEq(borrowController.borrowAllowed(address(borrowContract), address(0), 0), true, "Allowed contract not allowed to borrow");
    }

    function test_BorrowAllowed_False_Where_EdgeCaseBugTriggeredAndNotAMinter() public {
        uint testAmount = 1e18;
        gibWeth(user, testAmount);
        uint maxBorrow = getMaxBorrowAmount(testAmount);
        gibDOLA(address(market), maxBorrow);
        vm.startPrank(user, user);
        deposit(testAmount);
        market.borrow(maxBorrow);
        market.repay(user, maxBorrow);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 1);
        vm.prank(address(market), user);
        assertFalse(borrowController.borrowAllowed(user, user, 1), "User was allowed to borrow");
    }

    function test_BorrowAllowed_True_Where_EdgeCaseBugTriggeredAndAMinter() public {
        uint testAmount = 1e18;
        gibWeth(user, testAmount);
        uint maxBorrow = getMaxBorrowAmount(testAmount);
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
        assertEq(borrowController.borrowAllowed(user, user, 1), true, "User was not allowed to borrow");
    }

    function test_BorrowAllowed_Revert_When_EdgeCaseBugTriggeredAndCalledByNonApprovedMarket() public {
        uint testAmount = 1e18;
        gibWeth(user, testAmount);
        uint maxBorrow = getMaxBorrowAmount(testAmount);
        gibDOLA(address(market), maxBorrow);
        vm.startPrank(user, user);
        deposit(testAmount);
        market.borrow(maxBorrow);
        market.repay(user, maxBorrow);
        vm.stopPrank();
        
        vm.warp(block.timestamp + 1);
        vm.prank(gov);
        dbr.addMinter(address(borrowController));
        vm.prank(user, user);
        vm.expectRevert("Message sender is not a market");
        borrowController.borrowAllowed(user, user, 1);
    }

    function test_BorrowAllowed_False_Where_PriceIsStale() public {
        vm.startPrank(gov);
        borrowController.allow(address(borrowContract));
        vm.stopPrank();
        vm.warp(block.timestamp + 1000);
        
        vm.startPrank(address(market), user);
        assertEq(borrowController.isPriceStale(address(market)), true);
        assertEq(borrowController.borrowAllowed(user, address(0), 0), false, "Allowed contract not allowed to borrow");
        vm.stopPrank();
    }

    function test_BorrowAllowed_False_Where_DebtIsBelowMininimum() public {
        vm.startPrank(gov);
        borrowController.setMinDebt(address(market), 1 ether);
        vm.stopPrank();
        
        vm.startPrank(address(market), user);
        assertEq(borrowController.isBelowMinDebt(address(market), user, 0.5 ether), true);
        assertEq(borrowController.borrowAllowed(user, address(0), 0.5 ether), false, "Allowed contract not allowed to borrow");
        vm.stopPrank();
    }

    function test_Allow_Successfully_AddsAddressToAllowlist() public {
        bool allowed = borrowController.contractAllowlist(address(borrowContract));
        assertEq(allowed, false, "Contract was allowed before call to allow");

        vm.startPrank(gov);
        borrowController.allow(address(borrowContract));
        vm.stopPrank();

        assertEq(borrowController.contractAllowlist(address(borrowContract)), true, "Contract was not added to allowlist successfully");
    }

    function test_Deny_Successfully_RemovesAddressFromAllowlist() public {
        test_Allow_Successfully_AddsAddressToAllowlist();

        vm.startPrank(gov);
        borrowController.deny(address(borrowContract));

        assertEq(borrowController.contractAllowlist(address(borrowContract)), false, "Contract was not removed from allowlist successfully");
    }

    function test_BorrowAllowed_False_Where_UserIsUnallowedContractCallingFromConstructor() public {
        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), convertWethToDola(1 ether));
        vm.stopPrank();
        vm.deal(address(0xA), 1 ether);
        vm.startPrank(address(0xA), address(0xA));
        bytes memory denied = "Denied by borrow controller";
        vm.expectRevert(denied);
        new BorrowContractTxOrigin{value:1 ether}(market, WETH);
    }

    //Access Control

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
