pragma solidity ^0.8.13;

import {ALEV2, IERC20, IPendleHelper} from "src/util/ALEV2.sol";
import {DbrHelper} from "src/util/DbrHelper.sol";

contract Migration {
    address[] public markets = [0x63Df5e23Db45a2066508318f172bA45B9CD37035, // WETH
                        0x27b6c301Fd441f3345d61B7a4245E1F823c3F9c4, // yvyCRV
                        0x3474ad0e3a9775c9F68B415A7a9880B0CAB9397a, //cvxCRV
                        0xdc2265cBD15beD67b5F2c0B82e23FcE4a07ddF6b, //CVX
                        0x3FD3daBB9F9480621C8A111603D3Ba70F17550BC, // wstETH
                        0x48BA574Edf0bc4E2E40B529863aaA6a67c264E7C, // WBTC
                        0x0c0bb843FAbda441edeFB93331cFff8EC92bD168, // styETH
                        0x79eF6d28C41e47A588E2F2ffB4140Eb6d952AEc4, //sUSDe
                        0x2A256306D8ba899E33B01e495982656884Ac77FF,// cbBTC
                        0xb427fC22561f3963B04202F9bb5BCEbd76c14A99, //sUSDe-DOLA
                        0x4E264618dC015219CD83dbc53B31251D73c2db1a, //yv-sUSDe-DOLA
                        0xD68d3a44d46dd50BFeBa8Cca544717B76e7C4b29, //sUSDS-DOLA
                        0x4A33baFA8a31E4ec9649f65646022cAD1957808b, //yv-sUSDS-DOLA
                        0x2fed508aAc87c0e6f0b647Fe83164A7AA6eb2FC9, //scrvUSD-DOLA
                        0x5bb8f6aAcFF2971B42F9fE6945D24726A2541CF2, //yv-scrvUSD-DOLA
                        0x63D27fC9d463Ed727676367D3F818999962737E8, //scrvUSD-sDOLA
                        0xb8bc1E9c0a2d445bc39d2A745F47619E954dD565, // yv-scrvUSD-sDOLA
                        0x3Ac5CEbC7A417DB619B85660E4f284f5643DFd5e, //USR-DOLA
                        0xC0086Ff652c67f43F00F0F9C69Ef6c33640C8cCF, //yv-USR-DOLA
                        0xe4D47Ef77AC2C3FA4019Cd169Ac1Dd9E27cb12E4, //wstUSR-DOLA
                        0x28684485369f7478f42aAA62660123AB5D573537, //yv-wstUSR-DOLA
                        0x63fAd99705a255fE2D500e498dbb3A9aE5AA1Ee8, // CRV
                        0xb516247596Ca36bf32876199FBdCaD6B3322330B // INV
                        ];
   
    ALEV2 public constant OLD_ALE = ALEV2(payable(0x4dF2EaA1658a220FDB415B9966a9ae7c3d16e240));
    address public constant GOV = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    
    ALEV2 public immutable ale;
    DbrHelper public immutable dbrHelper;
 

    constructor(address _ale, address _dbrHelper) {
        ale = ALEV2(payable(_ale));
        dbrHelper = DbrHelper(_dbrHelper);
    } 

    modifier onlyGov() {
        require(msg.sender == GOV, "Only gov");
        _;
    }

    function migrate() external onlyGov {
        ale.claimPendingGov();
        dbrHelper.claimPendingGov();

        _setALEMarkets();
        _setDbrMarkets();
        
        ale.setPendingGov(GOV);
        dbrHelper.setPendingGov(GOV);
    }

    function _setALEMarkets() internal {
        for (uint i = 0; i < markets.length; i++) {
        (IERC20 buySellToken,
        ,
        IPendleHelper helper,
        bool useProxy) = getMarket(markets[i]);
        
        ale.setMarket(markets[i], address(buySellToken), address(helper), useProxy);
        }
        
    }

    function _setDbrMarkets() internal {
        for (uint i = 0; i < markets.length; i++) {
             dbrHelper.approveMarket(markets[i]);
        }
    }
    
    function getMarket(address market) internal view returns (IERC20 buySellToken,
        IERC20 collateral,
        IPendleHelper helper,
        bool useProxy) {

        (buySellToken,
        collateral,
        helper,
        useProxy) = OLD_ALE.markets(market);

        return (buySellToken, collateral, helper, useProxy);
    } 
    
    function getMarkets() external view returns (address[] memory) {
        return markets;
    }
}  