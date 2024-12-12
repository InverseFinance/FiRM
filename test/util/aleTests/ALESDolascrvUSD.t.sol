pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveSDolaLPHelperDynamic} from "src/util/CurveSDolaLPHelperDynamic.sol";
import "test/marketForkTests/SDolascrvUSDConvexMarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALE} from "src/util/ALE.sol";
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
        ale = ALE(payable(aleAddr));
        ale.setMarket(address(market), address(DOLA), address(helper), false);
        vm.stopPrank();

        userPkEscrow = address(market.predictEscrow(userPk));
    }
}
