// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IMarket} from "src/interfaces/IMarket.sol";
import {Sweepable, SafeERC20, IERC20} from "src/util/Sweepable.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ICurvePool} from "src/interfaces/ICurvePool.sol";

/**
 * @title CurveLP Helper for ALE and Market
 * @notice This contract is a generalized ALE helper contract for a curve pool with 2 coins with DOLA.
 * @dev This contract is used by the ALE to interact with the curve pool and market.
 * Can also be used by anyone to perform add/remove liquidity from and to DOLA and deposit/withdraw operations.
 **/

contract CurveDolaLPHelper is Sweepable, IMultiMarketTransformHelper {
    using SafeERC20 for IERC20;

    error InsufficientLP();
    error MarketNotSet(address market);
    error NotImplemented();

    uint256 public constant POOL_LENGTH_2 = 2;
    uint256 public constant POOL_LENGTH_3 = 3;

    struct Pool {
        ICurvePool pool;
        uint128 dolaIndex;
        uint128 length;
    }

    event MarketSet(
        address indexed market,
        uint128 dolaIndex,
        address indexed pool
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
     * @return lpAmount The amount of LP token received.
     */
    function transformToCollateral(
        uint256 amount,
        bytes calldata data
    ) external override returns (uint256 lpAmount) {
        lpAmount = transformToCollateral(amount, msg.sender, data);
    }

    /**
     * @notice Deposits DOLA into the Curve Pool and returns the received LP token.
     * @dev Use custom recipient address.
     * @param amount The amount of DOLA to be deposited.
     * @param recipient The address on behalf of which the lpAmount are deposited.
     * @param data The encoded address of the market.
     * @return lpAmount The amount of LP token received.
     */
    function transformToCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) public override returns (uint256 lpAmount) {
        (address market, uint256 minMint) = abi.decode(
            data,
            (address, uint256)
        );
        _revertIfMarketNotSet(market);

        uint128 dolaIndex = markets[market].dolaIndex;
        ICurvePool pool = markets[market].pool;

        DOLA.safeTransferFrom(msg.sender, address(this), amount);
        DOLA.approve(address(pool), amount);

        if (markets[market].length == POOL_LENGTH_3) {
            uint256[POOL_LENGTH_3] memory amounts;
            amounts[dolaIndex] = amount;
            return pool.add_liquidity(amounts, minMint, recipient);
        } else if (markets[market].length == POOL_LENGTH_2) {
            uint256[POOL_LENGTH_2] memory amounts;
            amounts[dolaIndex] = amount;
            return pool.add_liquidity(amounts, minMint, recipient);
        } else revert NotImplemented();
    }

    /**
     * @notice Redeems the ERC4626 token for the associated underlying token.
     * @dev Used by the ALE but can be called by anyone.
     * @param amount The amount of ERC4626 token to be redeemed.
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
     * @notice Redeems the ERC4626 token for the associated underlying token.
     * @dev Use custom recipient address.
     * Helper function following the inherited interface but in this case is better to redeem directly on the pool to save gas.
     * @param amount The amount of ERC4626 token to be redeemed.
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

        IERC20(address(pool)).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
        dolaAmount = pool.remove_liquidity_one_coin(
            amount,
            int128(markets[market].dolaIndex),
            minOut,
            recipient
        );
    }

    /**
     * @notice Deposit DOLA into the Curve Pool and deposit the received lpAmount for recipient.
     * @param assets The amount of underlying token to be transferred.
     * @param recipient The address on behalf of which the lpAmount are deposited.
     * @param data The encoded address of the market.
     * @return lpAmount The amount of LP token deposited into the market.
     */
    function transformToCollateralAndDeposit(
        uint256 assets,
        address recipient,
        bytes calldata data
    ) external override returns (uint256 lpAmount) {
        (address market, ) = abi.decode(data, (address, uint256));
        _revertIfMarketNotSet(market);

        ICurvePool pool = markets[market].pool;

        lpAmount = transformToCollateral(assets, address(this), data);

        uint256 actualLP = IERC20(address(pool)).balanceOf(address(this));
        if (lpAmount > actualLP) revert InsufficientLP();

        IERC20(address(pool)).approve(market, actualLP);
        IMarket(market).deposit(recipient, actualLP);
    }

    /**
     * @notice Withdraw the shares from the market then withdraw DOLA from the Curve Pool.
     * @param amount The amount of LP token to be withdrawn from the market.
     * @param recipient The address to which DOLA is transferred.
     * @param permit The permit data for the Market.
     * @param data The encoded address of the market.
     * @return dolaAmount The amount of underlying token withdrawn from the Curve Pool
     */
    function withdrawAndTransformFromCollateral(
        uint256 amount,
        address recipient,
        Permit calldata permit,
        bytes calldata data
    ) external override returns (uint256 dolaAmount) {
        (address market, uint256 minOut) = abi.decode(data, (address, uint256));
        _revertIfMarketNotSet(market);

        ICurvePool pool = markets[market].pool;

        IMarket(market).withdrawOnBehalf(
            msg.sender,
            amount,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );
        uint256 actualLP = IERC20(address(pool)).balanceOf(address(this));
        if (actualLP < amount) revert InsufficientLP();

        dolaAmount = pool.remove_liquidity_one_coin(
            amount,
            int128(markets[market].dolaIndex),
            minOut,
            recipient
        );
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
        uint128 length
    ) external onlyGov {
        markets[marketAddress] = Pool({
            pool: ICurvePool(poolAddress),
            dolaIndex: dolaIndex,
            length: length
        });
        emit MarketSet(marketAddress, dolaIndex, poolAddress);
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
