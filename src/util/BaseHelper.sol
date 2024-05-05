// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITransformHelper} from "src/interfaces/ITransformHelper.sol";

/**
 * @title Base Helper
 * @notice This contract is a base helper contract for the ALE and markets.
 * @dev Base contract to be inherited in each helper contract.
 */
abstract contract BaseHelper is ITransformHelper {
    using SafeERC20 for IERC20;

    error NotGov();
    error NotPendingGov();
    error NotGuardianOrGov();
    error NotImplemented();

    address public gov;
    address public pendingGov;
    address public guardian;

    event NewGov(address gov);
    event NewPendingGov(address pendingGov);
    event NewGuardian(address guardian);

    /** @dev Constructor
    @param _gov The address of Inverse Finance governance
    @param _guardian The address of the guardian
    **/
    constructor(address _gov, address _guardian) {
        gov = _gov;
        guardian = _guardian;
    }

    modifier onlyGov() {
        if (msg.sender != gov) revert NotGov();
        _;
    }

    modifier onlyGuardianOrGov() {
        if (msg.sender != guardian || msg.sender != gov)
            revert NotGuardianOrGov();
        _;
    }

    /**
     * @notice Transforms the underlying token into the collateral token.
     * @dev Used by the ALE but can be called by anyone.
     * @param amount The amount of underlying token to be deposited.
     * @return shares The amount of collateral received.
     */
    function transformToCollateral(
        uint256 amount,
        bytes calldata data
    ) external virtual returns (uint256 shares) {}

    function transformToCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external virtual returns (uint256 shares) {}

    /**
     * @notice Transform the collateral token for the associated underlying token.
     * @dev Used by the ALE but can be called by anyone.
     * @param amount The amount of collateral token to be transformed.
     * @return assets The amount of underlying token after conversion.
     */
    function transformFromCollateral(
        uint256 amount,
        bytes calldata data
    ) external virtual returns (uint256 assets) {}

    function transformFromCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) external virtual returns (uint256 assets) {}

    function transformToCollateralAndDeposit(
        uint256 assets,
        address recipient,
        bytes calldata data
    ) external virtual returns (uint256 shares) {}

    function withdrawAndTransformFromCollateral(
        uint256 amount,
        address recipient,
        Permit calldata permit,
        bytes calldata data
    ) external virtual override returns (uint256 assets) {}

    /**
     * @notice Return current asset to collateral ratio.
     * @return collateralAmount The amount of collateral for 1 unit of asset.
     */
    function assetToCollateralRatio()
        external
        view
        virtual
        returns (uint256 collateralAmount)
    {}

    /**
     * @notice Estimate the amount of collateral for a given amount of asset.
     * @param assetAmount The amount of asset to be converted.
     * @return collateralAmount The amount of collateral for the given asset amount.
     */
    function assetToCollateral(
        uint256 assetAmount
    ) external view virtual returns (uint256 collateralAmount) {}

    /**
     * @notice Estimate the amount of asset for a given amount of collateral.
     * @param collateralAmount The amount of collateral to be converted.
     * @return assetAmount The amount of asset for the given collateral amount.
     */
    function collateralToAsset(
        uint256 collateralAmount
    ) external view virtual returns (uint256 assetAmount) {}

    /**
     * @notice Sweep any ERC20 token from the contract.
     * @dev Only callable by gov.
     * @param _token The address of the ERC20 token to be swept.
     */
    function sweep(address _token) external onlyGov {
        IERC20(_token).safeTransfer(
            gov,
            IERC20(_token).balanceOf(address(this))
        );
    }

    /**
     * @notice Sets the pendingGov, which can claim gov role.
     * @dev Only callable by gov
     * @param _pendingGov The address of the pendingGov
     */
    function setPendingGov(address _pendingGov) external onlyGov {
        pendingGov = _pendingGov;
        emit NewPendingGov(_pendingGov);
    }

    /**
     * @notice Claims the gov role
     * @dev Only callable by pendingGov
     */
    function claimPendingGov() external {
        if (msg.sender != pendingGov) revert NotPendingGov();
        gov = pendingGov;
        pendingGov = address(0);
        emit NewGov(gov);
    }

    /**
     * @notice Sets the guardian role
     * @dev Only callable by gov
     * @param _guardian The address of the guardian
     */
    function setGuardian(address _guardian) external onlyGov {
        guardian = _guardian;
        emit NewGuardian(_guardian);
    }
}
