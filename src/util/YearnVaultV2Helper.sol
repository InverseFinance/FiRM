//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "src/interfaces/IMarket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IYearnVaultV2.sol";

library YearnVaultV2Helper {
    uint256 public constant scale = 1e18;

    /// @notice View function to calculate collateral amount from asset amount
    /// @param assetAmount Amount of asset to transform
    /// @return collateralAmount Amount of collateral received
    function assetToCollateral(
        IYearnVaultV2 vault,
        uint assetAmount
    ) public view returns (uint collateralAmount) {
        uint totalSupply = vault.totalSupply();
        if (totalSupply > 0)
            return (assetAmount * totalSupply) / getFreeFunds(vault);
        return assetAmount;
    }

    /// @notice View function to calculate asset amount from collateral amount
    /// @param collateralAmount Amount of collateral to transform
    /// @return assetAmount Amount of asset received
    function collateralToAsset(
        IYearnVaultV2 vault,
        uint collateralAmount
    ) public view returns (uint assetAmount) {
        uint totalSupply = vault.totalSupply();
        if (totalSupply > 0)
            return (collateralAmount * getFreeFunds(vault)) / totalSupply;
        return collateralAmount;
    }

    /// @notice View function for the exchange rate between asset and collateral
    /// @return ratio Amount of asset per share of collateral
    function assetToCollateralRatio(
        IYearnVaultV2 vault
    ) external view returns (uint ratio) {
        return vault.pricePerShare();
    }

    function getFreeFunds(IYearnVaultV2 vault) public view returns (uint256) {
        return vault.totalAssets() - calculateLockedProfit(vault);
    }

    function calculateLockedProfit(
        IYearnVaultV2 vault
    ) public view returns (uint256) {
        uint256 lockedFundsRatio = (block.timestamp - vault.lastReport()) *
            vault.lockedProfitDegradation();

        if (lockedFundsRatio < 10 ** 18) {
            uint256 lockedProfit = vault.lockedProfit();

            return
                lockedProfit - ((lockedFundsRatio * lockedProfit) / 10 ** 18);
        } else return 0;
    }
}
