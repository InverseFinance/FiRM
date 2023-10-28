// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";
import {SFraxEscrow} from "src/escrows/SFraxEscrow.sol";
import {Market} from "src/Market.sol";
import "src/Oracle.sol";

contract SFraxMarketForkTest is MarketBaseForkTest {
    SFraxEscrow escrow;
    IERC20 frax = IERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    address fraxToUsd = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        
        escrow = new SFraxEscrow();
        
        Market market = new Market(
            gov,
            lender,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbr)),
            frax,
            IOracle(address(oracle)),
            5000,
            5000,
            1000,
            true
        );

        _advancedInit(address(market), fraxToUsd, true);
    }
}
