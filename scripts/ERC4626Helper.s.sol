// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {ERC4626Helper} from "src/util/ERC4626Helper.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";

contract Deploy is Script, ConfigAddr {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.createSelectFork(vm.envString("RPC_MAINNET"));
        vm.broadcast(deployerPrivateKey);
        ERC4626Helper helper = new ERC4626Helper(gov, pauseGuardian);
    }
}
