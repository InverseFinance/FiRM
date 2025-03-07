// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IMarket} from "src/interfaces/IMarket.sol";
import {Sweepable, SafeERC20, IERC20} from "src/util/Sweepable.sol";
import {IMultiMarketConvertHelper} from "src/interfaces/IMultiMarketConvertHelper.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IYearnVaultV2} from "src/interfaces/IYearnVaultV2.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
/**
 * @title CurveLP Helper for ALE and Market for sDOLA Curve pools using dynamic array when adding liquidity
 * @notice This contract is a generalized ALE helper contract for a curve pools with sDOLA. Also support YearnV2 vaults for this LP.
 * @dev This contract is used by the ALE to interact with sDOLA Curve pools or YearnV2 Curve vaults and market.
 * Can also be used by anyone to perform add/remove liquidity from and to DOLA and deposit/withdraw operations.
 **/

contract CurveSDolaLPHelperDynamic is Sweepable, IMultiMarketConvertHelper {
    using SafeERC20 for IERC20;

    error InsufficientLP();
    error InsufficientShares();
    error MarketNotSet(address market);

    struct Pool {
        ICurvePool pool;
        uint128 sDolaIndex;
        uint128 length;
        IYearnVaultV2 vault;
    }

    event MarketSet(
        address indexed market,
        uint128 sDolaIndex,
        address indexed pool,
        address indexed yearnVault
    );
    event MarketRemoved(address indexed market);

    IERC20 public immutable DOLA;
    IERC4626 public immutable sDOLA;
    /// @notice Mapping of market addresses to their associated Curve Pools.
    mapping(address => Pool) public markets;

    /** @dev Constructor
    @param _gov The address of Inverse Finance governance
    @param _guardian The address of the guardian
    @param _dola The address of DOLA
    @param _sDola The address of sDOLA 
    **/
    constructor(
        address _gov,
        address _guardian,
        address _dola,
        address _sDola
    ) Sweepable(_gov, _guardian) {
        DOLA = IERC20(_dola);
        sDOLA = IERC4626(_sDola);
    }

    /**
     * @notice Deposits DOLA into the Curve Pool and returns the received LP token.
     * @dev Used by the ALE but can be called by anyone.
     * @param amount The amount of DOLA to be deposited.
     * @param data The encoded address of the market.
     * @return collateralAmount The amount of LP token received.
     */
    function convertToCollateral(
        address,
        uint256 amount,
        bytes calldata data
    ) external override returns (uint256 collateralAmount) {
        collateralAmount = convertToCollateral(amount, msg.sender, data);
    }

    /**
     * @notice Deposits DOLA into the Curve Pool and returns the received LP token or Yearn token.
     * @dev Use custom recipient address.
     * @param amount The amount of DOLA to be deposited.
     * @param recipient The address on behalf of which the collateralAmount are deposited.
     * @param data The encoded address of the market.
     * @return collateralAmount The amount of LP or Yearn token received.
     */
    function convertToCollateral(
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
            IERC20(address(markets[market].pool)).approve(
                address(vault),
                lpAmount
            );
            return vault.deposit(lpAmount, recipient);
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
    function convertFromCollateral(
        address,
        uint256 amount,
        bytes calldata data
    ) external override returns (uint256 dolaAmount) {
        return convertFromCollateral(amount, msg.sender, data);
    }

    /**
     * @notice Redeems Collateral for DOLA.
     * @dev Use custom recipient address.
     * @param amount The amount of LP or Yearn Token to be redeemed.
     * @param recipient The address to which the underlying token is transferred.
     * @param data The encoded address of the market.
     * @return dolaAmount The amount of DOLA redeemed.
     */
    function convertFromCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) public override returns (uint256 dolaAmount) {
        (address market, uint256 minOut) = abi.decode(data, (address, uint256));
        _revertIfMarketNotSet(market);

        ICurvePool pool = markets[market].pool;
        IYearnVaultV2 vault = markets[market].vault;
        uint128 sDolaIndex = markets[market].sDolaIndex;

        uint256 lpAmount;
        // If vault is set, withdraw LP token from the Yearn Vault and then remove liquidity from the pool
        if (address(vault) != address(0)) {
            IERC20(address(vault)).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
            lpAmount = vault.withdraw(amount);
            _reimburseSharesLeft(vault, recipient);
        } else {
            // Just remove liquidity from the pool
            IERC20(address(pool)).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
            lpAmount = amount;
        }
        return _removeLiquidity(pool, lpAmount, sDolaIndex, minOut, recipient);
    }

    /**
     * @notice Convert DOLA into LP or Yearn token and deposit the received amount for recipient.
     * @param assets The amount of DOLA to be converted.
     * @param recipient The address on behalf of which the LP or Yearn are deposited.
     * @param data The encoded address of the market.
     * @return collateralAmount The amount of collateral deposited into the market.
     */
    function convertToCollateralAndDeposit(
        uint256 assets,
        address recipient,
        bytes calldata data
    ) external override returns (uint256) {
        (address market, ) = abi.decode(data, (address, uint256));
        _revertIfMarketNotSet(market);

        // Convert DOLA to LP or Yearn token
        uint256 amount = convertToCollateral(assets, address(this), data);

        IYearnVaultV2 vault = markets[market].vault;

        uint256 actualAmount;
        address collateral;

        // If Vault is set, deposit the Yearn token into the market
        if (address(vault) != address(0)) {
            collateral = address(vault);
            actualAmount = vault.balanceOf(address(this));
        } else {
            // Deposit the LP token into the market
            collateral = address(markets[market].pool);
            actualAmount = IERC20(collateral).balanceOf(address(this));
        }

        if (amount > actualAmount) revert InsufficientShares();

        IERC20(collateral).approve(market, actualAmount);
        IMarket(market).deposit(recipient, actualAmount);
        return actualAmount;
    }

    /**
     * @notice Withdraw the collateral from the market then convert to DOLA.
     * @param amount The amount of LP or Yearn token to be withdrawn from the market.
     * @param recipient The address to which DOLA is transferred.
     * @param permit The permit data for the Market.
     * @param data The encoded address of the market.
     * @return dolaAmount The amount of DOLA redeemed.
     */
    function withdrawAndConvertFromCollateral(
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
            amount = vault.withdraw(amount);
            _reimburseSharesLeft(vault, recipient);
        }
        // Just remove liquidity from the pool
        if (IERC20(address(pool)).balanceOf(address(this)) < amount)
            revert InsufficientLP();
        return
            _removeLiquidity(
                pool,
                amount,
                markets[market].sDolaIndex,
                minOut,
                recipient
            );
    }

    function _addLiquidity(
        address market,
        uint256 amount,
        uint256 minMint,
        address recipient
    ) internal returns (uint256 lpAmount) {
        DOLA.safeTransferFrom(msg.sender, address(this), amount);

        DOLA.approve(address(sDOLA), amount);
        uint256 sDolaAmount = sDOLA.deposit(amount, address(this));

        uint128 sDolaIndex = markets[market].sDolaIndex;
        ICurvePool pool = markets[market].pool;
        sDOLA.approve(address(pool), sDolaAmount);

        uint256[] memory amounts = new uint256[](markets[market].length);
        amounts[sDolaIndex] = sDolaAmount;
        return pool.add_liquidity(amounts, minMint, recipient);
    }

    function _removeLiquidity(
        ICurvePool pool,
        uint256 amount,
        uint128 sDolaIndex,
        uint256 minOut,
        address recipient
    ) internal returns (uint256 dolaAmount) {
        uint256 sDolaAmount = pool.remove_liquidity_one_coin(
            amount,
            int128(sDolaIndex),
            minOut,
            address(this)
        );
        return sDOLA.redeem(sDolaAmount, recipient, address(this));
    }

    function _reimburseSharesLeft(
        IYearnVaultV2 vault,
        address recipient
    ) internal {
        uint256 sharesLeft = vault.balanceOf(address(this));
        if (sharesLeft > 0)
            IERC20(address(vault)).safeTransfer(recipient, sharesLeft);
    }

    function _revertIfMarketNotSet(address market) internal view {
        if (address(markets[market].pool) == address(0))
            revert MarketNotSet(market);
    }

    /**
     * @notice Set the market address and its associated Curve Pool and sDola Index.
     * @dev Only callable by the governance.
     * @param marketAddress The address of the market.
     * @param sDolaIndex sDola index in the coins array for Curve Pools.
     * @param poolAddress The address of the curve pool with sDOLA.
     */
    function setMarket(
        address marketAddress,
        address poolAddress,
        uint128 sDolaIndex,
        uint128 length,
        address vaultAddress
    ) external onlyGov {
        markets[marketAddress] = Pool({
            pool: ICurvePool(poolAddress),
            sDolaIndex: sDolaIndex,
            length: length,
            vault: IYearnVaultV2(vaultAddress)
        });
        emit MarketSet(marketAddress, sDolaIndex, poolAddress, vaultAddress);
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
