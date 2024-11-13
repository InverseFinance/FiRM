// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Governable} from "src/util/Governable.sol";

/**
 * @title Sweepable and Governable contracts
 * @notice This contract can be used to sweep tokens to the gov address and add governalble functionality
 */
contract Sweepable is Governable {
    using SafeERC20 for IERC20;

    constructor(address _gov, address _guardian) Governable(_gov, _guardian) {}

    /**
     * @notice Sweeps the specified token to the gov address
     * @dev Only callable by gov
     * @param token The address of the token to be swept
     */
    function sweep(address token) external onlyGov {
        IERC20(token).safeTransfer(gov, IERC20(token).balanceOf(address(this)));
    }
}
