// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Caution. We assume all failed transfers cause reverts and ignore the returned bool.
interface IERC20 {
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
    function delegate(address delegatee) external;
    function delegates(address delegator) external view returns (address delegatee);
}

// Caution. This is a proxy implementation. Follow proxy pattern best practices
contract GovTokenEscrow {
    address public market;
    IERC20 public token;
    address public beneficiary;

    function initialize(IERC20 _token, address _beneficiary) public {
        require(market == address(0), "ALREADY INITIALIZED");
        market = msg.sender;
        token = _token;
        beneficiary = _beneficiary;
        _token.delegate(_token.delegates(_beneficiary));
    }

    function pay(address recipient, uint amount) public {
        require(msg.sender == market, "ONLY MARKET");
        token.transfer(recipient, amount);
    }

    function balance() public view returns (uint) {
        return token.balanceOf(address(this));
    }

    /* Uncomment if Escrow contract should handle on deposit callbacks. This function should remain callable by anyone to handle direct inbound transfers.
    function onDeposit() public {

    }
    */

    function delegate(address delegatee) public {
        require(msg.sender == beneficiary);
        token.delegate(delegatee);
    }
}