// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IEscrow.sol";

abstract contract BaseEscrowTest is Test{

    address market = address(0xA);
    address beneficiary = address(0xB);
    address claimant = address(0xC);
    address holder = address(0xD);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    IERC20 COLLATERAL = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IEscrow escrow;
    bool approxBalance;
    bool restakerEscrow;

    function initialize(address _escrow, address _collateral) public {
        //This will fail if there's no mainnet variable in foundry.toml
        COLLATERAL = IERC20(_collateral);
        escrow = IEscrow(_escrow);
        vm.prank(market, market);
        escrow.initialize(COLLATERAL, beneficiary);
        deal(address(COLLATERAL), holder, 1000 ether);
    }
    
    function initialize(
        address _escrow,
        address _collateral,
        bool _approxBalance,
        bool _restakerEscrow) public {
        approxBalance = _approxBalance;
        restakerEscrow = _restakerEscrow;
        initialize(_escrow, _collateral);
    }

    function testOnDeposit_successful_whenContractHoldsCOLLATERAL() public {
        vm.prank(holder, holder);
        COLLATERAL.transfer(address(escrow), 1 ether);
        assertEq(COLLATERAL.balanceOf(address(escrow)), 1 ether, "COLLATERAL transfer failed");

        escrow.onDeposit();
        //Asserts that balance function returns correct amount        
        if(approxBalance){ 
            uint max = 1 ether;
            uint min = 1 ether * (1 ether - 100) / 1 ether;
            withinSpan(escrow.balance(), max, min);
        } else {
            assertEq(escrow.balance(), 1 ether);
        }
        //Assert that escrow either holds balance or has restaked balance
        if(restakerEscrow){
            assertEq(COLLATERAL.balanceOf(address(escrow)), 0, "All COLLATERAL not deposited");
        } else {
            assertEq(COLLATERAL.balanceOf(address(escrow)), 1 ether, "All COLLATERAL not deposited");
        }
    }

    function testPay_successful() public {
        vm.prank(holder, holder);
        COLLATERAL.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.startPrank(market, market);
        if(approxBalance){
            escrow.pay(beneficiary, escrow.balance());
        } else {
            escrow.pay(beneficiary, 1 ether);
        }
        
        assertEq(escrow.balance(), 0);
        assertEq(COLLATERAL.balanceOf(beneficiary), 1 ether);
    }

    function testPay_successful_whenEscrowHasStakedCOLLATERAL_AndTimeWarp() public {
        vm.prank(holder, holder);
        COLLATERAL.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.startPrank(market, market);
        vm.warp(block.timestamp + 365 days);
        escrow.pay(beneficiary, 1 ether);
        vm.stopPrank();

        assertGe(escrow.balance(), 0);
        assertEq(COLLATERAL.balanceOf(beneficiary), 1 ether);
    }

    function testPay_failWithONLYMARKET_whenCalledByNonMarket() public {
        vm.prank(holder, holder);
        COLLATERAL.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.startPrank(holder, holder);
        vm.expectRevert("ONLY MARKET");
        escrow.pay(beneficiary, 1 ether);
        vm.stopPrank();
    }

    function testPay_fail_whenPayMoreThanBalance() public {
        vm.prank(holder, holder);
        COLLATERAL.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.startPrank(market, market);
        vm.expectRevert();
        escrow.pay(beneficiary, 10 ether);
        vm.stopPrank();   
    }

    function withinSpan(uint input, uint max, uint min) public {
        assertLe(input, max, "Input above max");
        assertGe(input, min, "Input below min");
    }
}

