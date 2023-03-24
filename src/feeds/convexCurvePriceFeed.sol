pragma solidity ^0.8.13;

interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

interface ICurvePool {
    function ema_price() external view returns (uint256);
    function price_oracle() external view returns (uint256);
}

contract ConvexCurvePriceFeed is IChainlinkFeed {
    
    IChainlinkFeed crvToUsd = IChainlinkFeed(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f);
    ICurvePool cvxCrvCrvPool = ICurvePool(0x971add32Ea87f10bD192671630be3BE8A11b8623);

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
        int256 cvxCrvUsdPrice = crvUsdPrice * int256(crvPerCvxCrv) / 10**18;
        return (roundId, cvxCrvUsdPrice, startedAt, updatedAt, answeredInRound);
    }
}
