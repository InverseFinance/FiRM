// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/interfaces/IERC20.sol";
import {DAIEscrow, IDSR, IPot} from "src/escrows/DAIEscrow.sol";

contract DAIEscrowForkTest is Test{

    address market = address(0xA);
    address beneficiary = address(0xB);
    address claimant = address(0xC);
    address holder = address(0xD);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    IERC20 DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IDSR DSR = IDSR(0x373238337Bfe1146fb49989fc222523f83081dDb);
    IPot POT = IPot(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);
    DAIEscrow escrow;


    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        escrow = new DAIEscrow();
        vm.prank(market, market);
        escrow.initialize(DAI, beneficiary);
        deal(address(DAI), holder, 1000 ether);
    }

    function test_initialize() public {
        DAIEscrow freshEscrow = new DAIEscrow();
        vm.prank(address(market));
        freshEscrow.initialize(DAI, holder);
        assertEq(address(freshEscrow.market()), address(market), "Market not equal market");
        assertEq(address(freshEscrow.token()), address(DAI), "DAI not Token");
    }

    function testOnDeposit_successful_whenContractHoldsDAI() public {
        uint balanceBefore = escrow.balance();
        
        vm.prank(holder, holder);
        DAI.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        
        uint max = balanceBefore + 1 ether;
        uint min = (balanceBefore + 1 ether) * (1 ether - 100) / 1 ether;
        withinSpan(escrow.balance(), max, min);
        assertEq(DAI.balanceOf(address(escrow)), 0, "All DAI not deposited");
        assertEq(DSR.daiBalance(address(escrow)), escrow.balance(), "DSR Balance not equal to escrow balance");
    }

    function testPay_successful_whenContractHasStakedDAI() public {
        vm.prank(holder, holder);
        DAI.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        uint beneficiaryBalanceBefore = DAI.balanceOf(beneficiary);

        vm.startPrank(market, market);
        escrow.pay(beneficiary, 0.5 ether);
        assertEq(DAI.balanceOf(beneficiary), beneficiaryBalanceBefore + 0.5 ether);

        uint escrowBal = escrow.balance();
        escrow.pay(beneficiary, escrowBal);

        assertEq(escrow.balance(), 0);
        assertEq(DSR.daiBalance(address(escrow)), 0);
        assertEq(DAI.balanceOf(beneficiary), beneficiaryBalanceBefore + 0.5 ether + escrowBal);
        assertEq(DSR.daiBalance(address(escrow)), escrow.balance());
    }

    function testPay_successful_whenEscrowHasStakedDAI_AndTimeWarp() public {
        vm.prank(holder, holder);
        DAI.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        uint beneficiaryBalanceBefore = DAI.balanceOf(beneficiary);

        vm.startPrank(market, market);
        vm.warp(block.timestamp + 365 days);
        POT.drip();
        escrow.pay(beneficiary, 1 ether);
        vm.stopPrank();


        assertGt(escrow.balance(), 0);
        assertGt(DSR.daiBalance(address(escrow)), 0);
        assertGe(DAI.balanceOf(beneficiary), beneficiaryBalanceBefore + 1 ether);
        assertEq(DSR.daiBalance(address(escrow)), escrow.balance());
    }

    function testPay_successful_whenContractHasStakedDAIFuzz(uint walletAmount) public {
        vm.assume(walletAmount > 1000);
        vm.startPrank(holder, holder);
        uint payAmount = walletAmount % DAI.balanceOf(holder);
        if(payAmount < 3) payAmount = 3;
        DAI.transfer(address(escrow), payAmount);
        escrow.onDeposit();
        uint beneficiaryBalanceBefore = DAI.balanceOf(beneficiary);
        vm.stopPrank();

        vm.prank(market, market);
        escrow.pay(beneficiary, payAmount-3);


        withinSpan(escrow.balance(), 3, 0);
        withinSpan(DSR.daiBalance(address(escrow)), 3, 0);
        withinSpan(DAI.balanceOf(beneficiary), beneficiaryBalanceBefore + payAmount, beneficiaryBalanceBefore + payAmount-3);
        assertEq(DSR.daiBalance(address(escrow)), escrow.balance(), "DSR balance not equal to escrow");
    }

    function testPay_failWithONLYMARKET_whenCalledByNonMarket() public {
        vm.prank(holder, holder);
        DAI.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.startPrank(holder, holder);
        vm.expectRevert("ONLY MARKET");
        escrow.pay(beneficiary, 1 ether);
        vm.stopPrank();
    }

    function withinSpan(uint input, uint max, uint min) public {
        assertLe(input, max, "Input above max");
        assertGe(input, min, "Input below min");
    }
}

