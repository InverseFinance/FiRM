pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelperDynamic} from "src/util/CurveDolaLPHelperDynamic.sol";
import "test/marketForkTests/DolasUSDsConvexMarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALEV2} from "src/util/ALEV2.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";
import {Test} from "forge-std/Test.sol";
import {MarketForkTest} from "test/marketForkTests/MarketForkTest.sol";
interface IFlashMinter {
    function setMaxFlashLimit(uint256 limit) external;

    function flashFee(
        address _token,
        uint256 _value
    ) external view returns (uint256);
}

abstract contract ALEBaseDolaLPDynTest is MarketForkTest {
    ALEV2 ale;
    IFlashMinter flash;
    address userPk = vm.addr(1);
    CurveDolaLPHelperDynamic helper;
    address userPkEscrow;
    ICurvePool curvePool;

    function test_leveragePosition() public {
        vm.prank(gov);
        DOLA.mint(userPk, 10000 ether);

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), 10000 ether);
        helper.convertToCollateralAndDeposit(
            10000 ether,
            userPk,
            abi.encode(address(market), 0)
        );
        vm.stopPrank();

        uint256 lpAmount = ConvexEscrowV2(address(userPkEscrow)).balance();
        console.log("lpAmount", lpAmount);
        gibDBR(userPk, 20000 ether);

        uint maxBorrowAmount = _getMaxBorrowAmount(lpAmount);

        // Sign Message for borrow on behalf
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        maxBorrowAmount,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        bytes memory swapData;

        ALEV2.DBRHelper memory dbrData;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = maxBorrowAmount;
        uint256 lpAmountAdded = curvePool.calc_token_amount(amounts, true);

        vm.prank(userPk);
        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(0),
            swapData,
            permit,
            abi.encode(address(market), uint(0)),
            dbrData
        );

        assertEq(DOLA.balanceOf(userPk), 0);
        assertEq(
            ConvexEscrowV2(address(userPkEscrow)).balance(),
            lpAmount + lpAmountAdded
        );
    }

    function test_leveragePosition_buyDBR() public {
        vm.prank(gov);
        DOLA.mint(userPk, 10000 ether);

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), 10000 ether);
        helper.convertToCollateralAndDeposit(
            10000 ether,
            userPk,
            abi.encode(address(market), 0)
        );
        vm.stopPrank();

        uint256 lpAmount = ConvexEscrowV2(address(userPkEscrow)).balance();

        uint maxBorrowAmount = _getMaxBorrowAmount(lpAmount);

        // Calculate the amount of DOLA needed to borrow to buy the DBR needed to cover for the borrowing period
        (uint256 dolaForDBR, uint256 dbrAmount) = ale
            .approximateDolaAndDbrNeeded(maxBorrowAmount, 365 days, 8);

        // Sign Message for borrow on behalf
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        maxBorrowAmount + dolaForDBR,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        bytes memory swapData;

        ALEV2.DBRHelper memory dbrData = ALEV2.DBRHelper(
            dolaForDBR,
            (dbrAmount * 97) / 100,
            0
        );

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = maxBorrowAmount;
        uint256 lpAmountAdded = curvePool.calc_token_amount(amounts, true);

        vm.prank(userPk);
        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(0),
            swapData,
            permit,
            abi.encode(address(market), uint(0)),
            dbrData
        );

        assertEq(DOLA.balanceOf(userPk), 0);
        assertEq(
            ConvexEscrowV2(address(userPkEscrow)).balance(),
            lpAmount + lpAmountAdded
        );
        assertGt(dbr.balanceOf(userPk), (dbrAmount * 97) / 100);
    }

    function test_depositAndLeveragePosition_DOLA() public {
        vm.prank(gov);
        DOLA.mint(userPk, 11000 ether);
        uint256 initialDolaDeposit = 1000 ether;

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), 10000 ether);
        helper.convertToCollateralAndDeposit(
            10000 ether,
            userPk,
            abi.encode(address(market), 0)
        );
        vm.stopPrank();

        uint256 lpAmount = ConvexEscrowV2(address(userPkEscrow)).balance();
        gibDBR(userPk, 20000 ether);

        uint maxBorrowAmount = _getMaxBorrowAmount(lpAmount);

        // Sign Message for borrow on behalf
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        maxBorrowAmount,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        bytes memory swapData;

        ALEV2.DBRHelper memory dbrData;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = maxBorrowAmount + initialDolaDeposit;
        uint256 lpAmountAdded = curvePool.calc_token_amount(amounts, true);

        vm.startPrank(userPk);
        DOLA.approve(address(ale), initialDolaDeposit);
        ale.depositAndLeveragePosition(
            initialDolaDeposit,
            maxBorrowAmount,
            address(market),
            address(0),
            swapData,
            permit,
            abi.encode(address(market), uint(0)),
            dbrData,
            false
        );

        assertEq(DOLA.balanceOf(userPk), 0);
        assertEq(
            ConvexEscrowV2(address(userPkEscrow)).balance(),
            lpAmount + lpAmountAdded
        );
    }

    function test_depositAndLeveragePosition_LP() public {
        vm.prank(gov);
        DOLA.mint(userPk, 11000 ether);

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), 11000 ether);
        uint256 initialLpAmount = helper.convertToCollateral(
            address(0),
            1000 ether,
            abi.encode(address(market), 0)
        );
        helper.convertToCollateralAndDeposit(
            10000 ether,
            userPk,
            abi.encode(address(market), 0)
        );
        vm.stopPrank();

        uint256 lpAmount = ConvexEscrowV2(address(userPkEscrow)).balance();
        gibDBR(userPk, 20000 ether);

        uint maxBorrowAmount = _getMaxBorrowAmount(lpAmount);

        // Sign Message for borrow on behalf
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        maxBorrowAmount,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        bytes memory swapData;

        ALEV2.DBRHelper memory dbrData;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = maxBorrowAmount;

        uint256 lpAmountAdded = curvePool.calc_token_amount(amounts, true);

        vm.startPrank(userPk);
        IERC20(address(curvePool)).approve(address(ale), initialLpAmount);
        ale.depositAndLeveragePosition(
            initialLpAmount,
            maxBorrowAmount,
            address(market),
            address(0),
            swapData,
            permit,
            abi.encode(address(market), uint(0)),
            dbrData,
            true
        );

        assertEq(DOLA.balanceOf(userPk), 0);
        assertEq(
            ConvexEscrowV2(address(userPkEscrow)).balance(),
            lpAmount + lpAmountAdded + initialLpAmount
        );
    }

    function test_deleveragePosition() public {
        test_leveragePosition();
        uint256 lpAmount = ConvexEscrowV2(address(userPkEscrow)).balance();
        uint256 amountToWithdraw = lpAmount / 2;

        uint256 dolaRedeemed = curvePool.calc_withdraw_one_coin(
            amountToWithdraw,
            0
        );

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        amountToWithdraw,
                        1,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        ALEV2.DBRHelper memory dbrData;
        bytes memory swapData;

        vm.prank(userPk);
        ale.deleveragePosition(
            dolaRedeemed / 2,
            address(market),
            address(0),
            amountToWithdraw,
            swapData,
            permit,
            abi.encode(address(market), uint(0)),
            dbrData
        );

        assertEq(
            ConvexEscrowV2(address(userPkEscrow)).balance(),
            lpAmount - amountToWithdraw
        );
        assertApproxEqAbs(DOLA.balanceOf(userPk), dolaRedeemed / 2, 1);
    }

    function test_deleveragePosition_sellDBR() public {
        test_leveragePosition();
        uint256 lpAmount = ConvexEscrowV2(address(userPkEscrow)).balance();
        uint256 amountToWithdraw = lpAmount;

        uint256 dolaRedeemed = curvePool.calc_withdraw_one_coin(
            amountToWithdraw,
            0
        );
        uint256 debt = market.debts(address(userPk));

        assertGt(debt, 0);

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        amountToWithdraw,
                        1,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        ALEV2.DBRHelper memory dbrData = ALEV2.DBRHelper(
            dbr.balanceOf(userPk),
            1,
            0
        ); // sell all DBR
        bytes memory swapData;

        vm.startPrank(userPk);
        dbr.approve(address(ale), dbr.balanceOf(userPk));
        ale.deleveragePosition(
            debt,
            address(market),
            address(0),
            amountToWithdraw,
            swapData,
            permit,
            abi.encode(address(market), uint(0)),
            dbrData
        );

        assertEq(
            ConvexEscrowV2(address(userPkEscrow)).balance(),
            lpAmount - amountToWithdraw
        );
        // Dbrs have also been sold
        assertGt(DOLA.balanceOf(userPk), dolaRedeemed - debt);
        assertEq(dbr.balanceOf(userPk), 0);
    }

    function _getMaxBorrowAmount(
        uint amountCollat
    ) internal view returns (uint) {
        return
            (amountCollat *
                oracle.viewPrice(address(curvePool), 0) *
                market.collateralFactorBps()) /
            10_000 /
            1e18;
    }
}
