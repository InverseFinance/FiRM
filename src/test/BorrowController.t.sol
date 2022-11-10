// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../BorrowController.sol";
import "./mocks/BorrowContract.sol";
import "./FrontierV2Test.sol";
import "../Market.sol";
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
    }

    function test_BorrowAllowed_True_Where_UserIsEOA() public {
        vm.startPrank(user, user);
        assertEq(borrowController.borrowAllowed(user, address(0), 0), true, "EOA not allowed to borrow");
    }

    function test_BorrowAllowed_False_Where_UserIsUnallowedContract() public {
        assertEq(borrowController.borrowAllowed(address(borrowContract),address(0), 0), false, "Unallowed contract allowed to borrow");
    }

    function test_BorrowAllowed_True_Where_UserIsAllowedContract() public {
        vm.startPrank(gov);
        borrowController.allow(address(borrowContract));
        vm.stopPrank();

        assertEq(borrowController.borrowAllowed(address(borrowContract), address(0), 0), true, "Allowed contract not allowed to borrow");
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

        vm.deal(user, 1 ether);
        vm.startPrank(user, user);
        bytes memory denied = "Denied by borrow controller";
        vm.expectRevert(denied);
        new BorrowContractTxOrigin{value:1 ether}(market, WETH);
    }

    //Access Control

    function test_accessControl_setOperator() public {
        vm.startPrank(gov);
        borrowController.setOperator(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyOperatorLowercase);
        borrowController.setOperator(address(0));
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
