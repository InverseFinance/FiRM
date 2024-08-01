// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseEscrowLPConvexTest} from "test/escrowForkTests/BaseEscrowLPConvexTest.t.sol";

contract DolaFraxBPEscrowConvexForkTest is BaseEscrowLPConvexTest {
    // Curve
    address _dolaFraxBP = 0xE57180685E3348589E9521aa53Af0BCD497E884d;
    address _lpHolder = address(0x4E2f395De08C11d28bE37Fb2F19f6F5869136567);
    address _gauge = 0xBE266d68Ce3dDFAb366Bb866F4353B6FC42BA43c;

    // Convex
    uint256 _pid = 115;
    address _rewardPool = 0x0404d05F3992347d2f0dC3a97bdd147D77C85c1c;
    address _depositToken = 0xf7eCC27CC9DB5d28110AF2d89b176A6623c7E351;
    address _stash = 0xe5A980F96c791c8Ea56c2585840Cab571441510e;

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

        init(_dolaFraxBP, _lpHolder, _gauge, convexParams, true);
    }
}
