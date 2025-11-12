// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Ownable
 * @notice This contract adds Ownable functionality to the contract
 */
contract Ownable {
    error NotGov();
    error NotPendingGov();

    address public gov;
    address public pendingGov;

    event NewGov(address indexed gov);
    event NewPendingGov(address indexed pendingGov);

    /** @dev Constructor
    @param _gov The address of Inverse Finance governance
    **/
    constructor(address _gov) {
        gov = _gov;
    }

    modifier onlyGov() {
        if (msg.sender != gov) revert NotGov();
        _;
    }

    /**
     * @notice Sets the pendingGov, which can claim gov role.
     * @dev Only callable by gov
     * @param _pendingGov The address of the pendingGov
     */
    function setPendingGov(address _pendingGov) external onlyGov {
        pendingGov = _pendingGov;
        emit NewPendingGov(_pendingGov);
    }

    /**
     * @notice Claims the gov role
     * @dev Only callable by pendingGov
     */
    function claimPendingGov() external {
        if (msg.sender != pendingGov) revert NotPendingGov();
        gov = pendingGov;
        pendingGov = address(0);
        emit NewGov(gov);
    }
}
