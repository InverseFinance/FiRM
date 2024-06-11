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

contract CurveLPPessimisticFeed {

    ICurvePool public immutable curvePool;

    IChainlinkFeed public immutable coin1Feed;

    IChainlinkFeed public immutable coin2Feed;

    constructor(address _curvePool, address _coin1Feed, address _coin2Feed){
        curvePool = ICurvePool(_curvePool);
        coin1Feed = IChainlinkFeed(_coin1Feed);
        coin2Feed = IChainlinkFeed(_coin2Feed);
    }

    /**
     * @return roundId The round ID of the Chainlink price feed
     * @return minUsdPrice The pessimistic LP token price in USD
     * @return startedAt The timestamp when the latest round of Chainlink price feed started
     * @return updatedAt The timestamp when the latest round of Chainlink price feed was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        public
        view
        returns (uint80 roundId, int256 minUsdPrice, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (
            uint80 roundIdCoin1,
            int256 usdPriceCoin1,
            uint startedAtCoin1,
            uint updatedAtCoin1,
            uint80 answeredInRoundCoin1
        ) = coin1Feed.latestRoundData();

        (
            uint80 roundIdCoin2,
            int256 usdPriceCoin2,
            uint startedAtCoin2,
            uint updatedAtCoin2,
            uint80 answeredInRoundCoin2
        ) = coin2Feed.latestRoundData();

        if (
            (usdPriceCoin1 < usdPriceCoin2 && updatedAtCoin1 > 0) || usdPriceCoin2 == 0
        ) {
            minUsdPrice = usdPriceCoin1 * int(curvePool.get_virtual_price()) / int(10 ** coin1Feed.decimals());
            roundId = roundIdCoin1;
            startedAt = startedAtCoin1;
            updatedAt = updatedAtCoin1;
            answeredInRound = answeredInRoundCoin1;
        } else {
            minUsdPrice = usdPriceCoin2 * int(curvePool.get_virtual_price()) / int(10 ** coin2Feed.decimals());
            roundId = roundIdCoin2;
            startedAt = startedAtCoin2;
            updatedAt = updatedAtCoin2;
            answeredInRound = answeredInRoundCoin2;
        }
    }

    /** 
    @notice Retrieves the latest price for LP token
    @return price The latest price for LP token
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
}
