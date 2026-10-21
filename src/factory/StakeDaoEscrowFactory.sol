// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StakeDaoEscrow} from "src/escrows/StakeDaoEscrow.sol";

contract StakeDaoEscrowFactory {
    mapping(address => bool) public isFromFactory;

    event NewStakeDaoEscrow(
        address indexed rewardVault, address indexed treasury, address indexed escrowImplementation
    );

    /**
     * @notice Deploy a new StakeDaoEscrow implementation.
     * @dev Markets use this implementation to create borrower-specific escrow clones.
     * @param rewardVault StakeDAO reward vault used by the escrow implementation
     * @param treasury Referrer address passed to the reward vault on deposits
     */
    function deployEscrow(address rewardVault, address treasury) external returns (address escrowImplementation) {
        escrowImplementation = address(new StakeDaoEscrow(rewardVault, treasury));
        isFromFactory[escrowImplementation] = true;

        emit NewStakeDaoEscrow(rewardVault, treasury, escrowImplementation);
    }
}
