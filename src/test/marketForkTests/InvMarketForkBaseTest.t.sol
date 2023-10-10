// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";
import {BorrowController} from "../../BorrowController.sol";
import "../../DBR.sol";
import {Fed} from "../../Fed.sol";
import "../../Market.sol";
import "../../Oracle.sol";
import {DbrDistributor} from "../../DbrDistributor.sol";
import {INVEscrow, IXINV, IDbrDistributor} from "../../escrows/INVEscrow.sol";

import "../mocks/ERC20.sol";
import "../mocks/BorrowContract.sol";

contract InvMarketBaseForkTest is MarketBaseForkTest {
    DbrDistributor distributor;
    
    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        distributor = DbrDistributor(0xdcd2D918511Ba39F2872EB731BB88681AE184244);
        Market market = Market(0xb516247596Ca36bf32876199FBdCaD6B3322330B);
        address invFeed = 0xC54Ca0a605D5DA34baC77f43efb55519fC53E78e;
        _advancedInit(address(market), address(invFeed), true);
        vm.startPrank(gov);
        dbr.addMinter(address(distributor));
        vm.stopPrank();

        borrowContract = new BorrowContract(address(market), payable(address(collateral)));
    }
}
