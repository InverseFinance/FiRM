// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "../interfaces/IERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// @dev Caution: We assume all failed transfers cause reverts and ignore the returned bool.
interface DSR {
    function daiBalance(address usr) public returns (uint wad);
    function join(address dst, uint wad) public;
    function exit(address dst, uint wad) public;
}

/**
 * @title DAI Escrow
 * @notice Collateral is stored in unique escrow contracts for every user and every market.
 * This escrow allows user to deposit DAI collateral directly into the xDAI contract, earning APY and allowing them to delegate votes on behalf of the xDAI collateral
 * @dev Caution: This is a proxy implementation. Follow proxy pattern best practices
 */
contract DAIEscrow {
    using FixedPointMathLib for uint;

    address public market;
    IDelegateableERC20 public token;
    DSR public constant DSR_MANAGER = DSR(0x373238337Bfe1146fb49989fc222523f83081dDb);
    address public beneficiary;

    /**
     * @notice Initialize escrow with a token
     * @dev Must be called right after proxy is created.
     * @param _token The IERC20 token representing DAI
     * @param _beneficiary The beneficiary who may delegate token voting power
     */
    function initialize(IDelegateableERC20 _token, address _beneficiary) public {
        require(market == address(0), "ALREADY INITIALIZED");
        market = msg.sender;
        token = _token;
        beneficiary = _beneficiary;
        _token.approve(address(DSR_MANAGER), type(uint).max);
    }
    
    /**
     * @notice Transfers the associated ERC20 token to a recipient.
     * @param recipient The address to receive payment from the escrow
     * @param amount The amount of ERC20 token to be transferred.
     */
    function pay(address recipient, uint amount) public {
        require(msg.sender == market, "ONLY MARKET");
        DSR_MANAGER.exit(recipient, amount);
    }

    /**
    * @notice Get the token balance of the escrow
    * @return Uint representing the DAI token balance of the escrow including the additional DAI accrued from DAI
    */
    function balance() public view returns (uint) {
        return DSR_MANAGER.daiBalance(address(this));
    }
    
    /**
     * @notice Function called by market on deposit. Will deposit DAI into the DSR
     * @dev This function should remain callable by anyone to handle direct inbound transfers.
     */
    function onDeposit() public {
        uint daiBalance = token.balanceOf(address(this));
        if(daiBalance > 0) {
            DSR_MANAGER.join(address(this), daiBalance);
        }
    }
}
