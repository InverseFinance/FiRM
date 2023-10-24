// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

/**
@title sFrax Escrow
@notice Collateral is stored in unique escrow contracts for every user and every market.
This escrow allows user to deposit FRAX collateral directly into the sFRAX ERC4626 contract, earning FRAX yield which is accounted for FRAX collateral
@dev Caution: This is a proxy implementation. Follow proxy pattern best practices
*/
contract SFraxEscrow {
    address public market;
    IERC20 public token;
    IERC4626 public constant sFrax = IERC4626(0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32);

    /**
    @notice Initialize escrow with a token
    @dev Must be called right after proxy is created
    @param _token The IERC20 token to be stored in this specific escrow
    */
    function initialize(IERC20 _token, address) public {
        require(market == address(0), "ALREADY INITIALIZED");
        market = msg.sender;
        token = _token;
        token.approve(address(sFrax), type(uint).max);
    }
    
    /**
    @notice Transfers the associated ERC20 token to a recipient.
    @param recipient The address to receive payment from the escrow
    @param amount The amount of ERC20 token to be transferred.
    */
    function pay(address recipient, uint amount) public {
        require(msg.sender == market, "ONLY MARKET");
        if(amount == balance()){
            amount += 1;
        }
        uint256 sFraxAmount = sFrax.convertToShares(amount);
        sFrax.redeem(sFraxAmount, recipient, address(this));
    }

    /**
    @notice Get the token balance of the escrow
    @return Uint representing the token balance of the escrow
    */
    function balance() public view returns (uint) {
        uint sFraxBalance = sFrax.balanceOf(address(this));
        return sFrax.convertToAssets(sFraxBalance);
    }

    /**
    @notice Function called by market on deposit. Function is empty for this escrow.
    @dev This function should remain callable by anyone to handle direct inbound transfers.
    */
    function onDeposit() public {
        uint fraxBalance = token.balanceOf(address(this));
        if(fraxBalance > 0) {
            sFrax.deposit(fraxBalance, address(this));
        }
    }
}
