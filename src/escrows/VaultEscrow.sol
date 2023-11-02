// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

/**
@title Vault Escrow
@notice Collateral is stored in unique escrow contracts for every user and every market.
This escrow allows user to deposit collateral directly into the ERC4626 contract, earning yield
@dev Caution: This is a proxy implementation. Follow proxy pattern best practices
*/
contract VaultEscrow {
    address public market;
    IERC20 public token;
    IERC4626 public immutable vault;

    constructor(address _vault){
        vault = IERC4626(_vault);
    }

    /**
    @notice Initialize escrow with a token
    @dev Must be called right after proxy is created
    @param _token The IERC20 token to be stored in this specific escrow
    */
    function initialize(IERC20 _token, address) public {
        require(market == address(0), "ALREADY INITIALIZED");
        market = msg.sender;
        token = _token;
        token.approve(address(vault), type(uint).max);
    }
    
    /**
    @notice Transfers the associated ERC20 token to a recipient.
    @param recipient The address to receive payment from the escrow
    @param amount The amount of ERC20 token to be transferred.
    */
    function pay(address recipient, uint amount) public {
        require(msg.sender == market, "ONLY MARKET");
        if(amount == balance()){
            vault.redeem(vault.balanceOf(address(this)), recipient, address(this));
        } else {
            vault.withdraw(amount, recipient, address(this));
        }
    }

    /**
    @notice Get the token balance of the escrow
    @return Uint representing the token balance of the escrow
    */
    function balance() public view returns (uint) {
        uint vaultBalance = vault.balanceOf(address(this));
        return vault.convertToAssets(vaultBalance);
    }

    /**
    @notice Function called by market on deposit. Function is empty for this escrow.
    @dev This function should remain callable by anyone to handle direct inbound transfers.
    */
    function onDeposit() public {
        uint tokenBalance = token.balanceOf(address(this));
        if(tokenBalance > 0) {
            vault.deposit(tokenBalance, address(this));
        }
    }
}
