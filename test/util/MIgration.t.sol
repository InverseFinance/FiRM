pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Migration} from "src/util/Migration.sol";
import {ALEV2, IERC20, IPendleHelper} from "src/util/ALEV2.sol";
import {DbrHelper} from "src/util/DbrHelper.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";
contract MigrationTest is Test, ConfigAddr {

    Migration migration;
    ALEV2 ale;
    DbrHelper dbrHelper;
    
    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
      
        ale = new ALEV2(newTriDBRAddr, address(this));
        dbrHelper = new DbrHelper(newTriDBRAddr, address(this));
        migration = new Migration(address(ale),address(dbrHelper));
        ale.setPendingGov(address(migration));
        dbrHelper.setPendingGov(address(migration));
    }

    function test_migrateMarkets() public {
        vm.prank(gov);
        migration.migrate();
        address[] memory markets = migration.getMarkets();
        ALEV2 oldALE = migration.OLD_ALE();
        for (uint i = 0; i < markets.length; ++i) {
            (IERC20 buySellToken, , IPendleHelper helper, bool useProxy) = oldALE.markets(markets[i]);
            (IERC20 buySellToken2, , IPendleHelper helper2, bool useProxy2) = ale.markets(markets[i]);
            // ALE migration checks
            assertEq(address(buySellToken), address(buySellToken2));
            assertEq(address(helper), address(helper2));
            assertEq(useProxy,useProxy2);
            // DbrHelper migration checks
            IERC20 dola = IERC20(dolaAddr);
            assertEq(dola.allowance(address(dbrHelper),address(markets[i])), type(uint).max);
        }

        assertEq(ale.pendingGov(), gov);
        assertEq(dbrHelper.pendingGov(), gov);
    }
}