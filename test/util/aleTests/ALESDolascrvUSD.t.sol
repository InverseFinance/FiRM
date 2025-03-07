pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveSDolaLPHelperDynamic} from "src/util/CurveSDolaLPHelperDynamic.sol";
import "test/marketForkTests/SDolascrvUSDConvexMarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALEV2} from "src/util/ALEV2.sol";
import {ALEBaseSDolaLPDynTest, IFlashMinter} from "test/util/aleTests/ALEBaseSDolaLPDyn.sol";

contract ALESDolascrvUSDTest is
    ALEBaseSDolaLPDynTest,
    SDolascrvUSDConvexMarketForkTest
{
    function setUp() public override {
        super.setUp();
        curvePool = ICurvePool(sDolascrvUSD);

        helper = new CurveSDolaLPHelperDynamic(
            gov,
            pauseGuardian,
            address(DOLA),
            sDolaAddr
        );

        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(curvePool), 1, 2, address(0));
        ale = new ALEV2(address(0), triDBRAddr);
        ale.setMarket(address(market), address(DOLA), address(helper), false);
        borrowController.allow(address(ale));
        vm.stopPrank();

        userPkEscrow = address(market.predictEscrow(userPk));
    }
}
