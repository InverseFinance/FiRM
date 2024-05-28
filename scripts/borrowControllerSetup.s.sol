pragma solidity ^0.8.13;
import "forge-std/Script.sol";
import {Market} from "src/Market.sol";
import {BorrowController} from "src/BorrowController.sol";
import "src/DBR.sol";

interface IBorrowController {
    function setDailyLimit(address market, uint newLimit) external;
    function dailyLimits(address market) external returns(uint);
    function allow(address market) external;
    function setOperator(address gov) external;
}


contract borrowControllerSetup is Script {
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address deployerAddress = 0x11EC78492D53c9276dD7a184B1dbfB34E50B710D;
    IBorrowController oldBorrowController = IBorrowController(0x20C7349f6D6A746a25e66f7c235E96DAC880bc0D);
    BorrowController newBorrowController; // = BorrowController(0x81ff13c46f363D13fC25FB801a4335c6097B7862);
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
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.broadcast(deployerPrivateKey); 
        newBorrowController = new BorrowController(deployerAddress, address(DBR));

        for(uint i; i < markets.length; ++i){
            address market = markets[i];
            require(DBR.markets(market), "Not a market");
            uint oldLimit = oldBorrowController.dailyLimits(market);
            vm.broadcast(deployerPrivateKey);
            newBorrowController.setDailyLimit(market, oldLimit);
        }

        //Add helper contract to allowList
        vm.broadcast(deployerPrivateKey);
        newBorrowController.allow(0xae8165f37FC453408Fb1cd1064973df3E6499a76);

        //Transfer ownership to gov
        vm.broadcast(deployerPrivateKey);
        newBorrowController.setOperator(gov);
    }
}
