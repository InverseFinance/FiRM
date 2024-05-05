// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IMarket} from "src/interfaces/IMarket.sol";
import {BaseHelper, SafeERC20, IERC20} from "src/util/BaseHelper.sol";

/**
 * @title ERC4626 Accelerated Leverage Engine Helper
 * @notice This contract is a generalized ALE helper contract for an ERC4626 vault market.
 * @dev This contract is used by the ALE to interact with the ERC4626 vault and market.
 * Can also be used by anyone to perform wrap/unwrap and deposit/withdraw operations.
 **/

contract ERC4626AleHelperNew is BaseHelper {
    using SafeERC20 for IERC20;

    error InsufficientShares();

    IMarket public immutable market;
    IERC20 public immutable underlying;
    IERC4626 public immutable vault;

    /** @dev Constructor
    @param _vault The address of the ERC4626 vault
    @param _market The address of the market
    @param _underlying The address of the ERC20 underlying;
    @param _gov The address of Inverse Finance governance
    **/
    constructor(
        address _vault,
        address _market,
        address _underlying,
        address _gov,
        address _guardian
    ) BaseHelper(_gov, _guardian) {
        vault = IERC4626(_vault);
        market = IMarket(_market);
        underlying = IERC20(_underlying);
    }

    /**
     * @notice Deposits the underlying token into the ERC4626 vault and returns the received ERC4626 token.
     * @dev Used by the ALE but can be called by anyone.
     * @param amount The amount of underlying token to be deposited.
     * @return shares The amount of ERC4626 token received.
     */
    function transformToCollateral(
        uint256 amount,
        bytes calldata data
    ) external override returns (uint256 shares) {
        shares = transformToCollateral(amount, msg.sender, data);
    }

    /**
     * @notice Deposits the underlying token into the ERC4626 vault and returns the received ERC4626 token.
     * @dev Use custom recipient address.
     * @param amount The amount of underlying token to be deposited.
     * @param recipient The address on behalf of which the shares are deposited.
     */
    function transformToCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) public override returns (uint256 shares) {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        underlying.approve(address(vault), amount);
        shares = vault.deposit(amount, recipient);
    }

    /**
     * @notice Redeems the ERC4626 token for the associated underlying token.
     * @dev Used by the ALE but can be called by anyone.
     * @param amount The amount of ERC4626 token to be redeemed.
     * @return assets The amount of underlying token redeemed.
     */
    function transformFromCollateral(
        uint256 amount,
        bytes calldata data
    ) external override returns (uint256 assets) {
        assets = transformFromCollateral(amount, msg.sender, data);
    }

    function transformFromCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) public override returns (uint256 assets) {
        IERC20(address(vault)).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        vault.approve(address(market), amount);
        assets = vault.redeem(amount, recipient, address(this));
    }

    /**
     * @notice Deposit the associated underlying token into the ERC4626 vault and deposit the received shares for recipient.
     * @param assets The amount of underlying token to be transferred.
     * @param recipient The address on behalf of which the shares are deposited.
     * @return shares The amount of ERC4626 token deposited into the market.
     */
    function transformToCollateralAndDeposit(
        uint256 assets,
        address recipient,
        bytes calldata data
    ) external override returns (uint256 shares) {
        shares = transformToCollateral(assets, address(this), data);

        uint256 actualShares = vault.balanceOf(address(this));
        if (shares > actualShares) revert InsufficientShares();

        vault.approve(address(market), actualShares);
        market.deposit(recipient, actualShares);
    }

    /**
     * @notice Withdraw the shares from the market then withdraw the associated underlying token from the ERC4626 vault.
     * @param amount The amount of ERC4626 token to be withdrawn from the market.
     * @param recipient The address to which the underlying token is transferred.
     * @param permit The permit data for the Market.
     * @return assets The amount of underlying token withdrawn from the ERC4626 vault.
     */
    function withdrawAndTransformFromCollateral(
        uint256 amount,
        address recipient,
        Permit calldata permit,
        bytes calldata data
    ) external override returns (uint256 assets) {
        market.withdrawOnBehalf(
            msg.sender,
            amount,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );
        uint256 actualShares = vault.balanceOf(address(this));
        if (actualShares < amount) revert InsufficientShares();

        vault.approve(address(market), actualShares);
        assets = vault.redeem(actualShares, recipient, address(this));
    }

    /**
     * @notice Return current asset to collateral ratio.
     * @return collateralAmount The amount of collateral for 1 unit of asset.
     */
    function assetToCollateralRatio()
        external
        view
        override
        returns (uint256 collateralAmount)
    {
        return vault.convertToShares(10 ** vault.decimals());
    }

    /**
     * @notice Estimate the amount of collateral for a given amount of asset.
     * @param assetAmount The amount of asset to be converted.
     * @return collateralAmount The amount of collateral for the given asset amount.
     */
    function assetToCollateral(
        uint256 assetAmount
    ) external view override returns (uint256 collateralAmount) {
        return vault.convertToShares(assetAmount);
    }

    /**
     * @notice Estimate the amount of asset for a given amount of collateral.
     * @param collateralAmount The amount of collateral to be converted.
     * @return assetAmount The amount of asset for the given collateral amount.
     */
    function collateralToAsset(
        uint256 collateralAmount
    ) external view override returns (uint256 assetAmount) {
        return vault.convertToAssets(collateralAmount);
    }
}