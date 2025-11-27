// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/util/Ownable.sol";

/**
 * @title Guardable
 * @notice This contract adds Guardian and Operator roles functionality
 */
contract Guardable is Ownable {
    error NotGuardian();
    error NotOperator();
    error NotGuardianOrGov();
    error NotOperatorOrGov();

    address public guardian;
    address public operator;

    event NewGuardian(address guardian);
    event NewOperator(address operator);

    /** @dev Constructor
    @param _gov The address of Inverse Finance governance
    @param _guardian The address of the guardian
    @param _operator The address of the operator
    **/
    constructor(address _gov, address _guardian, address _operator) Ownable(_gov) {
        guardian = _guardian;
        operator = _operator;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert NotGuardian();
        _;
    }

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    modifier onlyGuardianOrGov() {
        if (msg.sender != guardian && msg.sender != gov)
            revert NotGuardianOrGov();
        _;
    }

    modifier onlyOperatorOrGov() {
        if (msg.sender != operator && msg.sender != gov)
            revert NotOperatorOrGov();
        _;
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

    /**
     * @notice Sets the operator role
     * @dev Only callable by gov
     * @param _operator The address of the operator
     */
    function setOperator(address _operator) external onlyGov {
        operator = _operator;
        emit NewOperator(_operator);
    }
}
