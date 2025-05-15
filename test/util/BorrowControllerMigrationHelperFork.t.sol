pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {BorrowController} from "src/BorrowController.sol";
import {BorrowControllerMigrationHelper, IBorrowController} from "src/util/BorrowControllerMigrationHelper.sol";

contract BorrowControllerMigrationHelperForkTest is Test{
    
    IBorrowController oldController = IBorrowController(0xEEBea1ed06EeB120CbF72Fad195683746b5A5245);
    IBorrowController newController;
    BorrowControllerMigrationHelper migrationHelper;
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address dbr = 0xAD038Eb671c44b853887A7E32528FaB35dC5D710;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 22487356);
        migrationHelper = new BorrowControllerMigrationHelper(gov);
        newController = IBorrowController(address(new BorrowController(address(migrationHelper), dbr)));
    }

    function testAllowlistContracts_Fail() external {
        address[] memory fakeAllowlist = new address[](2);
        fakeAllowlist[0] = address(1);
        fakeAllowlist[1] = address(2);
        vm.expectRevert();
        migrationHelper.allowlistContracts(oldController, newController, fakeAllowlist);
    }


    function testAllowlistContracts() external {
        address[] memory allowlist = new address[](2);
        allowlist[0] = 0x495886947EAce9788360F46be55c758f92Ecd074;
        allowlist[1] = 0x0aBb47c564296D34B0F5B068361985f507fe123c;
        vm.expectRevert("Only gov");
        migrationHelper.allowlistContracts(oldController, newController, allowlist);
        vm.prank(gov);
        migrationHelper.allowlistContracts(oldController, newController, allowlist);
    }

    function testMigrateMarkets() external {
        address[] memory markets = new address[](3);
        markets[0] = 0x4E264618dC015219CD83dbc53B31251D73c2db1a;
        markets[1] = 0x63Df5e23Db45a2066508318f172bA45B9CD37035;
        markets[2] = 0x48BA574Edf0bc4E2E40B529863aaA6a67c264E7C;
        vm.expectRevert("Only gov");
        migrationHelper.migrateMarkets(oldController, newController, markets);
        vm.prank(gov);
        migrationHelper.migrateMarkets(oldController, newController, markets);
        for(uint i; i < markets.length; i++){
            address market = markets[i];
            assertEq(newController.dailyLimits(market), oldController.dailyLimits(market));
            assertEq(newController.stalenessThreshold(market), oldController.stalenessThreshold(market));
            assertEq(newController.minDebts(market), oldController.minDebts(market));
        }
    }

    function testTransferOwnership() external {
        vm.expectRevert("Only gov");
        migrationHelper.transferOwnership(newController);
        vm.prank(gov);
        migrationHelper.transferOwnership(newController);

        assertEq(newController.operator(), gov);
    }
}

