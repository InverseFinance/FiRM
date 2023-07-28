//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "src/interfaces/IMarket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IDola.sol";
import "src/interfaces/ITransformHelper.sol";
import "src/interfaces/ISTYCRV.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

// st-yCRV helper
contract STYCRVHelper is Ownable, ReentrancyGuard {
    error NotEnoughShares();

    uint256 public constant scale = 1e18;
    ISTYCRV public constant vault =
        ISTYCRV(0x27B5739e22ad9033bcBf192059122d163b60349D); // st-yCRV
    uint256 public maxLoss = 1; // 0.01% [BPS]
    IERC20 public constant underlying =
        IERC20(0xFCc5c47bE19d06BF83eB04298b026F81069ff65b); // yCRV

    constructor() Ownable(msg.sender) {
        underlying.approve(address(vault), type(uint256).max);
    }

    function setMaxLoss(uint256 _maxLoss) external onlyOwner {
        maxLoss = _maxLoss;
    }

    // TODO: add transformToCollateralAndDeposit
    // TODO: add withdrawAndTransformFromCollateral

    /// @notice Transforms underlying to collateral
    /// @param _value Amount of underlying to transform
    /// @param _helperData Optional helper data in case the collateral needs to be transformed
    /// @return collateralAmount Amount of collateral received
    function transformToCollateral(
        uint256 _value,
        bytes calldata _helperData
    ) external nonReentrant returns (uint256 collateralAmount) {
        underlying.transferFrom(msg.sender, address(this), _value);
        // Transform underlying to collateral
        return vault.deposit(_value, msg.sender);
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

        return vault.withdraw(_value, msg.sender, maxLoss);
    }

    /// @notice View function to calculate collateral amount from asset amount
    /// @param assetAmount Amount of asset to transform
    /// @return collateralAmount Amount of collateral received
    function assetToCollateral(
        uint assetAmount
    ) external view returns (uint collateralAmount) {
        return (assetAmount * scale) / vault.pricePerShare();
    }

    /// @notice View function to calculate asset amount from collateral amount
    /// @param collateralAmount Amount of collateral to transform
    /// @return assetAmount Amount of asset received
    function collateralToAsset(
        uint collateralAmount
    ) external view returns (uint assetAmount) {
        return (collateralAmount * vault.pricePerShare()) / scale;
    }

    /// @notice View function for the exchange rate between asset and collateral
    /// @return ratio Amount of asset per share of collateral
    function assetToCollateralRatio() external view returns (uint ratio) {
        return vault.pricePerShare();
    }

    // function transformToCollateralAndDeposit(
    //     uint amount,
    //     address user,
    //     bytes calldata data
    // ) public;

    // function withdrawAndTransformFromCollateral(
    //     uint amount,
    //     address user,
    //     bytes calldata data,
    //     uint v,
    //     uint r,
    //     uint8 s
    // ) public;
}
