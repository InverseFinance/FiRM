pragma solidity ^0.8.13;
import "forge-std/Script.sol";
import {Market, IERC20} from "src/Market.sol";
import {IMarket} from "src/interfaces/IMarket.sol";
import {BorrowController} from "src/BorrowController.sol";
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
    //IBC oldBorrowController = IBC(0x2DbAd53A647A86b8988E007a33FE78bd55e9Dd6f);
    BorrowController newBorrowController;
    DolaBorrowingRights DBR = DolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
    address[] markets = 
        [
            0x3474ad0e3a9775c9F68B415A7a9880B0CAB9397a, //cvxCrv
            0x63fAd99705a255fE2D500e498dbb3A9aE5AA1Ee8, //crv
            0xb516247596Ca36bf32876199FBdCaD6B3322330B, //inv
            0x63Df5e23Db45a2066508318f172bA45B9CD37035, //weth
            0x27b6c301Fd441f3345d61B7a4245E1F823c3F9c4, //stycrv
            0xB907Dcc926b5991A149d04Cb7C0a4a25dC2D8f9a, //deUSD-DOLA
            0x4f5ea72d932f554f08e97CB78DD25F8AAE43C08e, //yv-deUSD-DOLA
            0xD68d3a44d46dd50BFeBa8Cca544717B76e7C4b29, //sUSDS-sDOLA
            0xb427fC22561f3963B04202F9bb5BCEbd76c14A99, //sUSDE-sDOLA
            0x4A33baFA8a31E4ec9649f65646022cAD1957808b, //yv-sUSDS-sDOLA
            0x2fed508aAc87c0e6f0b647Fe83164A7AA6eb2FC9, //scrvUSD-DOLA
            0x5bb8f6aAcFF2971B42F9fE6945D24726A2541CF2, //yv-scrvUSD-DOLA
            0x4E264618dC015219CD83dbc53B31251D73c2db1a, //yv-sUSDE-sDOLA
            0x63D27fC9d463Ed727676367D3F818999962737E8, //scrvUSD-sDOLA
            0xb8bc1E9c0a2d445bc39d2A745F47619E954dD565, //yv-scrvUSD-sDOLA
            0x0971B1690d101169BFca4715897aD3a9b3C39b26, //DAI
            0x3FD3daBB9F9480621C8A111603D3Ba70F17550BC, //wstETH
            0x79eF6d28C41e47A588E2F2ffB4140Eb6d952AEc4, //sUSDe
            0x6A522f3BD3fDA15e74180953f203cf55aA6C631E, //crvUSD-DOLA
            0x2A256306D8ba899E33B01e495982656884Ac77FF, //cbBTC
            0xe85943e280776254ee6C9801553B93F10Ef4C99C, //yv-crvUSD-DOLA
            0xFEA3A862eE4b3F9b6015581d6d2D25AF816C54f1, //sFRAX
            0x0DFE3D04536a74Dd532dd0cEf5005bA14c5f4112, //pt-sUSDe-mar27
            0x0c0bb843FAbda441edeFB93331cFff8EC92bD168, //st-yETH
            0x4797A68c8feB383c3372c0e098533aCf8eD95B26, //FraxPyUsd-DOLA
            0x29fe42F4F71Ba5b9a7aaE794468e7ca4128a93b8, //COMP
            0xf013D998D4cf7f45547958094F1EEE75Ca43c4f5, //yv-FraxPyUsd-DOLA
            0x87df9A00f0e4908e61756d2Fcb348ADF95Ce72Ea, //FraxBP-DOLA
            0x8205bE13cC245740F9EA23Dc88a9B56206bEC0e3  //yv-FraxBP-DOLA
        ];
            //0x743A502cf0e213F6FEE56cD9C6B03dE7Fa951dCf, //steth
            //0x7Cd3ab8354289BEF52c84c2BF0A54E3608e66b37, //gohm
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork(vm.envString("RPC_MAINNET"));
        vm.broadcast(deployerPrivateKey);
        newBorrowController = new BorrowController(gov, address(DBR));
        /**
        for(uint i; i < markets.length; ++i){
            address market = markets[i];
            require(DBR.markets(market), "Not a market");
            console.log("Market:", IErc20(IMarket(market).collateral()).name());
            IBC oldBorrowController = IBC(IMarket(market).borrowController());
            //console.log("Old BorrowController:", address(oldBorrowController));
            uint newLimit = newBorrowController.dailyLimits(market);
            uint newMinDebt = newBorrowController.minDebts(market);
            uint oldLimit = oldBorrowController.dailyLimits(market);
            uint oldMinDebt = oldBorrowController.minDebts(market);
            if(newLimit != oldLimit || newMinDebt != oldMinDebt){
                console.log("Old Limit  :", oldLimit);
                console.log("Old MinDebt:", oldMinDebt);
                console.log("New Limit  :", newLimit);
                console.log("New MinDebt:", newMinDebt);
                //vm.startBroadcast(deployerPrivateKey);
                //newBorrowController.setDailyLimit(market, oldLimit);
                //newBorrowController.setMinDebt(market, oldMinDebt);
                //vm.stopBroadcast();
            }
            console.log("----------------");
        }
        */
        //Add helper contract to allowList
        /*
        vm.startBroadcast(deployerPrivateKey);
        newBorrowController.allow(0x0aBb47c564296D34B0F5B068361985f507fe123c);
        newBorrowController.allow(0x0591926d5d3b9Cc48ae6eFB8Db68025ddc3adFA5);
        newBorrowController.allow(0x496a3Fc15209350487F7136b7c3c163F9204eE70);
        newBorrowController.allow(0x495886947EAce9788360F46be55c758f92Ecd074);
        newBorrowController.allow(0x5233f4C2515ae21B540c438862Abb5603506dEBC);


        //Transfer ownership to gov
        newBorrowController.setOperator(gov);
        */
    }
}
