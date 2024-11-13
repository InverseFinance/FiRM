pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelper} from "src/util/CurveDolaLPHelper.sol";
import "test/marketForkTests/DolaFraxBPConvexMarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALE} from "src/util/ALE.sol";

interface IFlashMinter {
    function setMaxFlashLimit(uint256 _maxFlashLimit) external;

    function flashFee(
        address _token,
        uint256 _value
    ) external view returns (uint256);
}

contract ALEDolaFraxBPTest is DolaFraxBPConvexMarketForkTest {
    ALE ale;
    IFlashMinter flash;
    address userPk = vm.addr(1);
    CurveDolaLPHelper helper;
    address userPkEscrow;
    ICurvePool curvePool;

    function setUp() public override {
        super.setUp();
        curvePool = dolaFraxBP;

        helper = CurveDolaLPHelper(curveDolaLPHelperAddr);

        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(curvePool), 0, 2, address(0));
        ale = new ALE(address(0), triDBRAddr);
        ale.setMarket(address(market), address(DOLA), address(helper), false);

        flash = IFlashMinter(address(ale.flash()));
        flash.setMaxFlashLimit(10000000 ether);
        DOLA.addMinter(address(flash));
        borrowController.allow(address(ale));
        vm.stopPrank();
        userPkEscrow = address(market.predictEscrow(userPk));
    }

    function test_leveragePosition() public {
        vm.prank(gov);
        DOLA.mint(userPk, 10000000 ether);

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), 10000000 ether);
        helper.transformToCollateralAndDeposit(
            10000000 ether,
            userPk,
            abi.encode(address(market), 0)
        );
        vm.stopPrank();

        uint256 lpAmount = ConvexEscrowV2(userPkEscrow).balance();
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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData;

        ALE.DBRHelper memory dbrData;

        uint256[2] memory amounts = [maxBorrowAmount, 0];
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
        assertApproxEqRel(
            ConvexEscrowV2(userPkEscrow).balance(),
            lpAmount + lpAmountAdded,
            1e14 // 0.01% Delta
        );
    }

    function test_leveragePosition_buyDBR(uint amount) public {
        vm.assume(amount < 10000000 ether);
        vm.assume(amount > 0.001 ether);
        vm.prank(gov);
        DOLA.mint(userPk, amount);

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), amount);
        helper.transformToCollateralAndDeposit(
            amount,
            userPk,
            abi.encode(address(market), 0)
        );
        vm.stopPrank();

        uint256 lpAmount = ConvexEscrowV2(userPkEscrow).balance();

        uint maxBorrowAmount = _getMaxBorrowAmount(lpAmount);

        // Calculate the amount of DOLA needed to borrow to buy the DBR needed to cover for the borrowing period
        (uint256 dolaForDBR, uint256 dbrAmount) = ale
            .approximateDolaAndDbrNeeded(maxBorrowAmount, 15 days, 8);

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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData;

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
            dolaForDBR,
            (dbrAmount * 95) / 100,
            0
        );

        uint256[2] memory amounts = [maxBorrowAmount, 0];
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
        assertApproxEqRel(
            ConvexEscrowV2(userPkEscrow).balance(),
            lpAmount + lpAmountAdded,
            1e14 // 0.01% Delta
        );
        assertGt(dbr.balanceOf(userPk), (dbrAmount * 95) / 100);
    }

    function test_depositAndLeveragePosition_DOLA(uint amount) public {
        vm.assume(amount < 10000000 ether);
        vm.assume(amount > 0.001 ether);
        vm.prank(gov);
        DOLA.mint(userPk, amount);
        uint256 initialDolaDeposit = amount / 10;

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), amount - initialDolaDeposit);
        helper.transformToCollateralAndDeposit(
            amount - initialDolaDeposit,
            userPk,
            abi.encode(address(market), 0)
        );
        vm.stopPrank();

        uint256 lpAmount = ConvexEscrowV2(userPkEscrow).balance();
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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData;

        ALE.DBRHelper memory dbrData;

        uint256[2] memory amounts = [maxBorrowAmount + initialDolaDeposit, 0];
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
        assertApproxEqRel(
            ConvexEscrowV2(userPkEscrow).balance(),
            lpAmount + lpAmountAdded,
            1e14 // 0.01% Delta
        );
    }

    function test_depositAndLeveragePosition_LP(uint256 amount) public {
        vm.assume(amount < 10000000 ether);
        vm.assume(amount > 0.001 ether);
        vm.prank(gov);
        DOLA.mint(userPk, amount);
        uint256 initialDolaDeposit = amount / 10;

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), amount);
        uint256 initialLpAmount = helper.transformToCollateral(
            initialDolaDeposit,
            abi.encode(address(market), 0)
        );
        helper.transformToCollateralAndDeposit(
            amount - initialDolaDeposit,
            userPk,
            abi.encode(address(market), 0)
        );
        vm.stopPrank();

        uint256 lpAmount = ConvexEscrowV2(userPkEscrow).balance();
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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData;

        ALE.DBRHelper memory dbrData;

        uint256[2] memory amounts = [maxBorrowAmount, 0];
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
        assertApproxEqRel(
            ConvexEscrowV2(userPkEscrow).balance(),
            lpAmount + lpAmountAdded + initialLpAmount,
            1e14 // 0.01% Delta
        );
    }

    function test_deleveragePosition(uint256 lpAmount) public {
        test_leveragePosition();
        uint256 totalLpAmount = ConvexEscrowV2(userPkEscrow).balance();
        vm.assume(lpAmount > 0.0001 ether);
        vm.assume(lpAmount <= totalLpAmount);
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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData;
        bytes memory swapData;

        vm.prank(userPk);
        ale.deleveragePosition(
            dolaRedeemed / 2,
            address(market),
            amountToWithdraw,
            address(0),
            swapData,
            permit,
            abi.encode(address(market), uint(0)),
            dbrData
        );

        assertEq(
            ConvexEscrowV2(userPkEscrow).balance(),
            totalLpAmount - amountToWithdraw
        );
        assertApproxEqAbs(DOLA.balanceOf(userPk), dolaRedeemed / 2, 1);
    }

    function test_deleveragePosition_sellDBR(uint256 lpAmount) public {
        test_leveragePosition();
        uint256 totalLpAmount = ConvexEscrowV2(userPkEscrow).balance();
        vm.assume(lpAmount > 0.0001 ether);
        vm.assume(lpAmount <= totalLpAmount);
        uint256 amountToWithdraw = lpAmount;

        uint256 dolaRedeemed = curvePool.calc_withdraw_one_coin(
            amountToWithdraw,
            0
        );
        uint256 debt = market.debts(address(userPk));
        uint256 amountToRepay;
        if (debt < dolaRedeemed) {
            amountToRepay = debt;
        } else {
            amountToRepay = dolaRedeemed;
        }

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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
            dbr.balanceOf(userPk),
            0,
            0
        ); // sell all DBR
        bytes memory swapData;

        vm.startPrank(userPk);
        dbr.approve(address(ale), dbr.balanceOf(userPk));
        ale.deleveragePosition(
            amountToRepay,
            address(market),
            amountToWithdraw,
            address(0),
            swapData,
            permit,
            abi.encode(address(market), uint(0)),
            dbrData
        );

        assertEq(
            ConvexEscrowV2(userPkEscrow).balance(),
            totalLpAmount - amountToWithdraw
        );
        // Dbrs have also been sold
        if (debt < dolaRedeemed) {
            // Dola left are more than the debt (plus the DBR sold)
            assertGt(DOLA.balanceOf(userPk), dolaRedeemed - amountToRepay);
        } else {
            // only DBR sold
            assertGt(DOLA.balanceOf(userPk), 0);
        }

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
