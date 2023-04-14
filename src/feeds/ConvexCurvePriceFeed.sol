pragma solidity ^0.8.13;

interface IChainlinkFeed {
    function decimals() external view returns (uint8 decimals);
    function latestRoundData() external view returns (uint80 roundId, int256 crvUsdPrice, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

interface ICurvePool {
    function price_oracle() external view returns (uint256);
    function last_price() external view returns (uint256);
}

contract ConvexCurvePriceFeed is IChainlinkFeed {
    
    IChainlinkFeed public crvToUsd = IChainlinkFeed(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f);
    ICurvePool public cvxCrvCrvPool = ICurvePool(0x971add32Ea87f10bD192671630be3BE8A11b8623);
    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address public guardian = 0xE3eD95e130ad9E15643f5A5f232a3daE980784cd;
    uint public minCrvPerCvxCrvRatio = 10**18 / 2;

    event NewMinCrvPerCvxCrvRatio(uint newMinRatio);

    function decimals() external view returns (uint8){
        return 18;
    }

    /**
     * @notice Retrieves the latest round data for the CvxCrv token price feed
     * @dev This function calculates the CvxCrv price in USD by combining the CRV to USD price from a Chainlink oracle and the CvxCrv to CRV ratio from a Curve pool
     * @return roundId The round ID of the Chainlink price feed for CRV to USD
     * @return cvxCrvUsdPrice The latest CvxCrv price in USD
     * @return startedAt The timestamp when the latest round of Chainlink price feed started
     * @return updatedAt The timestamp when the latest round of Chainlink price feed was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80){
        (uint80 roundId,int256 crvUsdPrice,uint startedAt,uint updatedAt,uint80 answeredInRound) = crvToUsd.latestRoundData();
        uint crvPerCvxCrv = cvxCrvCrvPool.price_oracle();
        if(crvPerCvxCrv > 10 ** 18){
            //1 CRV can always be traded for 1 CvxCrv, so price for CvxCrv should never be higher than the price of CRV
            crvPerCvxCrv = 10**18;
        } else if (minCrvPerCvxCrvRatio > crvPerCvxCrv) {
            //If price of cvxCrv falls below a certain raio, we assume something might have gone wrong with the EMA oracle
            //NOTE: This ratio floor is only meant as an intermediate protection, and should be removed as the EMA oracle gains lindy
            crvPerCvxCrv = minCrvPerCvxCrvRatio;
        }
        
        //Divide by 10**8 as crvUsdPrice is 8 decimals
        int256 cvxCrvUsdPrice = crvUsdPrice * int256(crvPerCvxCrv) / 10**8;
        return (roundId, cvxCrvUsdPrice, startedAt, updatedAt, answeredInRound);
    }

    /**
     * @notice Sets a new minimum CRV per CvxCrv ratio
     * @dev Can only be called by the gov or guardian addresses
     * @param newMinRatio The new minimum CRV per CvxCrv ratio
     */
    function setMinCrvPerCvxCrvRatio(uint newMinRatio) external {
        require(msg.sender == gov || msg.sender == guardian, "ONLY GOV OR GUARDIAN");
        require(newMinRatio <= 10**18, "RATIO CAN'T EXCEED 1");
        minCrvPerCvxCrvRatio = newMinRatio;
        emit NewMinCrvPerCvxCrvRatio(newMinRatio);
    }

    /**
     * @notice Sets a new guardian address
     * @dev Can only be called by the gov address
     * @param newGuardian The new guardian address
     */
    function setGuardian(address newGuardian) external {
        require(msg.sender == gov, "ONLY GOV");
        guardian = newGuardian;
    }

    /**
     * @notice Sets a new gov address
     * @dev Can only be called by the current gov address
     * @param newGov The new gov address
     */
    function setGov(address newGov) external {
        require(msg.sender == gov, "ONLY GOV");
        gov = newGov;
    }
}
