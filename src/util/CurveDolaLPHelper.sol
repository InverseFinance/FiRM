// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IMarket} from "src/interfaces/IMarket.sol";
import {Sweepable, SafeERC20, IERC20} from "src/util/Sweepable.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IYearnVaultV2} from "src/interfaces/IYearnVaultV2.sol";

/**
 * @title CurveLP Helper for ALE and Market
 * @notice This contract is a generalized ALE helper contract for a curve pool with 2 and 3 coins with DOLA. Also support YearnV2 vaults for this LP.
 * @dev This contract is used by the ALE to interact with Dola Curve pools or YearnV2 Curve vaults and market.
 * Can also be used by anyone to perform add/remove liquidity from and to DOLA and deposit/withdraw operations.
 **/

contract CurveDolaLPHelper is Sweepable, IMultiMarketTransformHelper {
    using SafeERC20 for IERC20;

    error InsufficientLP();
    error InsufficientShares();
    error MarketNotSet(address market);
    error NotImplemented();

    uint256 public constant POOL_LENGTH_2 = 2;
    uint256 public constant POOL_LENGTH_3 = 3;

    struct Pool {
        ICurvePool pool;
        uint128 dolaIndex;
        uint128 length;
        IYearnVaultV2 vault;
    }

    event MarketSet(
        address indexed market,
        uint128 dolaIndex,
        address indexed pool,
        address indexed yearnVault
    );
    event MarketRemoved(address indexed market);

    IERC20 public immutable DOLA;

    /// @notice Mapping of market addresses to their associated Curve Pools.
    mapping(address => Pool) public markets;

    /** @dev Constructor
    @param _gov The address of Inverse Finance governance
    @param _guardian The address of the guardian
    **/
    constructor(
        address _gov,
        address _guardian,
        address _dola
    ) Sweepable(_gov, _guardian) {
        DOLA = IERC20(_dola);
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
     * @param recipient The address on behalf of which the collateralAmount are deposited.
     * @param data The encoded address of the market.
     * @return collateralAmount The amount of LP or Yearn token received.
     */
    function transformToCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) public override returns (uint256 collateralAmount) {
        (address market, uint256 minMint) = abi.decode(
            data,
            (address, uint256)
        );
        _revertIfMarketNotSet(market);

        IYearnVaultV2 vault = markets[market].vault;
        // If vault is set, add DOLA liquidity to Curve Pool and then deposit the LP token into the Yearn Vault
        if (address(vault) != address(0)) {
            uint256 lpAmount = _addLiquidity(
                market,
                amount,
                minMint,
                address(this)
            );
            return
                _depositToYearn(
                    address(markets[market].pool),
                    vault,
                    lpAmount,
                    recipient
                );
        } else {
            // Just add DOLA liquidity to the pool
            return _addLiquidity(market, amount, minMint, recipient);
        }
    }

    /**
     * @notice Redeems the LP or Yearn token for DOLA.
     * @dev Used by the ALE but can be called by anyone.
     * @param amount The amount of LP or Yearn token to be redeemed.
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
        (address market, uint256 minOut) = abi.decode(data, (address, uint256));
        _revertIfMarketNotSet(market);

        ICurvePool pool = markets[market].pool;
        IYearnVaultV2 vault = markets[market].vault;
        uint128 dolaIndex = markets[market].dolaIndex;

        // If vault is set, withdraw LP token from the Yearn Vault and then remove liquidity from the pool
        if (address(vault) != address(0)) {
            IERC20(address(vault)).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
            uint256 lpAmount = vault.withdraw(amount);

            return
                _removeLiquidity(pool, lpAmount, dolaIndex, minOut, recipient);
        } else {
            // Just remove liquidity from the pool
            IERC20(address(pool)).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );

            return _removeLiquidity(pool, amount, dolaIndex, minOut, recipient);
        }
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
        (address market, ) = abi.decode(data, (address, uint256));
        _revertIfMarketNotSet(market);

        // Convert DOLA to LP or Yearn token
        uint256 amount = transformToCollateral(assets, address(this), data);

        IYearnVaultV2 vault = markets[market].vault;

        // If Vault is set, deposit the Yearn token into the market
        if (address(vault) != address(0)) {
            uint256 actualAmount = vault.balanceOf(address(this));
            if (amount > actualAmount) revert InsufficientShares();

            return
                _approveAndDepositIntoMarket(
                    address(vault),
                    market,
                    actualAmount,
                    recipient
                );
        } else {
            // Deposit the LP token into the market
            ICurvePool pool = markets[market].pool;
            uint256 actualLP = IERC20(address(pool)).balanceOf(address(this));
            if (actualLP < amount) revert InsufficientLP();

            return
                _approveAndDepositIntoMarket(
                    address(pool),
                    market,
                    actualLP,
                    recipient
                );
        }
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
        (address market, uint256 minOut) = abi.decode(data, (address, uint256));
        _revertIfMarketNotSet(market);

        IMarket(market).withdrawOnBehalf(
            msg.sender,
            amount,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );

        ICurvePool pool = markets[market].pool;
        IYearnVaultV2 vault = markets[market].vault;

        // Withdraw from the vault if it is set and then remove liquidity from the pool
        if (address(vault) != address(0)) {
            uint256 lpAmount = vault.withdraw(amount);
            _revertIfNotEnoughLP(pool, lpAmount);

            return
                _removeLiquidity(
                    pool,
                    lpAmount,
                    markets[market].dolaIndex,
                    minOut,
                    recipient
                );
        } else {
            // Just remove liquidity from the pool
            _revertIfNotEnoughLP(pool, amount);
            return
                _removeLiquidity(
                    pool,
                    amount,
                    markets[market].dolaIndex,
                    minOut,
                    recipient
                );
        }
    }

    function _addLiquidity(
        address market,
        uint256 amount,
        uint256 minMint,
        address recipient
    ) internal returns (uint256 lpAmount) {
        DOLA.safeTransferFrom(msg.sender, address(this), amount);

        uint128 dolaIndex = markets[market].dolaIndex;
        ICurvePool pool = markets[market].pool;
        DOLA.approve(address(pool), amount);

        // Support for 2 and 3 coins pools
        if (markets[market].length == POOL_LENGTH_2) {
            uint256[POOL_LENGTH_2] memory amounts;
            amounts[dolaIndex] = amount;
            return pool.add_liquidity(amounts, minMint, recipient);
        } else if (markets[market].length == POOL_LENGTH_3) {
            uint256[POOL_LENGTH_3] memory amounts;
            amounts[dolaIndex] = amount;
            return pool.add_liquidity(amounts, minMint, recipient);
        } else revert NotImplemented();
    }

    function _depositToYearn(
        address pool,
        IYearnVaultV2 vault,
        uint256 lpAmount,
        address recipient
    ) internal returns (uint256 collateralAmount) {
        IERC20(pool).approve(address(vault), lpAmount);
        return vault.deposit(lpAmount, recipient);
    }

    function _approveAndDepositIntoMarket(
        address collateral,
        address market,
        uint256 amount,
        address recipient
    ) internal returns (uint256) {
        IERC20(collateral).approve(market, amount);
        IMarket(market).deposit(recipient, amount);
        return amount;
    }

    function _removeLiquidity(
        ICurvePool pool,
        uint256 amount,
        uint128 dolaIndex,
        uint256 minOut,
        address recipient
    ) internal returns (uint256 dolaAmount) {
        dolaAmount = pool.remove_liquidity_one_coin(
            amount,
            int128(dolaIndex),
            minOut,
            recipient
        );
    }

    function _revertIfNotEnoughLP(
        ICurvePool pool,
        uint256 amount
    ) internal view {
        uint256 actualLP = IERC20(address(pool)).balanceOf(address(this));
        if (actualLP < amount) revert InsufficientLP();
    }

    function _revertIfMarketNotSet(address market) internal view {
        if (address(markets[market].pool) == address(0))
            revert MarketNotSet(market);
    }

    /**
     * @notice Set the market address and its associated Curve Pool and dola Index.
     * @dev Only callable by the governance.
     * @param marketAddress The address of the market.
     * @param dolaIndex Dola index in the coins array for Curve Pools.
     * @param poolAddress The address of the curve pool with DOLA.
     */
    function setMarket(
        address marketAddress,
        address poolAddress,
        uint128 dolaIndex,
        uint128 length,
        address vaultAddress
    ) external onlyGov {
        markets[marketAddress] = Pool({
            pool: ICurvePool(poolAddress),
            dolaIndex: dolaIndex,
            length: length,
            vault: IYearnVaultV2(vaultAddress)
        });
        emit MarketSet(marketAddress, dolaIndex, poolAddress, vaultAddress);
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
