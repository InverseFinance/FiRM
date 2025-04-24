pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveSDolaLPHelperDynamic} from "src/util/CurveSDolaLPHelperDynamic.sol";
import "test/marketForkTests/SDolaReUSDConvexMarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALEV2} from "src/util/ALEV2.sol";
import {ALEBaseSDolaLPDynTest, IFlashMinter} from "test/util/aleTests/ALEBaseSDolaLPDyn.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
contract ALESDolaReUSDTest is
    ALEBaseSDolaLPDynTest,
    SDolaReUSDConvexMarketForkTest
{
    function setUp() public override {
        super.setUp();
        curvePool = ICurvePool(reUSDsDola);

        helper = CurveSDolaLPHelperDynamic(
            curveSDolaLPHelperDynamicAddr
        );

        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(curvePool), 1, 2, address(0));
        ale = ALEV2(payable(aleV2Addr));
        ale.setMarket(address(market), address(DOLA), address(helper), false);
        borrowController.allow(address(ale));
        vm.stopPrank();
        
        userPkEscrow = address(market.predictEscrow(userPk));

        _seedLiquidity();
    }

    function _seedLiquidity() internal {
        vm.prank(gov);
        DOLA.mint(address(this), 1000000 ether);
        deal(reUSD, address(this), 1000000 ether);

        DOLA.approve(address(helper.sDOLA()), type(uint256).max);
        helper.sDOLA().deposit(
            1000000 ether,
            address(this)
        );
        uint256[] memory amounts  = new uint256[](2);
        amounts[0] = 1000000 ether;
        amounts[1] = helper.sDOLA().balanceOf(address(this));

        IERC20(reUSD).approve(address(curvePool), type(uint256).max);
        helper.sDOLA().approve(address(curvePool), type(uint256).max);
        curvePool.add_liquidity(
            amounts,
            0,
            address(this)
        );
    }
}
