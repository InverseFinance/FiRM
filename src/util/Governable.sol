// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title Governable
 * @notice This contract is add Governable functionality to the contract
 */
contract Governable {
    error NotGov();
    error NotPendingGov();
    error NotGuardianOrGov();

    address public gov;
    address public pendingGov;
    address public guardian;

    event NewGov(address gov);
    event NewPendingGov(address pendingGov);
    event NewGuardian(address guardian);

    /** @dev Constructor
    @param _gov The address of Inverse Finance governance
    @param _guardian The address of the guardian
    **/
    constructor(address _gov, address _guardian) {
        gov = _gov;
        guardian = _guardian;
    }

    modifier onlyGov() {
        if (msg.sender != gov) revert NotGov();
        _;
    }

    modifier onlyGuardianOrGov() {
        if (msg.sender != guardian || msg.sender != gov)
            revert NotGuardianOrGov();
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

    /**
     * @notice Sets the guardian role
     * @dev Only callable by gov
     * @param _guardian The address of the guardian
     */
    function setGuardian(address _guardian) external onlyGov {
        guardian = _guardian;
        emit NewGuardian(_guardian);
    }
}
