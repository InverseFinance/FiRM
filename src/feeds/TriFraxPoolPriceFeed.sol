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

contract TriFraxPoolPriceFeed {
    error OnlyGov();

    ICurvePool public constant tricryptoETH =
        ICurvePool(0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B);

    ICurvePool public constant tricryptoFRAX =
        ICurvePool(0xE57180685E3348589E9521aa53Af0BCD497E884d);

    ICurvePool public constant crvUSDFrax =
        ICurvePool(0x0CD6f267b2086bea681E922E19D40512511BE538);

    IChainlinkFeed public constant usdcToUsd =
        IChainlinkFeed(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    IChainlinkFeed public constant ethToUsd =
        IChainlinkFeed(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    IChainlinkFeed public constant fraxToUsd =
        IChainlinkFeed(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);

    IChainlinkFeed public constant crvUSDToUsd =
        IChainlinkFeed(0xEEf0C605546958c1f899b6fB336C20671f9cD49F);

    uint256 public constant ethK = 1;

    uint256 public fraxHeartbeat = 1 hours;

    uint256 public ethHeartbeat = 1 hours;

    uint256 public crvUSDHeartbeat = 24 hours;

    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    modifier onlyGov() {
        if(msg.sender != gov) revert OnlyGov();
        _;
    }
    /**
     * @notice Retrieves the latest round data for the LP token price feed
     * @dev This function calculates the LP token price in USD using the lowest usd price for FRAX and USDC from a Chainlink oracle
     * and the virtual price from the DOLA-FRAX-USDC tricrypto pool.
     * If USDC/USD price is out of bounds, it will fallback to ETH/USD price oracle and USDC to ETH ratio from the tricrypto pool
     * @return roundId The round ID of the Chainlink price feed
     * @return lpUsdPrice The latest LP token price in USD computed from the virtual price and USDC/USD or FRAX/USD feed
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
            int256 usdcUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = usdcToUsd.latestRoundData();

        if (isPriceOutOfBounds(usdcUsdPrice, usdcToUsd)) {
            (
                roundId,
                usdcUsdPrice,
                startedAt,
                updatedAt,
                answeredInRound
            ) = usdcToUsdFallbackOracle();
        }

        (
            uint80 roundIdFrax,
            int256 fraxUsdPrice,
            uint startedAtFrax,
            uint updatedAtFrax,
            uint80 answeredInRoundFrax
        ) = fraxToUsd.latestRoundData();

         if (isPriceOutOfBounds(fraxUsdPrice, fraxToUsd) || block.timestamp - updatedAtFrax > fraxHeartbeat) {
            (
                roundIdFrax,
                fraxUsdPrice,
                startedAtFrax,
                updatedAtFrax,
                answeredInRoundFrax
            ) = fraxToUsdFallbackOracle();
        }

        int256 minUsdPrice;

        // If FRAX price is lower than USDC price, use FRAX price
        if (
            fraxUsdPrice < usdcUsdPrice && updatedAtFrax > 0 || usdcUsdPrice == 0
        ) {
            minUsdPrice = fraxUsdPrice;
            roundId = roundIdFrax;
            startedAt = startedAtFrax;
            updatedAt = updatedAtFrax;
            answeredInRound = answeredInRoundFrax;
        } else {
            minUsdPrice = usdcUsdPrice;
        }

        return (
            roundId,
            (int(tricryptoFRAX.get_virtual_price()) * minUsdPrice) / 10 ** 8,
            startedAt,
            updatedAt,
            answeredInRound
        );
    }

    /** 
    @notice Retrieves the latest price for the LP token
    @return price The latest price for the LP token
    */
    function latestAnswer() external view returns (int256) {
        (, int256 price, , , ) = latestRoundData();
        return price;
    }

    /**
     * @notice Retrieves number of decimals for the LP token price feed
     * @return decimals The number of decimals for the LP token price feed
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
     * @notice Fetches the ETH to USD price and the ETH to USDC to get USDC/USD price, adjusts the decimals to match Chainlink oracles.
     * @dev The function assumes that the `price_oracle` returns the price with 18 decimals, and it adjusts to 8 decimals for compatibility with Chainlink oracles.
     * @return roundId The round ID of the ETH/USD Chainlink price feed
     * @return usdcToUsdPrice The latest USDC price in USD computed from the ETH/USD and ETH/USDC feeds
     * @return startedAt The timestamp when the latest round of ETH/USD Chainlink price feed started
     * @return updatedAt The timestamp when the latest round of ETH/USD Chainlink price feed was updated
     * @return answeredInRound The round ID of the ETH/USD Chainlink price feed in which the answer was computed
     */
    function usdcToUsdFallbackOracle()
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        int crvEthToUsdc = int(tricryptoETH.price_oracle(ethK));

        (
            uint80 roundId,
            int256 ethToUsdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = ethToUsd.latestRoundData();

        int usdcToUsdPrice = ethToUsdPrice * 10 ** 18 / crvEthToUsdc;
        
        if(isPriceOutOfBounds(ethToUsdPrice, ethToUsd) || block.timestamp - updatedAt > ethHeartbeat) {
            // will cause stale price on borrow controller
            updatedAt = 0;
        } 

        return (roundId, usdcToUsdPrice, startedAt, updatedAt, answeredInRound);
    }

        /**
     * @notice Fetches the crvUSD to USD price and the crvUSD to FRAX to get FRAX/USD price, adjusts the decimals to match Chainlink oracles.
     * @dev The function assumes that the `price_oracle` returns the price with 18 decimals, and it adjusts to 8 decimals for compatibility with Chainlink oracles.
     * @return roundId The round ID of the crvUSD/USD Chainlink price feed
     * @return fraxToUsdPrice The latest FRAX price in USD computed from the crvUSD/USD and crvUSD/FRAX feeds
     * @return startedAt The timestamp when the latest round of crvUSD/USD Chainlink price feed started
     * @return updatedAt The timestamp when the latest round of crvUSD/USD Chainlink price feed was updated
     * @return answeredInRound The round ID of the crvUSD/USD Chainlink price feed in which the answer was computed
     */
    function fraxToUsdFallbackOracle()
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        int crvUsdToFrax = int(crvUSDFrax.ema_price());

        (
            uint80 roundId,
            int256 crvUSDToUsdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = crvUSDToUsd.latestRoundData();

        int fraxToUsdPrice = crvUSDToUsdPrice * 10 ** 18 / crvUsdToFrax;
        
        if(isPriceOutOfBounds(crvUSDToUsdPrice, crvUSDToUsd) || block.timestamp - updatedAt > crvUSDHeartbeat) {
            // will cause stale price on borrow controller
            updatedAt = 0;
        } 

        return (roundId, fraxToUsdPrice, startedAt, updatedAt, answeredInRound);
    }

    /**
     * @notice Sets a new ETH heartbeat
     * @dev Can only be called by the current gov address
     * @param newHeartbeat The new ETH heartbeat
     */
    function setEthHeartbeat(uint256 newHeartbeat) external onlyGov {
        ethHeartbeat = newHeartbeat;
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
     * @notice Sets a new crvUSD heartbeat
     * @dev Can only be called by the current gov address
     * @param newHeartbeat The new crvUSD heartbeat
     */
    function setCrvUSDHeartbeat(uint256 newHeartbeat) external onlyGov {
        crvUSDHeartbeat = newHeartbeat;
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
