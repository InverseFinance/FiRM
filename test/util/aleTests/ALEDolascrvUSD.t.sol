pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelperDynamic} from "src/util/CurveDolaLPHelperDynamic.sol";
import "test/marketForkTests/DolascrvUSDConvexMarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALEV2} from "src/util/ALEV2.sol";
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
        ale = new ALEV2(newTriDBRAddr, gov);
        ale.setMarket(address(market), address(DOLA), address(helper), false);
        borrowController.allow(address(ale));
        vm.stopPrank();

        userPkEscrow = address(market.predictEscrow(userPk));
    }
}
