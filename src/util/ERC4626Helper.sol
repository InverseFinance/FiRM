// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IMarket} from "src/interfaces/IMarket.sol";
import {Sweepable, SafeERC20, IERC20} from "src/util/Sweepable.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";

/**
 * @title ERC4626 Accelerated Leverage Engine Helper
 * @notice This contract is a generalized ALE helper contract for an ERC4626 vault market.
 * @dev This contract is used by the ALE to interact with the ERC4626 vault and market.
 * Can also be used by anyone to perform wrap/unwrap and deposit/withdraw operations.
 **/

contract ERC4626Helper is Sweepable, IMultiMarketTransformHelper {
    using SafeERC20 for IERC20;

    error InsufficientShares();
    error MarketNotSet(address market);
    error NotImplemented();

    struct Vault {
        IERC4626 vault;
        IERC20 underlying;
    }

    event MarketSet(
        address indexed market,
        address indexed underlying,
        address indexed vault
    );
    event MarketRemoved(address indexed market);

    /// @notice Mapping of market addresses to their associated vaults.
    mapping(address => Vault) public markets;

    /** @dev Constructor
    @param _gov The address of Inverse Finance governance
    @param _guardian The address of the guardian
    **/
    constructor(address _gov, address _guardian) Sweepable(_gov, _guardian) {}

    /**
     * @notice Deposits the underlying token into the ERC4626 vault and returns the received ERC4626 token.
     * @dev Used by the ALE but can be called by anyone.
     * @param amount The amount of underlying token to be deposited.
     * @param data The encoded address of the market.
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
     * @param data The encoded address of the market.
     * @return shares The amount of ERC4626 token received.
     */
    function transformToCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) public override returns (uint256 shares) {
        address market = abi.decode(data, (address));
        _revertIfMarketNotSet(market);

        IERC20 underlying = markets[market].underlying;
        IERC4626 vault = markets[market].vault;

        underlying.safeTransferFrom(msg.sender, address(this), amount);
        underlying.approve(address(vault), amount);
        shares = vault.deposit(amount, recipient);
    }

    /**
     * @notice Redeems the ERC4626 token for the associated underlying token.
     * @dev Used by the ALE but can be called by anyone.
     * @param amount The amount of ERC4626 token to be redeemed.
     * @param data The encoded address of the market.
     * @return assets The amount of underlying token redeemed.
     */
    function transformFromCollateral(
        uint256 amount,
        bytes calldata data
    ) external override returns (uint256 assets) {
        assets = transformFromCollateral(amount, msg.sender, data);
    }

    /**
     * @notice Redeems the ERC4626 token for the associated underlying token.
     * @dev Use custom recipient address.
     * @param amount The amount of ERC4626 token to be redeemed.
     * @param recipient The address to which the underlying token is transferred.
     * @param data The encoded address of the market.
     * @return assets The amount of underlying token redeemed.
     */
    function transformFromCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) public override returns (uint256 assets) {
        address market = abi.decode(data, (address));
        _revertIfMarketNotSet(market);

        IERC4626 vault = markets[market].vault;

        IERC20(address(vault)).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        vault.approve(market, amount);
        assets = vault.redeem(amount, recipient, address(this));
    }

    /**
     * @notice Deposit the associated underlying token into the ERC4626 vault and deposit the received shares for recipient.
     * @param assets The amount of underlying token to be transferred.
     * @param recipient The address on behalf of which the shares are deposited.
     * @param data The encoded address of the market.
     * @return shares The amount of ERC4626 token deposited into the market.
     */
    function transformToCollateralAndDeposit(
        uint256 assets,
        address recipient,
        bytes calldata data
    ) external override returns (uint256 shares) {
        address market = abi.decode(data, (address));
        _revertIfMarketNotSet(market);

        IERC4626 vault = markets[market].vault;

        shares = transformToCollateral(assets, address(this), data);

        uint256 actualShares = vault.balanceOf(address(this));
        if (shares > actualShares) revert InsufficientShares();

        vault.approve(market, actualShares);
        IMarket(market).deposit(recipient, actualShares);
    }

    /**
     * @notice Withdraw the shares from the market then withdraw the associated underlying token from the ERC4626 vault.
     * @param amount The amount of ERC4626 token to be withdrawn from the market.
     * @param recipient The address to which the underlying token is transferred.
     * @param permit The permit data for the Market.
     * @param data The encoded address of the market.
     * @return assets The amount of underlying token withdrawn from the ERC4626 vault.
     */
    function withdrawAndTransformFromCollateral(
        uint256 amount,
        address recipient,
        Permit calldata permit,
        bytes calldata data
    ) external override returns (uint256 assets) {
        address market = abi.decode(data, (address));
        _revertIfMarketNotSet(market);

        IERC4626 vault = markets[market].vault;

        IMarket(market).withdrawOnBehalf(
            msg.sender,
            amount,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );
        uint256 actualShares = vault.balanceOf(address(this));
        if (actualShares < amount) revert InsufficientShares();

        vault.approve(market, actualShares);
        assets = vault.redeem(actualShares, recipient, address(this));
    }

    /**
     * @notice Return current asset to collateral ratio.
     * @return collateralAmount The amount of collateral for 1 unit of asset.
     */
    function assetToCollateralRatio(
        address market
    ) external view returns (uint256 collateralAmount) {
        _revertIfMarketNotSet(market);
        IERC4626 vault = markets[market].vault;
        return vault.convertToShares(10 ** vault.decimals());
    }

    /**
     * @notice Estimate the amount of collateral for a given amount of asset.
     * @param market The address of the market.
     * @param assetAmount The amount of asset to be converted.
     * @return collateralAmount The amount of collateral for the given asset amount.
     */
    function assetToCollateral(
        address market,
        uint256 assetAmount
    ) external view returns (uint256 collateralAmount) {
        _revertIfMarketNotSet(market);
        IERC4626 vault = markets[market].vault;
        return vault.convertToShares(assetAmount);
    }

    /**
     * @notice Estimate the amount of asset for a given amount of collateral.
     * @param market The address of the market.
     * @param collateralAmount The amount of collateral to be converted.
     * @return assetAmount The amount of asset for the given collateral amount.
     */
    function collateralToAsset(
        address market,
        uint256 collateralAmount
    ) external view returns (uint256 assetAmount) {
        _revertIfMarketNotSet(market);
        IERC4626 vault = markets[market].vault;
        return vault.convertToAssets(collateralAmount);
    }

    function _revertIfMarketNotSet(address market) internal view {
        if (
            markets[market].vault == IERC4626(address(0)) ||
            markets[market].underlying == IERC20(address(0))
        ) revert MarketNotSet(market);
    }

    /**
     * @notice Set the market address and its associated vault and underlying token.
     * @dev Only callable by the governance.
     * @param marketAddress The address of the market.
     * @param underlyingAddress The address of the underlying token.
     * @param vaultAddress The address of the ERC4626 vault.
     */
    function setMarket(
        address marketAddress,
        address underlyingAddress,
        address vaultAddress
    ) external onlyGov {
        markets[marketAddress] = Vault({
            vault: IERC4626(vaultAddress),
            underlying: IERC20(underlyingAddress)
        });
        emit MarketSet(marketAddress, underlyingAddress, vaultAddress);
    }

    /**
     * @notice Remove the market by setting the vault and underlying token to address(0).
     * @dev Only callable by the governance or the guardian.
     * @param market The address of the market to be removed.
     */
    function removeMarket(address market) external onlyGuardianOrGov {
        markets[market].vault = IERC4626(address(0));
        markets[market].underlying = IERC20(address(0));
        emit MarketRemoved(market);
    }
}
