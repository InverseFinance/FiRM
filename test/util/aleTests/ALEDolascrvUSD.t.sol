pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelperDynamic} from "src/util/CurveDolaLPHelperDynamic.sol";
import "test/marketForkTests/DolascrvUSDConvexMarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALE} from "src/util/ALE.sol";
import {ALEBaseDolaLPDynTest, IFlashMinter} from "test/util/aleTests/ALEBaseDolaLPDyn.sol";

contract ALEDolascrvUSDTest is
    ALEBaseDolaLPDynTest,
    DolascrvUSDConvexMarketForkTest
{
    function setUp() public override {
        super.setUp();
        curvePool = ICurvePool(dolascrvUSD);

        helper = CurveDolaLPHelperDynamic(curveDolaLPHelperDynamicAddr);

        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(curvePool), 0, 2, address(0));
        ale = ALE(payable(aleAddr));
        ale.setMarket(address(market), address(DOLA), address(helper), false);
        vm.stopPrank();

        userPkEscrow = address(market.predictEscrow(userPk));
    }
}
