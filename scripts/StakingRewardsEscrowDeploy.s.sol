// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {StakingRewardsEscrow} from "src/escrows/StakingRewardsEscrow.sol";

/// @notice Deploys an escrow implementation for the configured staking pool and sGOV vault.
/// @dev Set STAKING_REWARDS and SGOV; select the network and signer through the Forge CLI.
contract StakingRewardsEscrowDeploy is Script {
    function run() external returns (StakingRewardsEscrow implementation) {
        address stakingRewards = vm.envAddress("STAKING_REWARDS");
        address sGOV = vm.envAddress("SGOV");

        vm.startBroadcast();
        implementation = new StakingRewardsEscrow(stakingRewards, sGOV);
        vm.stopBroadcast();

        console2.log("StakingRewardsEscrow implementation deployed to", address(implementation));
        console2.log("Staking rewards pool", stakingRewards);
        console2.log("sGOV vault", sGOV);
    }
}
