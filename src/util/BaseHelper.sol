// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITransformHelper} from "src/interfaces/ITransformHelper.sol";
import {Sweepable} from "src/util/Sweepable.sol";

/**
 * @title Base Helper
 * @notice This contract is a base helper contract for the ALE and markets.
 * @dev Base contract to be inherited in each helper contract.
 */
abstract contract BaseHelper is ITransformHelper, Sweepable {
    error NotImplemented();

    /** @dev Constructor
    @param _gov The address of Inverse Finance governance
    @param _guardian The address of the guardian
    **/
    constructor(address _gov, address _guardian) Sweepable(_gov, _guardian) {}

    /**
     * @notice Transforms the underlying token into the collateral token.
     * @dev Used by the ALE but can be called by anyone.
     * @param amount The amount of underlying token to be deposited.
     * @return shares The amount of collateral received.
     */
    function transformToCollateral(
        uint256 amount,
        bytes calldata data
    ) external virtual returns (uint256 shares) {
        revert NotImplemented();
    }

    function transformToCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external virtual returns (uint256 shares) {
        revert NotImplemented();
    }

    /**
     * @notice Transform the collateral token for the associated underlying token.
     * @dev Used by the ALE but can be called by anyone.
     * @param amount The amount of collateral token to be transformed.
     * @return assets The amount of underlying token after conversion.
     */
    function transformFromCollateral(
        uint256 amount,
        bytes calldata data
    ) external virtual returns (uint256 assets) {
        revert NotImplemented();
    }

    function transformFromCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external virtual returns (uint256 assets) {
        revert NotImplemented();
    }

    function transformToCollateralAndDeposit(
        uint256 assets,
        address recipient,
        bytes calldata data
    ) external virtual returns (uint256 shares) {
        revert NotImplemented();
    }

    function withdrawAndTransformFromCollateral(
        uint256 amount,
        address recipient,
        Permit calldata permit,
        bytes calldata data
    ) external virtual override returns (uint256 assets) {
        revert NotImplemented();
    }

    /**
     * @notice Return current asset to collateral ratio.
     * @return collateralAmount The amount of collateral for 1 unit of asset.
     */
    function assetToCollateralRatio()
        external
        view
        virtual
        returns (uint256 collateralAmount)
    {
        revert NotImplemented();
    }

    /**
     * @notice Estimate the amount of collateral for a given amount of asset.
     * @param assetAmount The amount of asset to be converted.
     * @return collateralAmount The amount of collateral for the given asset amount.
     */
    function assetToCollateral(
        uint256 assetAmount
    ) external view virtual returns (uint256 collateralAmount) {
        revert NotImplemented();
    }

    /**
     * @notice Estimate the amount of asset for a given amount of collateral.
     * @param collateralAmount The amount of collateral to be converted.
     * @return assetAmount The amount of asset for the given collateral amount.
     */
    function collateralToAsset(
        uint256 collateralAmount
    ) external view virtual returns (uint256 assetAmount) {
        revert NotImplemented();
    }
}
