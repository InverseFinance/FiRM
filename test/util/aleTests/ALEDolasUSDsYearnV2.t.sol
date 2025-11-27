pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelperDynamic} from "src/util/CurveDolaLPHelperDynamic.sol";
import "test/marketForkTests/DolasUSDsYearnV2MarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALEV2} from "src/util/ALEV2.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";
import {ALEBaseDolaLPDynYearnV2Test, IFlashMinter} from "test/util/aleTests/ALEBaseDolaLPDynYearnV2.sol";

contract ALEDolasUSDsYearnV2Test is
    ALEBaseDolaLPDynYearnV2Test,
    DolasUSDsYearnV2MarketForkTest
{
    function setUp() public override {
        super.setUp();
        curvePool = dolasUSDs;
        helper = CurveDolaLPHelperDynamic(curveDolaLPHelperDynamicAddr);
        vault = IYearnVaultV2(yearn);
        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(curvePool), 0, 2, yearn);
        ale = new ALEV2(newTriDBRAddr, gov);
        ale.setMarket(address(market), address(DOLA), address(helper), false);

        borrowController.allow(address(ale));
        vm.stopPrank();
        userPkEscrow = address(market.predictEscrow(userPk));
    }
}
