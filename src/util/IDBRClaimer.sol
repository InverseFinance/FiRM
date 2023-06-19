pragma solidity ^0.8.13;

interface IDBRClaimer {
    //Claims DBR and immediately sells it for DOLA
    function claimAndSell(uint minDOLA) external;
    //Claims DBR, sells it for DOLA and uses it to repay debt in market on behalf of msg.sender
    function claimAndRepay(address market, uint minDOLA) external;
    //Claims DBR, sells it for DOLA, and uses it to repay debt in market on behalf of borrower
    function claimAndRepay(address borrower, address market, uint minDOLA) external;
    //Claims DBR and compounds it into xINV in the market
    function claimAndCompound(uint minINV) external;
}
