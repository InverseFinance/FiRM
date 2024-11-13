pragma solidity ^0.8.20;
import {IERC20} from "src/interfaces/IERC20.sol";

interface IEscrow {
    /**
     * @notice Initiatilizes the escrow clone after creation
     * @dev Must be called immediately after deployment
     * @param _token Collateral token of the escrow
     * @param _beneficiary Beneficiary of the escrow
     */
    function initialize(IERC20 _token, address _beneficiary) external;

    /**
     * @notice Transfers the associated ERC20 token to a recipient.
     * @param recipient The address to receive payment from the escrow
     * @param amount The amount of ERC20 token to be transferred.
     */
    function pay(address recipient, uint amount) external;

    /**
     * @notice Get the token balance of the escrow
     * @return Uint representing the token balance of the escrow including any additional tokens that may have been accrued
     */
    function balance() external view returns (uint);

    /**
     * @notice Function called by market on deposit. Function is empty for this escrow.
     * @dev This function should remain callable by anyone to handle direct inbound transfers.
     */
    function onDeposit() external;
}
