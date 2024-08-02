pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelper} from "src/util/CurveDolaLPHelper.sol";
import "test/marketForkTests/CrvUSDDolaConvexMarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";

contract CurveDolaLPHelperTest is CrvUSDDolaConvexMarketForkTest {
    CurveDolaLPHelper helper;
    address receiver = vm.addr(23);

    function setUp() public override {
        super.setUp();

        helper = new CurveDolaLPHelper(gov, pauseGuardian, address(DOLA));

        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(dolaCrvUSD), 0, 2);
        vm.stopPrank();
    }

    function test_transformToCollateral() public {
        uint256 amount = 100 ether;
        // Estimate LP amount
        uint256[2] memory amounts = [amount, 0];
        uint estLpAmount = dolaCrvUSD.calc_token_amount(amounts, true);

        DOLA.approve(address(helper), amount);
        uint256 lpAmount = helper.transformToCollateral(
            amount,
            abi.encode(address(market), uint(1))
        );
        assertEq(
            IERC20(address(dolaCrvUSD)).balanceOf(address(this)),
            lpAmount
        );
        assertEq(lpAmount, estLpAmount);
    }

    function test_transformToCollateral_receiver() public {
        uint256 amount = 100 ether;
        // Estimate LP amount
        uint256[2] memory amounts = [amount, 0];
        uint estLpAmount = dolaCrvUSD.calc_token_amount(amounts, true);

        DOLA.approve(address(helper), amount);
        uint256 lpAmount = helper.transformToCollateral(
            amount,
            receiver,
            abi.encode(address(market), uint(1))
        );
        assertEq(IERC20(address(dolaCrvUSD)).balanceOf(receiver), lpAmount);
        assertEq(lpAmount, estLpAmount);
    }

    function test_transformToCollateralAndDeposit() public {
        uint256 amount = 100 ether;
        // Estimate LP amount
        uint256[2] memory amounts = [amount, 0];
        uint estLpAmount = dolaCrvUSD.calc_token_amount(amounts, true);

        DOLA.approve(address(helper), amount);
        uint256 lpAmount = helper.transformToCollateralAndDeposit(
            amount,
            address(this),
            abi.encode(address(market), uint(1))
        );
        assertEq(IERC20(address(dolaCrvUSD)).balanceOf(address(this)), 0);
        assertEq(
            IERC20(address(dolaCrvUSD)).balanceOf(
                address(market.predictEscrow(address(this)))
            ),
            lpAmount
        );
        assertEq(lpAmount, estLpAmount);
    }

    function test_transformToCollateralAndDeposit_receiver() public {
        uint256 amount = 100 ether;
        // Estimate LP amount
        uint256[2] memory amounts = [amount, 0];
        uint estLpAmount = dolaCrvUSD.calc_token_amount(amounts, true);

        DOLA.approve(address(helper), amount);
        uint256 lpAmount = helper.transformToCollateralAndDeposit(
            amount,
            receiver,
            abi.encode(address(market), uint(1))
        );
        assertEq(IERC20(address(dolaCrvUSD)).balanceOf(receiver), 0);
        assertEq(
            IERC20(address(dolaCrvUSD)).balanceOf(
                address(market.predictEscrow(receiver))
            ),
            lpAmount
        );
        assertEq(lpAmount, estLpAmount);
    }

    function test_transformFromCollateral() public {
        test_transformToCollateral();
        uint256 amount = IERC20(address(dolaCrvUSD)).balanceOf(address(this));
        // Estimate DOLA amount
        uint estDolaAmount = dolaCrvUSD.calc_withdraw_one_coin(amount, 0);
        uint dolaBalBefore = DOLA.balanceOf(address(this));
        IERC20(address(dolaCrvUSD)).approve(address(helper), amount);
        uint256 dolaAmount = helper.transformFromCollateral(
            amount,
            abi.encode(address(market), uint(1))
        );

        assertEq(DOLA.balanceOf(address(this)) - dolaBalBefore, dolaAmount);
        assertEq(dolaAmount, estDolaAmount);
    }

    function test_transformFromCollateral_receiver() public {
        test_transformToCollateral();
        uint256 amount = IERC20(address(dolaCrvUSD)).balanceOf(address(this));
        // Estimate DOLA amount
        uint estDolaAmount = dolaCrvUSD.calc_withdraw_one_coin(amount, 0);

        IERC20(address(dolaCrvUSD)).approve(address(helper), amount);
        uint256 dolaAmount = helper.transformFromCollateral(
            amount,
            receiver,
            abi.encode(address(market), uint(1))
        );

        assertEq(DOLA.balanceOf(receiver), dolaAmount);
        assertEq(dolaAmount, estDolaAmount);
    }

    function test_withdrawAndTransformFromCollateral() public {
        test_transformToCollateralAndDeposit_receiver();
        uint256 amount = IERC20(address(dolaCrvUSD)).balanceOf(
            address(market.predictEscrow(receiver))
        );
        // Estimate DOLA amount
        uint estDolaAmount = dolaCrvUSD.calc_withdraw_one_coin(amount, 0);

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(helper),
                        receiver,
                        amount,
                        0,
                        block.timestamp
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(23, hash);

        IMultiMarketTransformHelper.Permit
            memory permit = IMultiMarketTransformHelper.Permit(
                block.timestamp,
                v,
                r,
                s
            );
        vm.prank(receiver);
        uint256 dolaAmount = helper.withdrawAndTransformFromCollateral(
            amount,
            receiver,
            permit,
            abi.encode(address(market), uint(1))
        );

        assertEq(DOLA.balanceOf(receiver), dolaAmount);
        assertEq(dolaAmount, estDolaAmount);
    }

    function test_withdrawAndTransformFromCollateral_other_receiver() public {
        test_transformToCollateralAndDeposit_receiver();
        uint256 amount = IERC20(address(dolaCrvUSD)).balanceOf(
            address(market.predictEscrow(receiver))
        );
        // Estimate DOLA amount
        uint estDolaAmount = dolaCrvUSD.calc_withdraw_one_coin(amount, 0);
        uint dolaBalBefore = DOLA.balanceOf(address(this));

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(helper),
                        receiver,
                        amount,
                        0,
                        block.timestamp
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(23, hash);

        IMultiMarketTransformHelper.Permit
            memory permit = IMultiMarketTransformHelper.Permit(
                block.timestamp,
                v,
                r,
                s
            );
        vm.prank(receiver);
        uint256 dolaAmount = helper.withdrawAndTransformFromCollateral(
            amount,
            address(this),
            permit,
            abi.encode(address(market), uint(1))
        );

        assertEq(DOLA.balanceOf(address(this)) - dolaBalBefore, dolaAmount);
        assertEq(dolaAmount, estDolaAmount);
    }
}
