pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelperDynamic} from "src/util/CurveDolaLPHelperDynamic.sol";
import "test/marketForkTests/DolaDeUSDYearnV2MarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALE} from "src/util/ALE.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";
import {ALEBaseDolaLPDynYearnV2Test, IFlashMinter} from "test/util/aleTests/ALEBaseDolaLPDynYearnV2.sol";

contract ALEDolaDeUSDeYearnV2Test is
    ALEBaseDolaLPDynYearnV2Test,
    DolaDeUSDYearnV2MarketForkTest
{
    function setUp() public override {
        super.setUp();

        helper = new CurveDolaLPHelperDynamic(
            gov,
            pauseGuardian,
            address(DOLA)
        );
        curvePool = dolaDeUSD;
        vault = IYearnVaultV2(yearn);
        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(curvePool), 0, 2, yearn);
        ale = new ALE(address(0), triDBRAddr);
        ale.setMarket(address(market), address(DOLA), address(helper), false);

        flash = IFlashMinter(address(ale.flash()));
        flash.setMaxFlashLimit(1000000 ether);
        DOLA.addMinter(address(flash));
        borrowController.allow(address(ale));
        vm.stopPrank();
        userPkEscrow = address(market.predictEscrow(userPk));
    }
}
