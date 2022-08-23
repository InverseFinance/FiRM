// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Caution. We assume all failed transfers cause reverts and ignore the returned bool.
interface IERC20 {
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
    function approve(address, uint) external view returns (uint);
    function delegate(address delegatee) external;
    function delegates(address delegator) external view returns (address delegatee);
}

interface IXINV {
    function balanceOf(address) external view returns (uint);
    function exchangeRateStored() external view returns (uint);
    function mint(uint mintAmount) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function syncDelegate(address user) external;
}

// Caution. This is a proxy implementation. Follow proxy pattern best practices
contract INVEscrow {
    address public market;
    IERC20 public token;
    address public beneficiary;
    IXINV public immutable xINV;

    constructor(IXINV _xINV) {
        xINV = _xINV; // TODO: Test whether an immutable variable will persist across proxies
    }

    function initialize(IERC20 _token, address _beneficiary) public {
        require(market == address(0), "ALREADY INITIALIZED");
        market = msg.sender;
        token = _token;
        beneficiary = _beneficiary;
        _token.delegate(_token.delegates(_beneficiary));
        _token.approve(address(xINV), type(uint).max);
        xINV.syncDelegate(address(this));
    }

    function pay(address recipient, uint amount) public {
        require(msg.sender == market, "ONLY MARKET");
        uint invBalance = token.balanceOf(address(this));
        if(invBalance < amount) xINV.redeemUnderlying(amount - invBalance); // we do not check return value because next call will fail if this fails anyway
        token.transfer(recipient, amount);
    }

    function balance() public view returns (uint) {
        uint invBalance = token.balanceOf(address(this));
        uint invBalanceInXInv = xINV.balanceOf(address(this)) * xINV.exchangeRateStored() / 1 ether;
        return invBalance + invBalanceInXInv;
    }

     //This function should remain callable by anyone to handle direct inbound transfers.
    function onDeposit() public {
        uint invBalance = token.balanceOf(address(this));
        if(invBalance > 0) {
            xINV.mint(invBalance); // we do not check return value because we don't want errors to block this call
        }
    }

    function delegate(address delegatee) public {
        require(msg.sender == beneficiary);
        token.delegate(delegatee);
        xINV.syncDelegate(address(this));
    }
}