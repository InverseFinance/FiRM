pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelperDynamic} from "src/util/CurveDolaLPHelperDynamic.sol";
import "test/marketForkTests/DolaWstUSRYearnV2MarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALEV2} from "src/util/ALEV2.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";
import {ALEBaseDolaLPDynYearnV2Test, IFlashMinter} from "test/util/aleTests/ALEBaseDolaLPDynYearnV2.sol";

contract ALEDolaWstUSRYearnV2Test is
    ALEBaseDolaLPDynYearnV2Test,
    DolaWstUSRYearnV2MarketForkTest
{
    address wstUSR = address(0x1202F5C7b4B9E47a1A484E8B270be34dbbC75055);
    
    function setUp() public override {
        super.setUp();

        helper = CurveDolaLPHelperDynamic(curveDolaLPHelperDynamicAddr);
        curvePool = dolaWstUSR;
        vault = IYearnVaultV2(yearn);
        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(curvePool), 0, 2, yearn);
        ale = new ALEV2(newTriDBRAddr, gov);
        ale.setMarket(address(market), address(DOLA), address(helper), false);
     
        borrowController.allow(address(ale));
        vm.stopPrank();
        userPkEscrow = address(market.predictEscrow(userPk));
        _seedPool();
    }

    function _seedPool() internal{
        // Seed the pool with 902153 wstETH and 1000000 DOLA
        deal(wstUSR, address(this), 902153 ether, true);
        vm.prank(gov);
        DOLA.mint(address(this), 1000000 ether);
        IERC20(wstUSR).approve(address(curvePool), type(uint256).max);
        DOLA.approve(address(curvePool), type(uint256).max);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000000 ether;
        amounts[1] = 902153 ether;
        curvePool.add_liquidity(amounts, 0, address(this));
    }
}
