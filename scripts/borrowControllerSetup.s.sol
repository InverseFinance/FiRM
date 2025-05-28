pragma solidity ^0.8.13;
import "forge-std/Script.sol";
import {Market, IERC20} from "src/Market.sol";
import {IMarket} from "src/interfaces/IMarket.sol";
import {BorrowController} from "src/BorrowController.sol";
import {BorrowControllerMigrationHelper} from "src/util/BorrowControllerMigrationHelper.sol";
import "src/DBR.sol";

interface IBorrowController {
    function setDailyLimit(address market, uint newLimit) external;
    function dailyLimits(address market) external returns(uint);
    function allow(address market) external;
    function setOperator(address gov) external;
}

interface IBC is IBorrowController {
    function minDebts(address market) external returns(uint);
}

interface IErc20 is IERC20 {
    function name() external view returns(string memory);
}

contract borrowControllerSetup is Script {
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address deployerAddress = 0x11EC78492D53c9276dD7a184B1dbfB34E50B710D;
    BorrowController newBorrowController;
    BorrowControllerMigrationHelper migrationHelper;
    DolaBorrowingRights DBR = DolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork(vm.envString("RPC_MAINNET"));
        vm.broadcast(deployerPrivateKey);
        newBorrowController = new BorrowController(gov, address(DBR));
        console.log("BorrowController deployed to", address(newBorrowController));
        migrationHelper = new BorrowControllerMigrationHelper(gov);
        console.log("BorrowControllerMigrationHelper deployed to", address(migrationHelper));
    }
}
