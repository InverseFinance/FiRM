// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {ALEV2} from "src/util/ALEV2.sol";

contract ALEV2Deploy is Script {
    address internal constant DEFAULT_GOV = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address internal constant DEFAULT_DBR_POOL = 0x66da369fC5dBBa0774Da70546Bd20F2B242Cd34d;

    error InvalidGovernance();
    error InvalidDbrPool(address pool);

    function run() external returns (ALEV2 ale) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address governance = vm.envOr("ALE_GOV", DEFAULT_GOV);
        address dbrPool = vm.envOr("ALE_DBR_POOL", DEFAULT_DBR_POOL);

        if (governance == address(0)) revert InvalidGovernance();
        if (dbrPool.code.length == 0) revert InvalidDbrPool(dbrPool);

        vm.startBroadcast(deployerPrivateKey);
        ale = new ALEV2(dbrPool, governance);
        vm.stopBroadcast();

        console2.log("ALEv2 deployed to", address(ale));
        console2.log("Governance", governance);
        console2.log("DOLA/DBR pool", dbrPool);
    }
}
