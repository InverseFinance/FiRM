pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveSDolaLPHelperDynamic} from "src/util/CurveSDolaLPHelperDynamic.sol";
import "test/marketForkTests/SDolascrvUSDYearnV2MarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALEV2} from "src/util/ALEV2.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";
import {ALEBaseSDolaLPDynYearnV2Test} from "test/util/aleTests/ALEBaseSDolaLPDynYearnV2.sol";

contract ALESDolascrvUSDYearnV2Test is
    ALEBaseSDolaLPDynYearnV2Test,
    SDolascrvUSDYearnV2MarketForkTest
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
        vault = IYearnVaultV2(yearn);

        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(curvePool), 1, 2, yearn);
        ale = new ALEV2(address(0), triDBRAddr);
        ale.setMarket(address(market), address(DOLA), address(helper), false);
        borrowController.allow(address(ale));
        vm.stopPrank();

        userPkEscrow = address(market.predictEscrow(userPk));
    }
}
