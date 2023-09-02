// SPDX-License-Identifier: UNLICENSED 
pragma solidity ^0.8.13;

import "src/DbrDistributor.sol";
import "src/interfaces/IDBR.sol";

contract DBRMock is IDBR {
    address market;
    mapping (address => uint) balances;
    mapping (address => bool) public markets;

    function allowMarket(address _market) external {
        markets[_market] = true;
    }

    function balanceOf(address holder) external view returns(uint){
        return balances[holder];
    }

    function mint(address user, uint amount) external {
        balances[user] += amount;
    }
}

