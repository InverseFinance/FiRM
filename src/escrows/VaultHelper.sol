// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IMarket} from "src/interfaces/IMarket.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
@title Vault Helper
@notice This contract is a helper contract for an ERC4626 vault contract. 
It allows users to deposit and withdraw ERC20 tokens from the vault contract and deposit and withdraw shares from the market.
**/
contract VaultHelper {
    using SafeERC20 for IERC20;
    
    error InsufficientShares();
    error AddressZero();

    IMarket public immutable market;
    IERC20 public immutable token;
    IERC4626 public immutable vault;

    /** @dev Constructor
    @param _vault The address of the ERC4626 vault
    @param _market The address of the market
    @param _token The address of the ERC20 token
    **/
    constructor(address _vault, address _market, address _token) {
        vault = IERC4626(_vault);
        market = IMarket(_market);
        token = IERC20(_token);
        maxApprove();
    }

    /**
    @notice Deposit the associated ERC20 token into the ERC4626 vault and deposit the received shares for recipient.
    @param recipient The address to receive payment from the escrow
    @param assets The amount of ERC20 token to be transferred.
    */
    function wrapAndDeposit(
        address recipient,
        uint assets
    ) external returns (uint256 shares) {
        if(recipient == address(0)) revert AddressZero();
        token.safeTransferFrom(msg.sender, address(this), assets);
        shares = vault.deposit(assets, address(this));
        uint256 actualShares = vault.balanceOf(address(this));
        if (shares > actualShares) revert InsufficientShares();
        market.deposit(recipient, actualShares);
    }


    /**
    @notice Withdraw the shares from the market then withdraw the associated ERC20 token from the ERC4626 vault.
    @param recipient The address to receive payment from the escrow
    @param shares The amount of ERC4626 token to be withdrawn from the market.
    @param deadline The deadline for the transaction to be executed
    @param v The v value of the signature
    @param r The r value of the signature
    @param s The s value of the signature
    @return assets The amount of ERC20 token withdrawn from the ERC4626 vault.
     */
    function withdrawAndUnwrap(
        address recipient,
        uint shares,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 assets) {
        if(recipient == address(0)) revert AddressZero();
        market.withdrawOnBehalf(recipient, shares, deadline, v, r, s);
        uint256 actualShares = vault.balanceOf(address(this));
        if (actualShares < shares) revert InsufficientShares();
        assets = vault.redeem(shares, recipient, address(this));
    }
    /**
     * @notice Refreshes approvals for vault and market contract
     */
    function maxApprove() public {
        token.approve(address(vault), type(uint).max);
        vault.approve(address(market), type(uint).max);
    }
}
