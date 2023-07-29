pragma solidity ^0.8.13;
import "forge-std/Script.sol";
import {Market} from "src/Market.sol";
import {BorrowController} from "src/BorrowController.sol";
import "src/DBR.sol";

interface IBorrowController {
    function setDailyLimit(address market, uint newLimit) external;
    function dailyLimits(address market) external returns(uint);
}


contract borrowControllerSetup is Script {
    IBorrowController oldBorrowController;
    IBorrowController newBorrowController;
    DolaBorrowingRights DBR = DolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
    address[] markets = 
        [
            0x93685185666c8D34ad4c574B3DBF41231bbfB31b, //cvxFxs
            0x3474ad0e3a9775c9F68B415A7a9880B0CAB9397a, //cvxCrv
            0x63fAd99705a255fE2D500e498dbb3A9aE5AA1Ee8, //crv
            0x7Cd3ab8354289BEF52c84c2BF0A54E3608e66b37, //gohm
            0xb516247596Ca36bf32876199FBdCaD6B3322330B, //inv
            0x743A502cf0e213F6FEE56cD9C6B03dE7Fa951dCf, //steth
            0x63Df5e23Db45a2066508318f172bA45B9CD37035, //weth
            0x27b6c301Fd441f3345d61B7a4245E1F823c3F9c4  //stycrv
        ];
    
    constructor(address _oldBorrowController, address _newBorrowController){
        oldBorrowController = IBorrowController(_oldBorrowController);
        newBorrowController = IBorrowController(_newBorrowController);
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        if(address(newBorrowController) == address(0)){
            vm.broadcast(deployerPrivateKey);
            newBorrowController = new BorrowController(deployerAddress, DBR);
        }

        for(uint i; i < markets.length; ++i){
            address market = markets[i];
            require(DBR.markets(market), "Not a market");
            uint oldLimit = oldBorrowController.dailyLimits(market);
            vm.broadcast(deployerPrivateKey);
            newBorrowController.setDailyLimit(market, oldLimit);
        }
    }
}
