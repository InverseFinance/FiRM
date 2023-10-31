pragma solidity ^0.8.20;

import "test/escrowForkTests/BaseEscrowTest.t.sol";
import {GOhmTokenEscrow} from "src/escrows/GOhmTokenEscrow.sol";

contract GohmEscrowFork is BaseEscrowTest {
    
    IERC20 gOhm = IERC20(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);
    GOhmTokenEscrow escrowImplementation;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        escrowImplementation = new GOhmTokenEscrow();
        initialize(address(escrowImplementation), address(gOhm));
    }

    function test_initialize() public {
        GOhmTokenEscrow freshEscrow = new GOhmTokenEscrow();
        vm.prank(market);
        freshEscrow.initialize(gOhm, holder);
        assertEq(freshEscrow.market(), market);
        assertEq(freshEscrow.beneficiary(), holder);
        assertEq(address(freshEscrow.token()), address(gOhm));
        assertEq(freshEscrow.delegatingTo(), freshEscrow.beneficiary());
    }

    function test_delegate() public {
        assertEq(escrowImplementation.delegatingTo(), beneficiary);
        vm.prank(beneficiary);
        escrowImplementation.delegate(holder);
        assertEq(escrowImplementation.delegatingTo(), holder);
    }

    function test_delegate_failsWhenCalledByNonBeneficiary() public {
        vm.expectRevert();
        vm.prank(holder);
        escrowImplementation.delegate(holder);
    }

}
