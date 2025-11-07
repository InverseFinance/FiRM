pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelperDynamic} from "src/util/CurveDolaLPHelperDynamic.sol";
import "test/marketForkTests/DolaUSRConvexMarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALEV2} from "src/util/ALEV2.sol";
import {ALEBaseDolaLPDynTest, IFlashMinter} from "test/util/aleTests/ALEBaseDolaLPDyn.sol";

contract ALEDolaUSRTest is
    ALEBaseDolaLPDynTest,
    DolaUSRConvexMarketForkTest
{
    function setUp() public override {
        super.setUp();
        curvePool = dolaUSR;

        helper = CurveDolaLPHelperDynamic(curveDolaLPHelperDynamicAddr);

        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(curvePool), 0, 2, address(0));
        ale = new ALEV2(newTriDBRAddr, gov);
        ale.setMarket(address(market), address(DOLA), address(helper), false);

        borrowController.allow(address(ale));
        ale.setCurvePool(address(newTriDBRAddr),0,1);
       
        vm.stopPrank();
        userPkEscrow = address(market.predictEscrow(userPk));
        
        _seedTriDbrPool();
    }

    function _seedTriDbrPool() internal {
        vm.prank(gov);
        DOLA.mint(address(this), 600000 ether);
        DOLA.approve(address(newTriDBRAddr), 600000 ether);
        deal(address(dbrAddr), address(this), 10000000 ether);
        deal(address(invAddr), address(this), 20000 ether);
        IERC20(dbrAddr).approve(address(newTriDBRAddr), 10000000 ether);
        IERC20(invAddr).approve(address(newTriDBRAddr), 20000 ether);
        uint[3] memory amounts;
        amounts[0] = 600000 ether;
        amounts[1] = 10000000 ether;
        amounts[2] = 20000 ether;

        ICurvePool(newTriDBRAddr).add_liquidity(amounts, 0);
    }
}
