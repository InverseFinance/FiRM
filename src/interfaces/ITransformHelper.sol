//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

interface ITransformHelper {
    
    struct Permit {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function transformToCollateral(
        uint amount,
        bytes calldata data
    ) external returns (uint);

    function transformToCollateralAndDeposit(
        uint amount,
        bytes calldata data
    ) external returns (uint256 collateralAmount);

    function transformFromCollateral(
        uint amount,
        bytes calldata data
    ) external returns (uint);

    function withdrawAndTransformFromCollateral(
        uint amount,
        Permit calldata permit,
        bytes calldata data
    ) external returns (uint256 underlyingAmount);

    function assetToCollateralRatio(
        uint assetAmount
    ) external view returns (uint collateralAmount);

    function assetToCollateral(
        uint assetAmount
    ) external view returns (uint collateralAmount);
    
    function collateralToAsset(
        uint collateralAmount
    ) external view returns (uint assetAmount);
}
