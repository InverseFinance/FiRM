pragma solidity ^0.8.13;

interface IChainlinkFeed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

interface IGOhm {
    function index() external view returns (uint256);
}

contract gOhmFeed is IChainlinkFeed{

    IChainlinkFeed ohmEthFeed = IChainlinkFeed(0x9a72298ae3886221820B1c878d12D872087D3a23);
    IChainlinkFeed ethUsdFeed = IChainlinkFeed(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    IGOhm gOhm = IGOhm(0x0ab87046fBb341D058F17CBC4c1133F25a20a52f);

    function decimals() external view returns (uint8){
        return 18;
    }
    
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80){
        (,int ohmEthPrice,,,) = ohmEthFeed.latestRoundData();
        (,int ethUsdPrice8Decimals, uint startedAt, uint updatedAt, uint80 answeredInRound)  = ethUsdFeed.latestRoundData();
        int ethUsdPrice = ethUsdPrice8Decimals * 10**10;
        int index = int(gOhm.index());
        //We don't really use startedAt, updatedAt and answeredInRound, so may be better to just pass 0
        return (0, index*ohmEthPrice*ethUsdPrice / 10**17, startedAt, updatedAt, answeredInRound);
    }
}
