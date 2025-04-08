// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseEscrowLPConvexTest} from "test/escrowForkTests/BaseEscrowLPConvexTest.t.sol";

contract DolaUSREscrowConvexForkTest is BaseEscrowLPConvexTest {
    // Curve
    address _dolaUSR = 0x38De22a3175708D45E7c7c64CD78479C8B56f76E;
    address _lpHolder = address(0x89836bB3a0471adBa7DEf2677292c07004308Feb);
    address _gauge = 0xd303994a0Db9b74f3E8fF629ba3097fC7060C331;

    // Convex
    uint256 _pid = 421;
    address _rewardPool = 0xE694a5e9272ea7ed2DC25f0c6D21640fb8a83166;
    address _stash = 0x63A8AE4C4fE19B8816dEa970544F8a446051cB89;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21969468);
        BaseEscrowLPConvexTest.ConvexInfo memory convexParams = ConvexInfo(
            _pid,
            _rewardPool,
            _stash
        );

        init(_dolaUSR, _lpHolder, _gauge, convexParams, true);
    }
}
