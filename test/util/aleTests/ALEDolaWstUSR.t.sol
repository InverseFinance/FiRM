pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelperDynamic} from "src/util/CurveDolaLPHelperDynamic.sol";
import "test/marketForkTests/DolaWstUSRConvexMarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALEV2} from "src/util/ALEV2.sol";
import {ALEBaseDolaLPDynTest, IFlashMinter} from "test/util/aleTests/ALEBaseDolaLPDyn.sol";

contract ALEDolaWstUSRTest is
    ALEBaseDolaLPDynTest,
    DolaWstUSRConvexMarketForkTest
{
    address wstUSR = address(0x1202F5C7b4B9E47a1A484E8B270be34dbbC75055);
    
    function setUp() public override {
        super.setUp();
        curvePool = dolaWstUSR;

        helper = CurveDolaLPHelperDynamic(curveDolaLPHelperDynamicAddr);

        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(curvePool), 0, 2, address(0));
        ale = ALEV2(payable(aleV2Addr));
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
