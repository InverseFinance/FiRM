// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {StakingRewardsEscrow} from "src/escrows/StakingRewardsEscrow.sol";

/// @notice Deploys an escrow implementation for the configured staking pool.
/// @dev Set STAKING_REWARDS; select the network and signer through the Forge CLI.
contract StakingRewardsEscrowDeploy is Script {
    function run() external returns (StakingRewardsEscrow implementation) {
        address stakingRewards = vm.envAddress("STAKING_REWARDS");

        vm.startBroadcast();
        implementation = new StakingRewardsEscrow(stakingRewards);
        vm.stopBroadcast();

        console2.log("StakingRewardsEscrow implementation deployed to", address(implementation));
        console2.log("Staking rewards pool", stakingRewards);
    }
}
