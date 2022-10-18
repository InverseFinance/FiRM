// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// @dev Caution: We assume all failed transfers cause reverts and ignore the returned bool.
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

/**
@title INV Escrow
@notice Collateral is stored in unique escrow contracts for every user and every market.
 This escrow allows user to deposit INV collateral directly into the xINV contract, earning APY and allowing them to delegate votes on behalf of the xINV collateral
@dev Caution: This is a proxy implementation. Follow proxy pattern best practices
*/
contract INVEscrow {
    address public market;
    IERC20 public token;
    address public beneficiary;
    IXINV public immutable xINV;

    constructor(IXINV _xINV) {
        xINV = _xINV; // TODO: Test whether an immutable variable will persist across proxies
    }

    /**
    @notice Initialize escrow with a token
    @dev Must be called right after proxy is created.
    @param _token The IERC20 token representing the INV governance token
    @param _beneficiary The beneficiary who may delegate token voting power
    */
    function initialize(IERC20 _token, address _beneficiary) public {
        require(market == address(0), "ALREADY INITIALIZED");
        market = msg.sender;
        token = _token;
        beneficiary = _beneficiary;
        _token.delegate(_token.delegates(_beneficiary));
        _token.approve(address(xINV), type(uint).max);
        xINV.syncDelegate(address(this));
    }

    /**
    @notice Transfers the associated ERC20 token to a recipient.
    @param recipient The address to receive payment from the escrow
    @param amount The amount of ERC20 token to be transferred.
    */
    function pay(address recipient, uint amount) public {
        require(msg.sender == market, "ONLY MARKET");
        uint invBalance = token.balanceOf(address(this));
        if(invBalance < amount) xINV.redeemUnderlying(amount - invBalance); // we do not check return value because next call will fail if this fails anyway
        token.transfer(recipient, amount);
    }

    /**
    @notice Get the token balance of the escrow
    @return Uint representing the INV token balance of the escrow including the additional INV accrued from xINV
    */
    function balance() public view returns (uint) {
        uint invBalance = token.balanceOf(address(this));
        uint invBalanceInXInv = xINV.balanceOf(address(this)) * xINV.exchangeRateStored() / 1 ether;
        return invBalance + invBalanceInXInv;
    }
    /**
    @notice Function called by market on deposit. Will deposit INV into xINV 
    @dev This function should remain callable by anyone to handle direct inbound transfers.
    */
    function onDeposit() public {
        uint invBalance = token.balanceOf(address(this));
        if(invBalance > 0) {
            xINV.mint(invBalance); // we do not check return value because we don't want errors to block this call
        }
    }

    /**
    @notice Delegates voting power of the underlying xINV.
    @param delegatee The address to be delegated voting power
    */
    function delegate(address delegatee) public {
        require(msg.sender == beneficiary);
        token.delegate(delegatee);
        xINV.syncDelegate(address(this));
    }
}
