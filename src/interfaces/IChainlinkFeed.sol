pragma solidity ^0.8.13;

interface IChainlinkFeed {
    function aggregator() external view returns (address aggregator);

    function decimals() external view returns (uint8 decimals);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 crvUsdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestAnswer() external view returns (int256 price);

    function description() external view returns (string memory description);
}

interface IChainlinkBasePriceFeed is IChainlinkFeed {
    function assetToUsd() external view returns (IChainlinkFeed);

    function assetToUsdFallback() external view returns (IChainlinkFeed);

    function assetToUsdHeartbeat() external view returns (uint256 heartbeat);
}
