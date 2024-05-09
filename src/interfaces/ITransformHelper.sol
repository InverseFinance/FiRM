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
        uint256 amount,
        bytes calldata data
    ) external returns (uint256 collateralAmount);

    function transformToCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external returns (uint256 collateralAmount);

    function transformToCollateralAndDeposit(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external returns (uint256 collateralAmount);

    function transformFromCollateral(
        uint256 amount,
        bytes calldata data
    ) external returns (uint256);

    function transformFromCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external returns (uint256);

    function withdrawAndTransformFromCollateral(
        uint256 amount,
        address recipient,
        Permit calldata permit,
        bytes calldata data
    ) external returns (uint256 underlyingAmount);

    function assetToCollateralRatio(
        address market
    ) external view returns (uint256 collateralAmount);

    function assetToCollateral(
        address market,
        uint256 assetAmount
    ) external view returns (uint256 collateralAmount);

    function collateralToAsset(
        address market,
        uint256 collateralAmount
    ) external view returns (uint256 assetAmount);
}
