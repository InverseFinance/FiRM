pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelperDynamic} from "src/util/CurveDolaLPHelperDynamic.sol";
import "test/marketForkTests/DolascrvUSDYearnV2MarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALE} from "src/util/ALE.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";
import {ALEBaseDolaLPDynYearnV2Test, IFlashMinter} from "test/util/aleTests/ALEBaseDolaLPDynYearnV2.sol";

contract ALEDolascrvUSDYearnV2Test is
    ALEBaseDolaLPDynYearnV2Test,
    DolascrvUSDYearnV2MarketForkTest
{
    function setUp() public override {
        super.setUp();
        curvePool = ICurvePool(dolascrvUSD);
        helper = CurveDolaLPHelperDynamic(curveDolaLPHelperDynamicAddr);
        vault = IYearnVaultV2(yearn);

        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(curvePool), 0, 2, yearn);
        ale = ALE(payable(aleAddr));
        ale.setMarket(address(market), address(DOLA), address(helper), false);
        vm.stopPrank();

        userPkEscrow = address(market.predictEscrow(userPk));
    }
}
