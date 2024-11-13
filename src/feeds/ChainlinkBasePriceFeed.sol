// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/interfaces/IChainlinkFeed.sol";

interface IAggregator {
    function maxAnswer() external view returns (int192);

    function minAnswer() external view returns (int192);
}

// Standard feed component for FiRM price feeds
/// @dev Always return the feed price in 18 decimals
contract ChainlinkBasePriceFeed {
    IChainlinkFeed public immutable assetToUsd;
    IChainlinkFeed public immutable assetToUsdFallback;
    uint8 public immutable assetToUsdDecimals;
    uint8 public immutable assetToUsdFallbackDecimals;
    string public description;

    address public owner;
    address public pendingOwner;

    uint256 public assetToUsdHeartbeat;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner, "Only pending owner");
        _;
    }

    constructor(
        address _owner,
        address _assetToUsd,
        address _assetToUsdFallback,
        uint256 _assetToUsdHeartbeat
    ) {
        owner = _owner;
        assetToUsd = IChainlinkFeed(_assetToUsd);
        assetToUsdFallback = IChainlinkFeed(_assetToUsdFallback);
        assetToUsdHeartbeat = _assetToUsdHeartbeat;
        assetToUsdDecimals = IChainlinkFeed(_assetToUsd).decimals();
        uint8 fallbackDecimals = 0;
        if (address(assetToUsdFallback) != address(0)) {
            fallbackDecimals = assetToUsdFallback.decimals();
        }
        assetToUsdFallbackDecimals = fallbackDecimals;
        description = assetToUsd.description();
    }

    /**
     * @notice Retrieves the latest round data for the asset token price feed
     * @return roundId The round ID of the Chainlink price feed for the feed with the lowest updatedAt feed
     * @return usdPrice The latest asset price in USD with 18 decimals
     * @return startedAt The timestamp when the latest round of Chainlink price feed started of the lowest last updatedAt feed
     * @return updatedAt The lowest timestamp when either of the latest round of Chainlink price feed was updated
     * @return answeredInRound The round ID in which the answer was computed of the lowest updatedAt feed
     */
    function latestRoundData()
        public
        view
        returns (
            uint80 roundId,
            int256 usdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (roundId, usdPrice, startedAt, updatedAt, answeredInRound) = assetToUsd
            .latestRoundData();

        if (isPriceStale(usdPrice, updatedAt)) {
            if (hasFallback()) {
                (
                    roundId,
                    usdPrice,
                    startedAt,
                    updatedAt,
                    answeredInRound
                ) = assetToUsdFallback.latestRoundData();
                usdPrice = normalizePrice(usdPrice, assetToUsdFallbackDecimals);
            } else {
                usdPrice = normalizePrice(usdPrice, assetToUsdDecimals);
                updatedAt = 0;
            }
        } else {
            usdPrice = normalizePrice(usdPrice, assetToUsdDecimals);
        }
    }

    /**
     * @notice Returns the latest price only
     * @dev Unlike chainlink oracles, the latestAnswer will always be the same as in the latestRoundData
     * @return int256 Returns the last finalized price of the chainlink oracle
     */
    function latestAnswer() external view returns (int256) {
        (, int256 latestPrice, , , ) = latestRoundData();
        return latestPrice;
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

    function isPriceStale(
        int256 price,
        uint256 updatedAt
    ) public view returns (bool) {
        bool stalePrice = updatedAt + assetToUsdHeartbeat < block.timestamp;
        return stalePrice || isPriceOutOfBounds(price, assetToUsd);
    }

    function hasFallback() public view returns (bool) {
        return address(assetToUsdFallback) != address(0);
    }

    function setHeartbeat(uint256 newHeartbeat) public onlyOwner {
        assetToUsdHeartbeat = newHeartbeat;
    }

    function setPendingOwner(address newPendingOwner) public onlyOwner {
        pendingOwner = newPendingOwner;
    }

    function acceptOwner() public onlyPendingOwner {
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    function normalizePrice(
        int256 price,
        uint8 feedDecimals
    ) public pure returns (int256) {
        if (feedDecimals > 18) {
            return price / int(10 ** (feedDecimals - 18));
        } else if (feedDecimals < 18) {
            return price * int(10 ** (18 - feedDecimals));
        }
        return price;
    }
}
