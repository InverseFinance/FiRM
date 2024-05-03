// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

interface IChainlinkFeed {
    function aggregator() external view returns (address aggregator);

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

interface IAggregator {
    function maxAnswer() external view returns (int192);

    function minAnswer() external view returns (int192);
}

interface ICurvePool {
    function ema_price() external view returns (uint256);
}

contract StYEthPriceFeed {
    error OnlyGov();

    ICurvePool public constant curveYETH =
        ICurvePool(0x69ACcb968B19a53790f43e57558F5E443A91aF22);

    IERC4626 public constant styETH =
        IERC4626(0x583019fF0f430721aDa9cfb4fac8F06cA104d0B4);

    IChainlinkFeed public constant ethToUsd =
        IChainlinkFeed(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    IChainlinkFeed public constant ethToBtc = 
        IChainlinkFeed(0xAc559F25B1619171CbC396a50854A3240b6A4e99);

    IChainlinkFeed public constant btcToUsd = 
        IChainlinkFeed(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);

    uint256 public ethToBtcHeartbeat = 1 hours;
    uint256 public btcToUsdHeartbeat = 1 hours;
    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    modifier onlyGov() {
        if(msg.sender != gov) revert OnlyGov();
        _;
    }
    
    /**
     * @notice Retrieves the latest round data for the stYETH price feed
     * @return roundId The round ID of the Chainlink price feed
     * @return ethUsdPrice The latest stYETH price in USD computed from ETH/USD Chainlink price feed
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
            int256 ethUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = ethToUsd.latestRoundData();

         if (isPriceOutOfBounds(ethUsdPrice, ethToUsd)) {
            (
                roundId,
                ethUsdPrice,
                startedAt,
                updatedAt,
                answeredInRound
            ) = ethToUsdFallbackOracle();
        }

        int256 yEthToEthPrice = int256(curveYETH.ema_price());

        if(yEthToEthPrice > 1e18){
            yEthToEthPrice = 1e18;
        }

        int256 stYEthDollarPrice =
            yEthToEthPrice * int(styETH.convertToAssets(1e18)) * ethUsdPrice /
            int(10 ** (decimals() - 10)) / 1e18;

        return (roundId, stYEthDollarPrice, startedAt, updatedAt, answeredInRound);
    }

       /**
     * @notice Fetches the ETH to BTC price and the BTC/USD to get ETH/USD price, adjusts the decimals to match Chainlink oracles.
     * @dev It will return the roundId, startedAt, updatedAt and answeredInRound from the ETH/USD Chainlink price feed when both oracles are not stale,
     * in which case updatedAt will be zero
     * @return roundId The round ID of the ETH/BTC Chainlink price feed
     * @return ethToUsdPrice The latest ETH price in USD computed from the ETH/BTC and BTC/USD feeds
     * @return startedAt The timestamp when the latest round of ETH/BTC Chainlink price feed started
     * @return updatedAt The timestamp when the latest round of ETH/BTC Chainlink price feed was updated
     * @return answeredInRound The round ID of the ETH/BTC Chainlink price feed in which the answer was computed
     */
    function ethToUsdFallbackOracle()
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (
            uint80 roundId,
            int256 ethToBtcPrice,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = ethToBtc.latestRoundData();

        (
            ,
            int256 btcToUsdPrice,
            ,
            uint256 updatedBtcUsdAt,
        ) = btcToUsd.latestRoundData();

        if(isPriceOutOfBounds(ethToBtcPrice, ethToBtc) || block.timestamp - updatedAt > ethToBtcHeartbeat) {
            // Will force stale price on borrow controller
            updatedAt = 0;
        }

        if(isPriceOutOfBounds(btcToUsdPrice, btcToUsd) || block.timestamp - updatedBtcUsdAt > btcToUsdHeartbeat) {
            // Will force stale price on borrow controller
            updatedAt = 0;
        }

        int256 ethToUsdPrice;

        if(updatedAt != 0) {
             ethToUsdPrice = ethToBtcPrice * btcToUsdPrice / 10**8;
        }

        return (roundId, ethToUsdPrice, startedAt, updatedAt, answeredInRound);
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
    @notice Retrieves the latest price for the INV token
    @return price The latest price for the INV token
    */
    function latestAnswer() external view returns (int256) {
        (, int256 price, , , ) = latestRoundData();
        return price;
    }

    /**
     * @notice Retrieves number of decimals for the INV price feed
     * @return decimals The number of decimals for the INV price feed
     */
    function decimals() public pure returns (uint8) {
        return 18;
    }

    /**
     * @notice Sets a new ETH/BTC heartbeat
     * @dev Can only be called by the current gov address
     * @param newHeartbeat The new ETH/BTC heartbeat
     */
    function setEthBtcHeartbeat(uint256 newHeartbeat) external onlyGov {
        ethToBtcHeartbeat = newHeartbeat;
    }

     /**
     * @notice Sets a new BTC/USD heartbeat
     * @dev Can only be called by the current gov address
     * @param newHeartbeat The new BTC/USD heartbeat
     */
    function setBtcUsdHeartbeat(uint256 newHeartbeat) external onlyGov {
        btcToUsdHeartbeat = newHeartbeat;
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
