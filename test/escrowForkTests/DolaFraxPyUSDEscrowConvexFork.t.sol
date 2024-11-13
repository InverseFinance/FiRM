// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseEscrowLPConvexTest} from "test/escrowForkTests/BaseEscrowLPConvexTest.t.sol";

contract DolaFraxPyUSDEscrowForkTest is BaseEscrowLPConvexTest {
    // Curve
    address _dolaFraxPyUSD = 0xef484de8C07B6e2d732A92B5F78e81B38f99f95E;
    address _lpHolder = 0xBFa04e5D6Ac1163b7Da3E873e5B9C969E91A0Ac0;
    address _gauge = 0x4B092818708A721cB187dFACF41f440ADb79044D;

    // Convex
    uint256 _pid = 317;
    address _rewardPool = 0xE8cBdBFD4A1D776AB1146B63ABD1718b2F92a823;
    address _depositToken = 0x430bE19e180fd8c2199eC5FAEabE2F5CDba68C94;
    address _stash = 0x6bCc4b00F2Cc9CdFF935E1A5D939f26A233Dd381;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20020781);
        BaseEscrowLPConvexTest.ConvexInfo memory convexParams = ConvexInfo(
            _pid,
            _rewardPool,
            _depositToken,
            _stash
        );

        init(_dolaFraxPyUSD, _lpHolder, _gauge, convexParams, true);
    }
}
