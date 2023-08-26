// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IChainlinkFeed {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 invDollarPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface ICurvePool {
    function price_oracle(uint k) external view returns (uint256);
}

contract InvFeedV3 is IChainlinkFeed {
    ICurvePool public constant tricrypto =
        ICurvePool(0x5426178799ee0a0181A89b4f57eFddfAb49941Ec);

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        int256 invDollarPrice = int256(tricrypto.price_oracle(1));
        return (0, invDollarPrice, 0, 0, 0);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
