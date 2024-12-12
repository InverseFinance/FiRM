pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelperDynamic} from "src/util/CurveDolaLPHelperDynamic.sol";
import "test/marketForkTests/DolasUSDsConvexMarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALE} from "src/util/ALE.sol";
import {ALEBaseDolaLPDynTest, IFlashMinter} from "test/util/aleTests/ALEBaseDolaLPDyn.sol";

contract ALEDolasUSDsTest is
    ALEBaseDolaLPDynTest,
    DolasUSDsConvexMarketForkTest
{
    function setUp() public override {
        super.setUp();
        curvePool = dolasUSDs;

        helper = new CurveDolaLPHelperDynamic(
            gov,
            pauseGuardian,
            address(DOLA)
        );

        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(curvePool), 0, 2, address(0));
        ale = new ALE(address(0), triDBRAddr);
        ale.setMarket(address(market), address(DOLA), address(helper), false);

        flash = IFlashMinter(address(ale.flash()));
        flash.setMaxFlashLimit(100000 ether);
        DOLA.addMinter(address(flash));
        borrowController.allow(address(ale));
        vm.stopPrank();
        userPkEscrow = address(market.predictEscrow(userPk));
    }
}
