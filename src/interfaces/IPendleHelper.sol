//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

interface IPendleHelper {
    struct Permit {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function convertToCollateral(
        address user,
        uint256 amount,
        bytes calldata data
    ) external returns (uint256 collateralAmount);

    function convertToCollateral(
        uint256 amount,
        bytes calldata data
    ) external returns (uint256 collateralAmount);

    function convertToCollateralAndDeposit(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external returns (uint256 collateralAmount);

    function convertFromCollateral(
        address user,
        uint256 amount,
        bytes calldata data
    ) external returns (uint256);

    function convertFromCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external returns (uint256);

    function withdrawAndConvertFromCollateral(
        uint256 amount,
        address recipient,
        Permit calldata permit,
        bytes calldata data
    ) external returns (uint256 underlyingAmount);
}
