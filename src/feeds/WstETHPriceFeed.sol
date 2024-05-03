// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IChainlinkFeed {
    function aggregator() external view returns (address aggregator);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface IAggregator {
    function maxAnswer() external view returns (int192);

    function minAnswer() external view returns (int192);
}

interface IWstETH {
    function stEthPerToken() external view returns (uint256);
}

contract WstETHPriceFeed {
    error OnlyGov();

    IWstETH public constant wstETH =
        IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    IChainlinkFeed public constant stEthToUsd =
        IChainlinkFeed(0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8);
    
    IChainlinkFeed public constant ethToUsd =
        IChainlinkFeed(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    
    IChainlinkFeed public constant stEthToEth =
        IChainlinkFeed(0x86392dC19c0b719886221c78AB11eb8Cf5c52812);

    uint256 public ethHeartbeat = 1 hours;
    uint256 public stEthToEthHeartbeat = 24 hours;

    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    modifier onlyGov() {
        if(msg.sender != gov) revert OnlyGov();
        _;
    }

    /**
     * @notice Retrieves the latest round data for wstETH price feed
     * @dev This function calculates the wstETH price in USD by combining the stETH to USD price from a Chainlink oracle 
     * and the stETH per wstETH ratio from the wstETH contract. 
     * If stETH/USD price is out of bounds, it will fallback to ETH/USD and stETH/ETH oracles to get the price.
     * @return roundId The round ID of the Chainlink price feed
     * @return wstEthUsdPrice The latest wstETH price in USD
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
            int256 stEthUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = stEthToUsd.latestRoundData();


        uint256 stEthPerToken = wstETH.stEthPerToken();

        if (isPriceOutOfBounds(stEthUsdPrice, stEthToUsd)) {
            (
                roundId,
                stEthUsdPrice,
                startedAt,
                updatedAt,
                answeredInRound
            ) = stEthToUsdFallbackOracle();
        }

        int256 wstEthUsdPrice = int256(stEthPerToken) * stEthUsdPrice / 10 ** 8;

        return (roundId, wstEthUsdPrice, startedAt, updatedAt, answeredInRound);
    }

    /** 
    @notice Retrieves the latest price for the wstETH token
    @return price The latest price for the wstETH token
    */
    function latestAnswer() external view returns (int256) {
        (, int256 price, , , ) = latestRoundData();
        return price;
    }

    /**
     * @notice Retrieves number of decimals for the wstETH price feed
     * @return decimals The number of decimals for the wstETH price feed
     */
    function decimals() external pure returns (uint8) {
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
     * @notice Fetches the ETH to USD price and the stETH/ETH to get stETH/USD price, adjusts the decimals to match Chainlink oracles.
     * @dev It will return the roundId, startedAt, updatedAt and answeredInRound from the ETH/USD Chainlink price feed when both oracles are not stale,
     * in which case updatedAt will be zero
     * @return roundId The round ID of the ETH/USD Chainlink price feed
     * @return stEthToUsdPrice The latest stETH price in USD computed from the ETH/USD and stETH/ETH feeds
     * @return startedAt The timestamp when the latest round of ETH/USD Chainlink price feed started
     * @return updatedAt The timestamp when the latest round of ETH/USD Chainlink price feed was updated
     * @return answeredInRound The round ID of the ETH/USD Chainlink price feed in which the answer was computed
     */
    function stEthToUsdFallbackOracle()
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (
            uint80 roundId,
            int256 ethToUsdPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = ethToUsd.latestRoundData();

        (
            ,
            int256 stEthToEthPrice,
            ,
            uint256 updatedAtStEth,
        ) = stEthToEth.latestRoundData();

        int256 stEthToUsdPrice = ethToUsdPrice * stEthToEthPrice / 10**18;

        if(isPriceOutOfBounds(ethToUsdPrice, ethToUsd) || block.timestamp - updatedAt > ethHeartbeat) {
            // Will force stale price on borrow controller
            updatedAt = 0;
        }

        if(isPriceOutOfBounds(stEthToEthPrice, stEthToEth) || block.timestamp - updatedAtStEth > stEthToEthHeartbeat) {
            // Will force stale price on borrow controller
            updatedAt = 0;
        }

        return (roundId, stEthToUsdPrice, startedAt, updatedAt, answeredInRound);
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
     * @notice Sets a new stETH/ETH heartbeat
     * @dev Can only be called by the current gov address
     * @param newHeartbeat The new stETH/ETH heartbeat
     */
    function setStEthHeartbeat(uint256 newHeartbeat) external onlyGov {
        stEthToEthHeartbeat = newHeartbeat;
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