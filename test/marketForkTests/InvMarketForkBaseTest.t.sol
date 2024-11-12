// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";
import {DbrDistributor} from "src/DbrDistributor.sol";
import {INVEscrow, IXINV, IDbrDistributor} from "src/escrows/INVEscrow.sol";

contract InvMarketBaseForkTest is MarketBaseForkTest {
    DbrDistributor distributor;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20026122);
        distributor = DbrDistributor(
            0xdcd2D918511Ba39F2872EB731BB88681AE184244
        );
        address marketAddr = 0xb516247596Ca36bf32876199FBdCaD6B3322330B;
        address feedAddr = 0xC54Ca0a605D5DA34baC77f43efb55519fC53E78e;
        _advancedInit(marketAddr, feedAddr, true);
        vm.startPrank(gov);
        dbr.addMinter(address(distributor));
        vm.stopPrank();
    }
}
