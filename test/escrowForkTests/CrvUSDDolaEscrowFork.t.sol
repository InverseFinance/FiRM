// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseEscrowLPTest} from "test/escrowForkTests/BaseEscrowLPTest.t.sol";

contract DolaCrvUSDDolaEscrowForkTest is BaseEscrowLPTest {
    // Curve
    address _crvUSDDola = 0x8272E1A3dBef607C04AA6e5BD3a1A134c8ac063B;
    address _lpHolder = 0xb634316E06cC0B358437CbadD4dC94F1D3a92B3b;
    address _gauge = 0xEcAD6745058377744c09747b2715c0170B5699e5;

    // Convex
    uint256 _pid = 215;
    address _rewardPool = 0xC94208D230EEdC4cDC4F80141E21aA485A515660;
    address _depositToken = 0x408abF1a02388A5EF19E3dB1e08db5eFdC510DFF;
    address _stash = 0x25F5Ccd892985Bf878327B15815bd90066EEf28d;

    // Yearn
    address _yearnVault = 0xfb5137Aa9e079DB4b7C2929229caf503d0f6DA96;
    address _yearnHolder = 0x8B5b1D02AAB4e10e49507e89D2bE10A382D52b57;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20020781);
        BaseEscrowLPTest.ConvexInfo memory convexParams = ConvexInfo(
            _pid,
            _rewardPool,
            _depositToken,
            _stash
        );

        BaseEscrowLPTest.YearnInfo memory yearnParams = YearnInfo(
            _yearnVault,
            _yearnHolder
        );

        init(_crvUSDDola, _lpHolder, _gauge, convexParams, yearnParams, true);
    }
}
