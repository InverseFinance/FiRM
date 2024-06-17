pragma solidity ^0.8.20;

import "src/util/FeedLib.sol";

// Combined Chainlink EMA Price Feed, allows for additional fallback to be set

contract ChainlinkEmaPriceFeed {
    IChainlinkFeed public immutable assetToUsd;
    IChainlinkFeed public assetToUsdFallback;
    ICurvePool public immutable curvePool;
    address public owner;
    address public pendingOwner;
    uint256 public assetToUsdHeartbeat;

    uint8 public decimals;

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
        uint256 _assetToUsdHeartbeat,
        address _curvePool,
        uint8 _decimals
    ) {
        owner = _owner;
        assetToUsd = IChainlinkFeed(_assetToUsd);
        assetToUsdFallback = IChainlinkFeed(_assetToUsdFallback);
        curvePool = ICurvePool(_curvePool);
        assetToUsdHeartbeat = _assetToUsdHeartbeat;
        decimals = _decimals;
    }

    /**
     * @notice Retrieves the latest round data for the asset token price feed
     * @return roundId The round ID of the Chainlink price feed for the feed with the lowest updatedAt feed
     * @return usdPrice The latest asset price in USD
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
        if (isPriceStale()) {
            if (hasFallback()) {
                (
                    roundId,
                    usdPrice,
                    startedAt,
                    updatedAt,
                    answeredInRound
                ) = assetToUsdFallback.latestRoundData();
                uint8 fallbackDecimals = assetToUsdFallback.decimals();
                if (fallbackDecimals > decimals) {
                    usdPrice =
                        usdPrice /
                        int(10 ** (fallbackDecimals - decimals));
                } else if (fallbackDecimals < decimals) {
                    usdPrice =
                        usdPrice *
                        int(10 ** (decimals - fallbackDecimals));
                }
            } else {
                (
                    roundId,
                    usdPrice,
                    startedAt,
                    updatedAt,
                    answeredInRound
                ) = FeedLib.usdEma(assetToUsd, assetToUsdHeartbeat, curvePool);
                updatedAt = 0;
            }
        } else {
            (roundId, usdPrice, startedAt, updatedAt, answeredInRound) = FeedLib
                .usdEma(assetToUsd, assetToUsdHeartbeat, curvePool);
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

    function isPriceStale() public view returns (bool) {
        (, int price, , uint256 updatedAt, ) = assetToUsd.latestRoundData();
        bool stalePrice = updatedAt + assetToUsdHeartbeat < block.timestamp;
        return stalePrice || isPriceOutOfBounds(price, assetToUsd);
    }

    function hasFallback() public view returns (bool) {
        return address(assetToUsdFallback) != address(0);
    }

    function setFallback(IChainlinkFeed newFallback) public onlyOwner {
        assetToUsdFallback = newFallback;
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
}
