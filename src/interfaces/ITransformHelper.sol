//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

interface ITransformHelper {
    function transformToCollateral(uint amount, bytes calldata data) external returns (uint);

    function transformToCollateralAndDeposit(
        uint amount,
        address user,
        bytes calldata data
    ) external returns (uint);

    function transformFromCollateral(uint amount, bytes calldata data) external returns (uint);

    function withdrawAndTransformFromCollateral(
        uint amount,
        address user,
        bytes calldata data,
        uint v,
        uint r,
        uint8 s
    ) external returns (uint);

    function assetToCollateralRatio(
        uint assetAmount
    ) external view returns (uint collateralAmount);
}
