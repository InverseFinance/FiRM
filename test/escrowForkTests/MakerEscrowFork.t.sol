pragma solidity ^0.8.20;

import "test/escrowForkTests/BaseEscrowTest.t.sol";
import {MakerEscrow, IVoteDelegate, IVoteDelegateFactory} from "src/escrows/MakerEscrow.sol";

contract MakerEscrowFork is BaseEscrowTest {
    
    IERC20 maker = IERC20(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2);
    MakerEscrow escrowImplementation;
    IVoteDelegateFactory public constant voteDelegateFactory = IVoteDelegateFactory(0xD897F108670903D1d6070fcf818f9db3615AF272);
    address delegate = 0xE5a7023f78c3c0b7B098e8f4aCE7031B3D9aFBaB;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        escrowImplementation = new MakerEscrow();
        initialize(address(escrowImplementation), address(maker));
    }

    function test_delegateTo() public {
        deal(address(maker), address(escrowImplementation), 1 ether);
        assertEq(escrowImplementation.delegate(), address(0));
        vm.prank(beneficiary);
        escrowImplementation.delegateTo(delegate);
        assertEq(escrowImplementation.delegate(), delegate);
        assertEq(escrowImplementation.iou().balanceOf(address(escrowImplementation)), 1 ether);
        assertEq(escrowImplementation.balance(), 1 ether);
    }

    function test_pay_payAfterDelegateTo() public {
        deal(address(maker), address(escrowImplementation), 1 ether);
        assertEq(escrowImplementation.delegate(), address(0));
        vm.prank(beneficiary);
        escrowImplementation.delegateTo(delegate);
        vm.roll(block.number + 1); //Will revert if chief is interacted with twice by same address in same block
        assertEq(escrowImplementation.delegate(), delegate);
        vm.prank(market);
        escrowImplementation.pay(beneficiary, 1 ether);
        assertEq(maker.balanceOf(beneficiary), 1 ether);
        assertEq(escrowImplementation.balance(), 0);
    }

    function test_delegateTo_afterPayHalf() public {
        deal(address(maker), address(escrowImplementation), 1 ether);
        vm.prank(market);
        escrowImplementation.pay(beneficiary, 1 ether / 2);
        assertEq(maker.balanceOf(beneficiary), 1 ether / 2);
        assertEq(escrowImplementation.balance(), 1 ether / 2);

        assertEq(escrowImplementation.delegate(), address(0));
        vm.prank(beneficiary);
        escrowImplementation.delegateTo(delegate);
        assertEq(escrowImplementation.delegate(), delegate);
        assertEq(escrowImplementation.iou().balanceOf(address(escrowImplementation)), 1 ether / 2);
        assertEq(escrowImplementation.balance(), 1 ether / 2);
    }

    function test_onDepositDelegateCorrectly() public {
        MakerEscrow freshEscrow = new MakerEscrow();
        deal(address(maker), address(freshEscrow), 1 ether);
        vm.prank(market);
        freshEscrow.initialize(maker, delegate);
        assertTrue(voteDelegateFactory.isDelegate(freshEscrow.beneficiary()), "`delegate` is not a Delegate");
        uint balBefore = freshEscrow.balance();
        freshEscrow.onDeposit();
        assertEq(freshEscrow.market(), market);
        assertEq(freshEscrow.beneficiary(), delegate);
        assertEq(address(freshEscrow.token()), address(maker));
        assertEq(freshEscrow.delegate(), freshEscrow.beneficiary(), "Delegate not set");
        assertEq(balBefore, freshEscrow.balance(), "Balance after");
    }

    function test_undelegate() public {
        deal(address(maker), address(escrowImplementation), 1 ether);
        assertEq(escrowImplementation.delegate(), address(0));
        vm.prank(beneficiary);
        escrowImplementation.delegateTo(delegate);
        assertEq(escrowImplementation.delegate(), delegate);

        vm.roll(block.number + 1); //Will revert if chief is interacted with twice by same address in same block
        vm.prank(beneficiary);
        escrowImplementation.undelegate();
        assertEq(escrowImplementation.delegate(), address(0));
        assertEq(maker.balanceOf(address(escrowImplementation)), 1 ether);
    }

    function test_delegate_failsWhenCalledByNonBeneficiary() public {
        vm.expectRevert();
        vm.prank(holder);
        escrowImplementation.delegateTo(holder);
    }

}
