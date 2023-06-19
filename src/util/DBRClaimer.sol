pragma solidity ^0.8.13;

import {IDBRClaimer} from "src/util/IDBRClaimer.sol";
import "src/util/IVault.sol";
import {Market} from "src/Market.sol";
import {INVEscrow} from "src/escrows/INVEscrow.sol";
import "src/interfaces/IMarket.sol";

interface ICurvePool {
    function coins(uint index) external view returns(address);
    function get_dy(uint i, uint j, uint dx) external view returns(uint);
    function exchange(uint i, uint j, uint dx, uint min_dy) external payable returns(uint);
    function exchange(uint i, uint j, uint dx, uint min_dy, bool use_eth) external payable returns(uint);
    function exchange(uint i, uint j, uint dx, uint min_dy, bool use_eth, address receiver) external payable returns(uint);
}

contract DBRClaimer is IDBRClaimer {

    IERC20 DBR = IERC20(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
    IERC20 DOLA = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 INV = IERC20(0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68);
    ICurvePool DBRDolaPool = ICurvePool(0x056ef502C1Fc5335172bc95EC4cAE16C2eB9b5b6);
    bytes32 DOLAInvPoolId = 0x441b8a1980f2f2e43a9397099d15cc2fe6d3625000020000000000000000035f;
    IVault vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    Market invMarket = Market(0xb516247596Ca36bf32876199FBdCaD6B3322330B);
    IVault.FundManagement fundManangement;


    constructor() {
        DBR.approve(address(DBRDolaPool), type(uint).max);
        INV.approve(address(invMarket), type(uint).max);
        DOLA.approve(address(vault), type(uint).max);
        fundManangement.sender = address(this);
        fundManangement.fromInternalBalance = false;
        fundManangement.recipient = payable(address(this));
        fundManangement.toInternalBalance = false;

    }

    //Claims DBR and immediately sells it for DOLA
    function claimAndSell(uint minDOLA) external {
        uint DOLAReceived = _claimAndSell(minDOLA);
        DOLA.transfer(msg.sender, DOLAReceived);
    }

    function _claimAndSell(uint minDOLA) internal returns(uint){
        address escrow = address(invMarket.predictEscrow(msg.sender));
        INVEscrow(escrow).claimDBRTo(address(this));
        uint DBRIndex = 0;
        uint DOLAIndex = 1;
        return DBRDolaPool.exchange(DBRIndex, DOLAIndex, DBR.balanceOf(address(this)), minDOLA);
    }

    //Claims DBR, sells it for DOLA and uses it to repay debt in market on behalf of msg.sender
    function claimAndRepay(address market, uint minDOLA) external {
        claimAndRepay(msg.sender, market, minDOLA);
    }

    //Claims DBR, sells it for DOLA, and uses it to repay debt in market on behalf of borrower
    function claimAndRepay(address borrower, address market, uint minDOLA) public{
        uint DOLAReceived = _claimAndSell(minDOLA);
        uint debt = IMarket(market).debts(borrower);
        if(DOLAReceived > debt){
            IMarket(market).repay(borrower, debt);
            DOLA.transfer(borrower, DOLAReceived - debt);
        } else {
            IMarket(market).repay(borrower, DOLAReceived);
        }
    }

    //Claims DBR and compounds it into xINV in the market
    function claimAndCompound(uint minINV) external {
        uint DOLAReceived = _claimAndSell(0); //min out is 0, since we revert on minINV
        uint invReceived = _buyInv(DOLAReceived, minINV);
        invMarket.deposit(msg.sender, invReceived);
    }

    /**
    @notice Buys as much INV as possible for DOLA in a balancer pool
    @param amount Amount of DBR to receive
    @param minOut minimum amount of INV to receive
    @return Amount of INV bought
    */
    function _buyInv(uint amount, uint minOut) internal returns(uint){
        IVault.SingleSwap memory swapStruct;

        //Populate Single Swap struct
        swapStruct.poolId = DOLAInvPoolId;
        swapStruct.kind = IVault.SwapKind.GIVEN_IN;
        swapStruct.assetIn = IAsset(address(DOLA));
        swapStruct.assetOut = IAsset(address(INV));
        swapStruct.amount = amount;
        //swapStruct.userData: User data can be left empty

        return vault.swap(swapStruct, fundManangement, minOut, block.timestamp);
    }
}
