pragma solidity ^0.8.13;

interface IYearnVaultV2 {
    function deposit(
        uint256 amount,
        address recipient
    ) external returns (uint256);

    function withdraw(
        uint256 shares,
        address recipient
    ) external returns (uint256);

    function withdraw(
        uint256 shares,
        address recipient,
        uint256 maxLoss
    ) external returns (uint256);

    function withdraw(uint256 amount) external returns (uint256);

    function totalSupply() external view returns (uint256);

    function pricePerShare() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function lastReport() external view returns (uint256);

    function lockedProfitDegradation() external view returns (uint256);

    function lockedProfit() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function availableDepositLimit() external view returns (uint256);

    function maxAvailableShares() external view returns (uint256);

    function symbol() external view returns (string memory);
}
