//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

interface ISTYCRV {
    function deposit(uint256 amount, address recipient) external returns (uint256);

    // maxLoss: uint256 = 1,  # 0.01% [BPS]
    function withdraw(uint256 amount, address recipient, uint256 maxLoss) external returns (uint256);

    function pricePerShare() external view returns(uint256); 

    function maxAvailableShares() external view returns(uint256);
}
