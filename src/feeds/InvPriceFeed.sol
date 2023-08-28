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
    function price_oracle(uint256 k) external view returns (uint256);
}

contract InvPriceFeed is IChainlinkFeed {
    ICurvePool public constant tricrypto =
        ICurvePool(0x5426178799ee0a0181A89b4f57eFddfAb49941Ec);

    IChainlinkFeed public constant usdcToUsd =
        IChainlinkFeed(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    uint256 public constant invK = 1;

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (
            uint80 roundId,
            int256 usdcUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = usdcToUsd.latestRoundData();

        int256 invDollarPrice = int256(tricrypto.price_oracle(invK));
        
        invDollarPrice =
            (invDollarPrice * usdcUsdPrice * int(10 ** 10)) /
            int(10 ** decimals());
            
        return (roundId, invDollarPrice, startedAt, updatedAt, answeredInRound);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
