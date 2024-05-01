// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IMarket} from "src/interfaces/IMarket.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ITransformHelper} from "src/interfaces/ITransformHelper.sol";

/**
@title ERC4626 Accelerated Leverage Engine Helper
@notice This contract is a generalized ALE helper contract for an ERC4626 vault market. 
@dev This contract is used by the ALE to interact with the ERC4626 vault and market.
**/

// TODO: add events, abstract base contract instead of interface
contract ERC4626AleHelper is ITransformHelper {
    using SafeERC20 for IERC20;

    error InsufficientShares();
    error AddressZero();
    error NotGov();
    error NotPendingGov();

    IMarket public immutable market;
    IERC20 public immutable underlying;
    IERC4626 public immutable vault;
    address public gov;
    address public pendingGov;

    event NewGov(address gov);
    event NewPendingGov(address pendingGov);

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
        address _gov
    ) {
        vault = IERC4626(_vault);
        market = IMarket(_market);
        underlying = IERC20(_underlying);
        gov = _gov;
    }

    modifier onlyGov() {
        if (msg.sender != gov) revert NotGov();
        _;
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
    ) external returns (uint256 shares) {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        underlying.approve(address(vault), amount);
        shares = vault.deposit(amount, address(this));
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
        IERC20(address(vault)).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        vault.approve(address(market), amount);
        assets = vault.redeem(amount, msg.sender, address(this));
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
    ) external returns (uint256 shares) {
        underlying.safeTransferFrom(msg.sender, address(this), assets);
        underlying.approve(address(vault), assets);
        shares = vault.deposit(assets, address(this));

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
    ) external view returns (uint256 collateralAmount) {
        return vault.convertToShares(assetAmount);
    }

    /**
     * @notice Estimate the amount of asset for a given amount of collateral.
     * @param collateralAmount The amount of collateral to be converted.
     * @return assetAmount The amount of asset for the given collateral amount.
     */
    function collateralToAsset(
        uint256 collateralAmount
    ) external view returns (uint256 assetAmount) {
        return vault.convertToAssets(collateralAmount);
    }

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
}
