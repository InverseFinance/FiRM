// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "src/util/FeedLib.sol";

contract DolaFraxBPPriceFeed {
    error OnlyGov();

    ICurvePool public immutable dolaFraxBP;

    IChainlinkFeed public immutable mainFraxFeed;

    IChainlinkFeed public immutable mainUsdcFeed;

    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    modifier onlyGov() {
        if (msg.sender != gov) revert OnlyGov();
        _;
    }

    constructor(
        address _curvePool,
        address _mainFraxFeed,
        address _mainUsdcFeed
    ) {
        dolaFraxBP = ICurvePool(_curvePool);
        mainFraxFeed = IChainlinkFeed(_mainFraxFeed);
        mainUsdcFeed = IChainlinkFeed(_mainUsdcFeed);
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
        ) = mainUsdcFeed.latestRoundData();

        (
            uint80 roundIdFrax,
            int256 fraxUsdPrice,
            uint startedAtFrax,
            uint updatedAtFrax,
            uint80 answeredInRoundFrax
        ) = mainFraxFeed.latestRoundData();

        int256 minUsdPrice;

        // If FRAX price is lower than USDC price, use FRAX price
        if (
            (fraxUsdPrice < usdcUsdPrice && updatedAtFrax > 0) ||
            usdcUsdPrice == 0
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
            (int(dolaFraxBP.get_virtual_price()) * minUsdPrice) / 10 ** 8,
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
        return mainUsdcFeed.assetToUsdFallback().latestRoundData();
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
        return mainFraxFeed.assetToUsdFallback().latestRoundData();
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
