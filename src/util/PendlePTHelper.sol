// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IMarket} from "src/interfaces/IMarket.sol";
import {Sweepable, SafeERC20, IERC20} from "src/util/Sweepable.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IYearnVaultV2} from "src/interfaces/IYearnVaultV2.sol";

/**
 * @title Pendle PT ALE and market helper
 * @notice This contract is a generalized ALE and market helper contract for Pendle PT tokens.
 * @dev Carefully prepare the router calldata from Pendle API when using it from the ALE:
 * When converting TO collateral, the receiver in Pendle API has to be set to this contract address
 * When converting FROM collateral, the receiver in Pendle API has to be set to the ALE address
 **/

contract PendlePTHelper is Sweepable, IMultiMarketTransformHelper {
    using SafeERC20 for IERC20;

    error InsufficientDOLA();
    error InsufficientPT();
    error MarketNotSet(address market);
    error PendleSwapFailed();

    struct PT {
        address pt;
        address yt;
    }

    event MarketSet(
        address indexed market,
        address indexed pt,
        address indexed yt
    );
    event MarketRemoved(address indexed market);

    IERC20 public immutable DOLA;
    address public immutable router;

    /// @notice Mapping of market addresses to their associated Curve Pools.
    mapping(address => PT) public markets;

    /** @dev Constructor
    @param _gov The address of Inverse Finance governance
    @param _guardian The address of the guardian
    @param _pendleRouter The address of the Pendle Router
    **/
    constructor(
        address _gov,
        address _guardian,
        address _dola,
        address _pendleRouter
    ) Sweepable(_gov, _guardian) {
        DOLA = IERC20(_dola);
        router = _pendleRouter;
    }

    /**
     * @notice Deposits DOLA into the Curve Pool and returns the received LP token.
     * @dev Used by the ALE but can be called by anyone.
     * @param amount The amount of underlying token to be deposited.
     * @param data The encoded address of the market.
     * @return collateralAmount The amount of LP token received.
     */
    function transformToCollateral(
        uint256 amount,
        bytes calldata data
    ) external override returns (uint256 collateralAmount) {
        collateralAmount = transformToCollateral(amount, msg.sender, data);
    }

    /**
     * @notice Deposits DOLA into the Curve Pool and returns the received LP token or Yearn token.
     * @dev Use custom recipient address.
     * @param amount The amount of DOLA to be deposited.
     * @param recipient The recipient address of the LP or Yearn token.
     * @param data The encoded address of the market.
     * @return collateralAmount The amount of LP or Yearn token received.
     */
    function transformToCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) public override returns (uint256 collateralAmount) {
        (
            address market,
            uint256 minMint,
            address ytRecipient,
            bytes memory callData
        ) = abi.decode(data, (address, uint256, address, bytes));

        _revertIfMarketNotSet(market);

        IERC20 pt = IERC20(markets[market].pt);
        DOLA.safeTransferFrom(msg.sender, address(this), amount);

        DOLA.approve(router, amount);
        (bool success, ) = router.call(callData);
        if (!success) revert PendleSwapFailed();

        uint256 ptBal = pt.balanceOf(address(this));
        if (ptBal < minMint || ptBal == 0) revert InsufficientPT();
        if (recipient != address(this)) pt.safeTransfer(recipient, ptBal);

        if (ytRecipient != address(0)) {
            IERC20 yt = IERC20(markets[market].yt);
            yt.safeTransfer(ytRecipient, yt.balanceOf(address(this)));
        }

        return ptBal;
    }

    /**
     * @notice Redeems the PT token for DOLA.
     * @dev Used by the ALE but can be called by anyone.
     * @param amount The amount of PT token to be redeemed.
     * @param data The encoded address of the market.
     * @return dolaAmount The amount of DOLA redeemed.
     */
    function transformFromCollateral(
        uint256 amount,
        bytes calldata data
    ) external override returns (uint256 dolaAmount) {
        dolaAmount = transformFromCollateral(amount, msg.sender, data);
    }

    /**
     * @notice Redeems Collateral for DOLA.
     * @dev Use custom recipient address.
     * @param amount The amount of LP or Yearn Token to be redeemed.
     * @param recipient The address to which the underlying token is transferred.
     * @param data The encoded address of the market.
     * @return dolaAmount The amount of DOLA redeemed.
     */
    function transformFromCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) public override returns (uint256 dolaAmount) {
        (
            address market,
            uint256 minOut,
            address ytProvider,
            bytes memory callData
        ) = abi.decode(data, (address, uint256, address, bytes));
        _revertIfMarketNotSet(market);

        if (ytProvider != address(0)) {
            IERC20 yt = IERC20(markets[market].yt);
            yt.safeTransferFrom(ytProvider, address(this), amount);
            yt.approve(router, amount);
        }

        IERC20 pt = IERC20(markets[market].pt);
        pt.safeTransferFrom(msg.sender, address(this), amount);
        pt.approve(router, amount);

        uint256 dolaBal = DOLA.balanceOf(recipient);
        (bool success, ) = router.call(callData);
        if (!success) revert PendleSwapFailed();
        // Ensure recipient received at least minOut DOLA
        dolaAmount = DOLA.balanceOf(recipient) - dolaBal;
        if (dolaAmount < minOut) revert InsufficientDOLA();
    }

    /**
     * @notice Convert DOLA into LP or Yearn token and deposit the received amount for recipient.
     * @param assets The amount of DOLA to be converted.
     * @param recipient The address on behalf of which the LP or Yearn are deposited.
     * @param data The encoded address of the market.
     * @return collateralAmount The amount of collateral deposited into the market.
     */
    function transformToCollateralAndDeposit(
        uint256 assets,
        address recipient,
        bytes calldata data
    ) external override returns (uint256) {
        (address market, , , ) = abi.decode(
            data,
            (address, uint256, address, bytes)
        );

        // Convert DOLA to PT token
        uint256 amount = transformToCollateral(assets, address(this), data);

        // Deposit PT into Market
        IERC20(markets[market].pt).approve(market, amount);
        IMarket(market).deposit(recipient, amount);

        return amount;
    }

    /**
     * @notice Withdraw the collateral from the market then convert to DOLA.
     * @param amount The amount of LP or Yearn token to be withdrawn from the market.
     * @param recipient The address to which DOLA is transferred.
     * @param permit The permit data for the Market.
     * @param data The encoded address of the market.
     * @return dolaAmount The amount of DOLA redeemed.
     */
    function withdrawAndTransformFromCollateral(
        uint256 amount,
        address recipient,
        Permit calldata permit,
        bytes calldata data
    ) external override returns (uint256 dolaAmount) {
        (
            address market,
            uint256 minOut,
            address ytProvider,
            bytes memory callData
        ) = abi.decode(data, (address, uint256, address, bytes));
        _revertIfMarketNotSet(market);

        IMarket(market).withdrawOnBehalf(
            msg.sender,
            amount,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );

        if (ytProvider != address(0)) {
            IERC20 yt = IERC20(markets[market].yt);
            yt.safeTransferFrom(ytProvider, address(this), amount);
            yt.approve(router, amount);
        }

        IERC20 pt = IERC20(markets[market].pt);
        pt.approve(router, amount);

        uint256 dolaBal = DOLA.balanceOf(recipient);
        (bool success, ) = router.call(callData);
        if (!success) revert PendleSwapFailed();

        dolaAmount = DOLA.balanceOf(recipient) - dolaBal;
        if (dolaAmount < minOut) revert InsufficientDOLA();
    }

    function _revertIfMarketNotSet(address market) internal view {
        if (address(markets[market].pt) == address(0))
            revert MarketNotSet(market);
    }

    /**
     * @notice Set the market address and its associated Curve Pool and dola Index.
     * @dev Only callable by the governance.
     * @param marketAddress The address of the market.
     * @param ptAddress Dola index in the coins array for Curve Pools.
     * @param ytAddress The address of the curve pool with DOLA.
     */
    function setMarket(
        address marketAddress,
        address ptAddress,
        address ytAddress
    ) external onlyGov {
        markets[marketAddress] = PT({pt: ptAddress, yt: ytAddress});
        emit MarketSet(marketAddress, ptAddress, ytAddress);
    }

    /**
     * @notice Remove the market.
     * @dev Only callable by the governance or the guardian.
     * @param market The address of the market to be removed.
     */
    function removeMarket(address market) external onlyGuardianOrGov {
        delete markets[market];
        emit MarketRemoved(market);
    }
}
