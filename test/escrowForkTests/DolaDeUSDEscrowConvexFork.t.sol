// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseEscrowLPConvexTest} from "test/escrowForkTests/BaseEscrowLPConvexTest.t.sol";

contract DolaDeUSDEscrowConvexForkTest is BaseEscrowLPConvexTest {
    // Curve
    address _dolaDeUSD = 0x6691DBb44154A9f23f8357C56FC9ff5548A8bdc4;
    address _lpHolder = address(0xcb4a7b790eDB7Fa3e2731Efd7ED85275f92Fc74A);
    address _gauge = 0xa48A3c91b062ca06Fd0d0569695432EB066f8c7E;

    // Convex
    uint256 _pid = 419;
    address _rewardPool = 0xD30E66cBc869Aa808eB9c81f8Aad8408767E3a3E;
    address _stash = 0x074297Bf0dEA6925c27526E6E3E3151D8cE4edc7;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21826229);
        BaseEscrowLPConvexTest.ConvexInfo memory convexParams = ConvexInfo(
            _pid,
            _rewardPool,
            _stash
        );

        init(_dolaDeUSD, _lpHolder, _gauge, convexParams, true);
    }
}
