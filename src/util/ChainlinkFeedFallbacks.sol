//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

interface IChainlinkFeed {
    function aggregator() external view returns (address aggregator);

    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 lpDollarPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface IAggregator {
    function maxAnswer() external view returns (int192);

    function minAnswer() external view returns (int192);
}

interface ICurvePool {
    function price_oracle(uint256 k) external view returns (uint256);

    function get_virtual_price() external view returns (uint256);

    function ema_price() external view returns (uint256);
}

library ChainlinkFeedFallbacks {
    int256 public constant scale = 1e18;

    function fallBackUsdEma(
        IChainlinkFeed assetToUsdFallback,
        uint256 assetFallHb,
        ICurvePool curvePool
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        uint256 assetToTargetPrice = curvePool.ema_price();

        (
            uint80 roundId,
            int256 assetToUsdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = assetToUsdFallback.latestRoundData();

        if (
            isPriceOutOfBounds(assetToUsdPrice, assetToUsdFallback) ||
            block.timestamp - updatedAt > assetFallHb
        ) {
            // will cause stale price on borrow controller
            updatedAt = 0;
        }

        return (
            roundId,
            (assetToUsdPrice * scale) / int(assetToTargetPrice),
            startedAt,
            updatedAt,
            answeredInRound
        );
    }

    // Fallback when curve pool returns targetToAsset and chainlink returns assetToUsd
    function fallbackUsdPriceOracle(
        IChainlinkFeed assetToUsdFallback,
        uint256 assetFallHb,
        ICurvePool curvePool,
        uint256 targetK
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        // int targetToAsset = int(curvePool.price_oracle(targetK));

        (
            uint80 roundId,
            int256 assetToUsd,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = assetToUsdFallback.latestRoundData();

        //  int targetToUsdPrice = (targetToAsset * assetToUsd) / 10 ** 18;

        if (
            isPriceOutOfBounds(assetToUsd, assetToUsdFallback) ||
            block.timestamp - updatedAt > assetFallHb
        ) {
            // will cause stale price on borrow controller
            updatedAt = 0;
        }

        return (
            roundId,
            (int(curvePool.price_oracle(targetK)) * assetToUsd) / scale,
            startedAt,
            updatedAt,
            answeredInRound
        );
    }

    // Fallback when curve pool returns assetToTarget (when need the stable one in curve pool as target like for USDC or crvUSD fallback) and chainlink returns assetToUsd
    function fallbackUsdPriceOracleStable(
        IChainlinkFeed assetToUsdFallback,
        uint256 assetFallHb,
        ICurvePool curvePool,
        uint256 assetK
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        // int assetToTarget = int(curvePool.price_oracle(assetK));

        (
            uint80 roundId,
            int256 assetToUsd,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = assetToUsdFallback.latestRoundData();

        //  int targetToUsdPrice = assetToUsd * 10 ** 18 / targetToAsset;

        if (
            isPriceOutOfBounds(assetToUsd, assetToUsdFallback) ||
            block.timestamp - updatedAt > assetFallHb
        ) {
            // will cause stale price on borrow controller
            updatedAt = 0;
        }

        return (
            roundId,
            (assetToUsd * scale) / int(curvePool.price_oracle(assetK)),
            startedAt,
            updatedAt,
            answeredInRound
        );
    }

    /**
     * @notice Checks if a given price is out of the boundaries defined in the Chainlink aggregator.
     * @param price The price to be checked.
     * @param feed The Chainlink feed to retrieve the boundary information from.
     * @return bool Returns `true` if the price is out of bounds, otherwise `false`.
     */
    function isPriceOutOfBounds(
        int price,
        IChainlinkFeed feed
    ) public view returns (bool) {
        IAggregator aggregator = IAggregator(feed.aggregator());
        int192 max = aggregator.maxAnswer();
        int192 min = aggregator.minAnswer();
        return (max <= price || min >= price);
    }
}
