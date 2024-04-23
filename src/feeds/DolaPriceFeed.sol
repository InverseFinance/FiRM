// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

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

contract DolaPriceFeed {
    error OnlyGov();

    ICurvePool public constant pyUSDFrax =
        ICurvePool(0xA5588F7cdf560811710A2D82D3C9c99769DB1Dcb);

    ICurvePool public constant crvDOLA =
        ICurvePool(0xef484de8C07B6e2d732A92B5F78e81B38f99f95E);

    IChainlinkFeed public constant pyUsdToUsd =
        IChainlinkFeed(0x8f1dF6D7F2db73eECE86a18b4381F4707b918FB1);

    IChainlinkFeed public constant fraxToUsd =
        IChainlinkFeed(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);

    uint256 public fraxHeartbeat = 1 hours;

    uint256 public pyUSDHeartbeat = 24 hours;

    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    modifier onlyGov() {
        if (msg.sender != gov) revert OnlyGov();
        _;
    }

    /**
     * @return roundId The round ID of the Chainlink price feed
     * @return dolaUsdprice The latest price for DOLA
     * @return startedAt The timestamp when the latest round of Chainlink price feed started
     * @return updatedAt The timestamp when the latest round of Chainlink price feed was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (
            uint80 roundId,
            int256 pyUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = pyUsdToUsd.latestRoundData();

        if (
            isPriceOutOfBounds(pyUsdPrice, pyUsdToUsd) ||
            block.timestamp - updatedAt > pyUSDHeartbeat
        ) {
            updatedAt = 0;
        }

        (
            uint80 roundIdFrax,
            int256 fraxUsdPrice,
            uint startedAtFrax,
            uint updatedAtFrax,
            uint80 answeredInRoundFrax
        ) = fraxToUsd.latestRoundData();

        if (
            isPriceOutOfBounds(fraxUsdPrice, fraxToUsd) ||
            block.timestamp - updatedAtFrax > fraxHeartbeat
        ) {
            updatedAtFrax = 0;
        }

        int256 minUsdPrice;

        // If FRAX price is lower or equal than pyUSD price, use FRAX price
        if (fraxUsdPrice <= pyUsdPrice || pyUsdPrice == 0) {
            minUsdPrice = fraxUsdPrice;
            roundId = roundIdFrax;
            startedAt = startedAtFrax;
            updatedAt = updatedAtFrax;
            answeredInRound = answeredInRoundFrax;
        } else {
            minUsdPrice = pyUsdPrice;
        }

        return (
            roundId,
            int(
                (pyUSDFrax.get_virtual_price() *
                    uint256(minUsdPrice) *
                    10 ** 18) / crvDOLA.price_oracle(0)
            ) / 10 ** 8,
            startedAt,
            updatedAt == 0 ? updatedAt : block.timestamp,
            answeredInRound
        );
    }

    /** 
    @notice Retrieves the latest price for DOLA
    @return price The latest price for DOLA
    */
    function latestAnswer() external view returns (int256) {
        (, int256 price, , , ) = latestRoundData();
        return price;
    }

    /**
     * @notice Retrieves number of decimals for the DOLA price feed
     * @return decimals The number of decimals for the DOLA price feed
     */
    function decimals() public pure returns (uint8) {
        return 18;
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

    /**
     * @notice Sets a new pyUSD heartbeat
     * @dev Can only be called by the current gov address
     * @param newHeartbeat The new pyUSD heartbeat
     */
    function setPyUSDHeartbeat(uint256 newHeartbeat) external onlyGov {
        pyUSDHeartbeat = newHeartbeat;
    }

    /**
     * @notice Sets a new FRAX heartbeat
     * @dev Can only be called by the current gov address
     * @param newHeartbeat The new FRAX heartbeat
     */
    function setFraxHeartbeat(uint256 newHeartbeat) external onlyGov {
        fraxHeartbeat = newHeartbeat;
    }

    /**
     * @notice Sets a new gov address
     * @dev Can only be called by the current gov address
     * @param newGov The new gov address
     */
    function setGov(address newGov) external onlyGov {
        gov = newGov;
    }
}
