pragma solidity ^0.8.20;

import "test/escrowForkTests/BaseEscrowTest.t.sol";
import {GovTokenEscrow, IDelegateable} from "src/escrows/GovTokenEscrow.sol";

contract CompEscrowForkTest is BaseEscrowTest {
    
    IERC20 comp = IERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    GovTokenEscrow escrowImplementation;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        escrowImplementation = new GovTokenEscrow();
        initialize(address(escrowImplementation), address(comp));
    }

    function test_initialize() public {
        GovTokenEscrow freshEscrow = new GovTokenEscrow();
        vm.prank(market);
        freshEscrow.initialize(address(comp), holder);
        address holderDelegate = freshEscrow.token().delegates(address(holder));
        assertEq(freshEscrow.market(), market);
        assertEq(freshEscrow.beneficiary(), holder, "beneficiary");
        assertEq(address(freshEscrow.token()), address(comp));
        assertEq(freshEscrow.delegatingTo(), holderDelegate, "delegatingTo: holder delegate");
    }

    function test_delegate() public {
        address holderDelegate = escrowImplementation.token().delegates(address(holder));
        assertEq(escrowImplementation.delegatingTo(), holderDelegate, "delegatingTo: holder delegate");
        vm.prank(beneficiary);
        escrowImplementation.delegate(holder);
        assertEq(escrowImplementation.delegatingTo(), holder, "delegatingTo: holder");
    }

    function test_delegate_failsWhenCalledByNonBeneficiary() public {
        vm.expectRevert();
        vm.prank(holder);
        escrowImplementation.delegate(holder);
    }

}
