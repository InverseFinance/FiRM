pragma solidity ^0.8.13;

interface ICurvePool {
    function price_oracle(uint256 k) external view returns (uint256);

    function get_virtual_price() external view returns (uint256);

    function ema_price() external view returns (uint256);
}
