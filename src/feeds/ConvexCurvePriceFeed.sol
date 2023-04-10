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
    uint public revertThreshold = 5000;

    function decimals() external view returns (uint8){
        return 18;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80){
        (uint80 roundId,int256 crvUsdPrice,uint startedAt,uint updatedAt,uint80 answeredInRound) = crvToUsd.latestRoundData();
        uint crvPerCvxCrv = cvxCrvCrvPool.price_oracle();
        if(crvPerCvxCrv > 10 ** 18){
            //1 CRV can always be traded for 1 CvxCrv, so price for CvxCrv should never be higher than the price of CRV
            return (roundId, crvUsdPrice, startedAt, updatedAt, answeredInRound);
        }
        //If there's too big of a difference between the EMA price and last price revert
        require(crvPerCvxCrv * revertThreshold / 10000 <= cvxCrvCrvPool.last_price(), "BELOW REVERT THRESHOLD");
        require(crvPerCvxCrv * (10000 + revertThreshold) / 10000 >= cvxCrvCrvPool.last_price(), "ABOVE REVERT THRESHOLD");
        //Divide by 10**8 as crvUsdPrice is 8 decimals
        int256 cvxCrvUsdPrice = crvUsdPrice * int256(crvPerCvxCrv) / 10**8;
        return (roundId, cvxCrvUsdPrice, startedAt, updatedAt, answeredInRound);
    }

    function setRevertThreshold(uint newRevertThreshold) public {
        require(msg.sender == gov, "ONLY GOV");
        revertThreshold = newRevertThreshold;
    }

    function setGov(address newGov) public {
        require(msg.sender == gov, "ONLY GOV");
        gov = newGov;
    }
}
