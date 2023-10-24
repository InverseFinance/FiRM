// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {SFraxEscrow, IERC20, IERC4626} from "src/escrows/SFraxEscrow.sol";

contract SFraxEscrowForkTest is Test{

    address market = address(0xA);
    address recipient = address(0xB);
    address holder = address(0xD);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    IERC20 public frax = IERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    IERC4626 public sFrax = IERC4626(0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32);
    SFraxEscrow escrow;


    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        escrow = new SFraxEscrow();
        vm.prank(market, market);
        escrow.initialize(frax, address(0));
        deal(address(frax), holder, 1000 ether);
    }

    function testOnDeposit_successful_whenContractHoldsDAI() public {
        uint balanceBefore = escrow.balance();
        
        vm.prank(holder, holder);
        frax.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        
        uint max = balanceBefore + 1 ether;
        uint min = (balanceBefore + 1 ether) * (1 ether - 10) / 1 ether;
        withinSpan(escrow.balance(), max, min);
        assertEq(frax.balanceOf(address(escrow)), 0, "All FRAX not deposited");
        assertGt(sFrax.balanceOf(address(escrow)), 0, "sFRAX not minted");
        assertEq(sFrax.convertToAssets(sFrax.balanceOf(address(escrow))), escrow.balance(), "FRAX Balance on sFRAX not equal to escrow balance");
    }

    function testPay_successful_whenContractHasStakedFRAX() public {
        vm.prank(holder, holder);
        frax.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        uint recipientBalanceBefore = frax.balanceOf(recipient);

        vm.prank(market, market);
        escrow.pay(recipient, 1 ether);

        assertEq(escrow.balance(), 0);
        assertEq(sFrax.balanceOf(address(escrow)), 0);
        assertEq(frax.balanceOf(recipient), recipientBalanceBefore + 1 ether-1);
    }   

    function testPay_successful_whenEscrowHasStakedFRAX_AndTimeWarp() public {
        vm.prank(holder, holder);
        frax.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        uint recipientBalanceBefore = frax.balanceOf(recipient);

        vm.startPrank(market, market);
        vm.warp(block.timestamp + 365 days);
        escrow.pay(recipient, 1 ether);
        vm.stopPrank();


        assertGt(escrow.balance(), 0); 
        assertGt(sFrax.balanceOf(address(escrow)), 0);
        assertGe(frax.balanceOf(recipient), recipientBalanceBefore + 1 ether - 1);
        assertEq(sFrax.convertToAssets(sFrax.balanceOf(address(escrow))), escrow.balance());
    }

    function testPay_successful_whenEscrowHasStakedFRAX_AndTimeWarp_PAY_ALL() public {
        vm.prank(holder, holder);
        frax.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        uint recipientBalanceBefore = frax.balanceOf(recipient);

        vm.startPrank(market, market);
        vm.warp(block.timestamp + 365 days);
        escrow.pay(recipient, escrow.balance());
        vm.stopPrank();

        assertEq(escrow.balance(), 0); 
        assertEq(sFrax.balanceOf(address(escrow)), 0);
        assertGe(frax.balanceOf(recipient), recipientBalanceBefore + 1 ether);
        assertEq(sFrax.convertToAssets(sFrax.balanceOf(address(escrow))), escrow.balance());
    }

    function testPay_successful_whenContractHasStakedFRAXFuzz(uint walletAmount) public {
        vm.assume(walletAmount > 1000);
        vm.startPrank(holder, holder);
        uint payAmount = walletAmount % frax.balanceOf(holder);
        if(payAmount < 3) payAmount = 3;
        frax.transfer(address(escrow), payAmount);
        escrow.onDeposit();
        uint recipientBalanceBefore = frax.balanceOf(recipient);
        vm.stopPrank();

        vm.prank(market, market);
        escrow.pay(recipient, payAmount-2);

        withinSpan(escrow.balance(), 2, 0);
        withinSpan(sFrax.balanceOf(address(escrow)), 2, 0);
        withinSpan(frax.balanceOf(recipient), recipientBalanceBefore + payAmount, recipientBalanceBefore + payAmount-3);
        assertEq(sFrax.convertToAssets(sFrax.balanceOf(address(escrow))), escrow.balance());
    }

    function testPay_failWithONLYMARKET_whenCalledByNonMarket() public {
        vm.prank(holder, holder);
        frax.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.startPrank(holder, holder);
        vm.expectRevert("ONLY MARKET");
        escrow.pay(recipient, 1 ether);
        vm.stopPrank();
    }

    function withinSpan(uint input, uint max, uint min) public {
        assertLe(input, max, "Input above max");
        assertGe(input, min, "Input below min");
    }
}

