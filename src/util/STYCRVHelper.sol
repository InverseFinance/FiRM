//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "src/interfaces/IMarket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IDola.sol";
import "src/interfaces/ITransformHelper.sol";
import "src/interfaces/ISTYCRV.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

// st-yCRV helper
contract STYCRVHelper is Ownable, ReentrancyGuard {
    error DepositLimitExceeded();
    error NotEnoughShares();
    error DepositFailed(uint256 expected, uint256 received);
    error WithdrawFailed(uint256 expected, uint256 received);

    uint256 public constant scale = 1e18;
    ISTYCRV public constant vault =
        ISTYCRV(0x27B5739e22ad9033bcBf192059122d163b60349D); // st-yCRV
    uint256 public maxLoss = 1; // 0.01% [BPS]
    IERC20 public constant underlying =
        IERC20(0xFCc5c47bE19d06BF83eB04298b026F81069ff65b); // yCRV

    IMarket public constant market =
        IMarket(0x27b6c301Fd441f3345d61B7a4245E1F823c3F9c4); // DOLA market

    struct Permit {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    constructor() Ownable(msg.sender) {
        underlying.approve(address(vault), type(uint256).max);
        IERC20(address(vault)).approve(address(market), type(uint256).max);
    }

    function setMaxLoss(uint256 _maxLoss) external onlyOwner {
        maxLoss = _maxLoss;
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

        uint256 estimateAmount = assetToCollateral(_value);

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

        uint256 estimateAmount = collateralToAsset(_value);

        underlyingAmount = vault.withdraw(_value, msg.sender, maxLoss);

        if (underlyingAmount < estimateAmount)
            revert WithdrawFailed(estimateAmount, underlyingAmount);
    }

    /// @notice View function to calculate collateral amount from asset amount
    /// @param assetAmount Amount of asset to transform
    /// @return collateralAmount Amount of collateral received
    function assetToCollateral(
        uint assetAmount
    ) public view returns (uint collateralAmount) {
        uint totalSupply = vault.totalSupply();
        if (totalSupply > 0)
            return (assetAmount * totalSupply) / getFreeFunds();
        return assetAmount;
    }

    /// @notice View function to calculate asset amount from collateral amount
    /// @param collateralAmount Amount of collateral to transform
    /// @return assetAmount Amount of asset received
    function collateralToAsset(
        uint collateralAmount
    ) public view returns (uint assetAmount) {
        return (collateralAmount * vault.pricePerShare()) / scale;
    }

    /// @notice View function for the exchange rate between asset and collateral
    /// @return ratio Amount of asset per share of collateral
    function assetToCollateralRatio() external view returns (uint ratio) {
        return vault.pricePerShare();
    }

    /// @notice Transforms underlying to collateral and deposits it into the market
    /// @param amount Amount of underlying to transform
    /// @param data Optional helper data in case the collateral needs to be transformed
    function transformToCollateralAndDeposit(
        uint amount,
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
        uint amount,
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

    function getFreeFunds() public view returns (uint256) {
        return vault.totalAssets() - calculateLockedProfit();
    }

    function calculateLockedProfit() public view returns (uint256) {
        uint256 lockedFundsRatio = (block.timestamp - vault.lastReport()) *
            vault.lockedProfitDegradation();

        if (lockedFundsRatio < 10 ** 18) {
            uint256 lockedProfit = vault.lockedProfit();

            return
                lockedProfit - ((lockedFundsRatio * lockedProfit) / 10 ** 18);
        } else return 0;
    }
}
