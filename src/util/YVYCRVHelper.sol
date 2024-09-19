//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "src/interfaces/IMarket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IDola.sol";
import "src/interfaces/ITransformHelper.sol";
import {Sweepable} from "src/util/Sweepable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";

// yvyCRV helper for ALE and market
contract YVYCRVHelper is Sweepable, ReentrancyGuard {
    error DepositLimitExceeded();
    error NotEnoughShares();
    error DepositFailed(uint256 expected, uint256 received);
    error WithdrawFailed(uint256 expected, uint256 received);
    error HelperPaused();

    IYearnVaultV2 public constant vault =
        IYearnVaultV2(0x27B5739e22ad9033bcBf192059122d163b60349D); // yvyCRV
    IERC20 public constant underlying =
        IERC20(0xFCc5c47bE19d06BF83eB04298b026F81069ff65b); // yCRV
    IMarket public constant market =
        IMarket(0x27b6c301Fd441f3345d61B7a4245E1F823c3F9c4); // FiRM yvyCRV market
    uint256 public maxLoss = 1; // 0.01% [BPS]

    struct Permit {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    constructor(address _gov, address _guardian) Sweepable(_gov, _guardian) {
        underlying.approve(address(vault), type(uint256).max);
        IERC20(address(vault)).approve(address(market), type(uint256).max);
    }

    /// @notice Transforms underlying to collateral
    /// @param _value Amount of underlying to transform
    /// @param _helperData Optional helper data in case the collateral needs to be transformed
    /// @return collateralAmount Amount of collateral received
    function transformToCollateral(
        uint256 _value,
        bytes calldata _helperData
    ) external nonReentrant returns (uint256 collateralAmount) {
        if (_value > vault.availableDepositLimit())
            revert DepositLimitExceeded();

        underlying.transferFrom(msg.sender, address(this), _value);

        uint256 estimateAmount = YearnVaultV2Helper.assetToCollateral(
            vault,
            _value
        );

        // Transform underlying to collateral
        collateralAmount = vault.deposit(_value, msg.sender);

        if (collateralAmount < estimateAmount)
            revert DepositFailed(estimateAmount, collateralAmount);
    }

    /// @notice Transforms collateral to underlying
    /// @param _value Amount of collateral to transform
    /// @param _helperData Optional helper data in case the collateral needs to be transformed
    /// @return underlyingAmount Amount of underlying received
    function transformFromCollateral(
        uint256 _value,
        bytes calldata _helperData
    ) external nonReentrant returns (uint256 underlyingAmount) {
        if (_value > vault.maxAvailableShares()) revert NotEnoughShares();

        IERC20(address(vault)).transferFrom(msg.sender, address(this), _value);

        uint256 estimateAmount = YearnVaultV2Helper.collateralToAsset(
            vault,
            _value
        );

        underlyingAmount = vault.withdraw(_value, msg.sender, maxLoss);

        if (underlyingAmount < estimateAmount)
            revert WithdrawFailed(estimateAmount, underlyingAmount);
    }

    /// @notice Transforms underlying to collateral and deposits it into the market
    /// @param amount Amount of underlying to transform
    /// @param data Optional helper data in case the collateral needs to be transformed
    function transformToCollateralAndDeposit(
        uint256 amount,
        bytes calldata data
    ) external returns (uint256 collateralAmount) {
        underlying.transferFrom(msg.sender, address(this), amount);

        collateralAmount = vault.deposit(amount, address(this));

        market.deposit(msg.sender, collateralAmount);
    }

    /// @notice Withdraws collateral from the market and transforms it to underlying
    /// @param amount Amount of collateral to transform
    /// @param data Optional helper data in case the collateral needs to be transformed
    function withdrawAndTransformFromCollateral(
        uint256 amount,
        Permit calldata permit,
        bytes calldata data
    ) external returns (uint256 underlyingAmount) {
        if (amount > vault.maxAvailableShares()) revert NotEnoughShares();

        market.withdrawOnBehalf(
            msg.sender,
            amount,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );

        uint256 shares = IERC20(address(vault)).balanceOf(address(this));
        return vault.withdraw(shares, msg.sender, maxLoss);
    }

    // Admin functions
    /// @notice Set the max loss for withdraw
    /// @dev Only gov can call this function
    /// @param _maxLoss Max loss in BPS
    function setMaxLoss(uint256 _maxLoss) external onlyGov {
        maxLoss = _maxLoss;
    }
}
