// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {IChainlinkBasePriceFeed} from "src/interfaces/IChainlinkFeed.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

// Combined Chainlink and Curve price_oracle taking dynamic fees into consideration, allows for additional fallback to be set via ChainlinkBasePriceFeed
contract DynamicFeeCurveFeed {
    /// @dev Chainlink base price feed implementation for the pairedToken to USD
    IChainlinkBasePriceFeed public immutable pairedTokenToUsd;
    /// @dev Curve 2-pool
    ICurvePool public immutable curvePool;
    /// @dev FiRM asset index in Curve pool `coins` array
    uint256 public immutable assetIndex;
    /// @dev Description of the feed
    string public description;
    /// @dev Price decimals of this feed
    uint public constant decimals = 18;
    /// @dev Max fee initially set to 2%
    int public maxFee = 2e8;

    address public gov;

    address public pendingGov;

    constructor(
        address _pairedTokenToUsd,
        address _curvePool,
        address _asset,
        address _gov
    ) {
        gov = _gov;
        pairedTokenToUsd = IChainlinkBasePriceFeed(_pairedTokenToUsd);
        require(
            pairedTokenToUsd.decimals() == 18,
            "ChainlinkCurveFeed: DECIMALS_MISMATCH"
        );
        curvePool = ICurvePool(_curvePool);
        uint _index;
        if(ICurvePool(_curvePool).coins(0) == _asset)
            _index = 0;
        else if(ICurvePool(_curvePool).coins(1) == _asset)
            _index = 1;
        else
            revert("CurveFeed: ASSET NOT IN TWO POOL");
        assetIndex = _index;

        string memory coin = IERC20(_asset).symbol();
        description = string(abi.encodePacked(coin, " / USD"));
    }

    event NewMaxFee(int maxFee);
    event NewGov(address newGov);
    event NewPendingGov(address newPendingGov);

    /**
     * @notice Retrieves the latest round data for the pairedToken token price feed
     * @return roundId The round ID of the Chainlink price feed for the feed with the lowest updatedAt feed
     * @return usdPrice The latest FiRM asset price in USD
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
        int256 pairedTokenToUsdPrice;
        (
            roundId,
            pairedTokenToUsdPrice,
            startedAt,
            updatedAt,
            answeredInRound
        ) = pairedTokenToUsd.latestRoundData();
        
        int256 fee = int256(curvePool.fee());
        if(fee > maxFee) fee = maxFee;
        //crv oracle price is either asset/pairedToken or pairedToken/asset depending on asset index
        int256 crvOraclePrice = int256(curvePool.price_oracle());
        //Depending on assetIndex we either divide or multiply by crv oracle price
        usdPrice = assetIndex == 0 ?
            pairedTokenToUsdPrice * 1e18 / crvOraclePrice :
            crvOraclePrice * pairedTokenToUsdPrice / 1e18;
        //Reduce the price by the dynamic fee amount
        usdPrice -= usdPrice * fee / 1e10; 
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

    function setMaxFee(int _maxFee) external {
        require(msg.sender == gov, "ONLY GOV");
        require(_maxFee >= 0 && _maxFee <= 1e10, "CurveFeed: maxFee > 100% or negative");
        maxFee = _maxFee;
        emit NewMaxFee(_maxFee);
    }

    function setPendingGov(address _gov) external {
        require(msg.sender == gov, "ONLY GOV");
        pendingGov = _gov;
        emit NewPendingGov(_gov);
    }

    function acceptGov() external {
        require(msg.sender == pendingGov, "ONLY PENDING GOV");
        gov = pendingGov;
        pendingGov = address(0);
        emit NewGov(gov);
    }
}
