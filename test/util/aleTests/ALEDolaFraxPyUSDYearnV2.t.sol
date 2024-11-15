pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelper} from "src/util/CurveDolaLPHelper.sol";
import "test/marketForkTests/DolaFraxPyUSDYearnV2MarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALE} from "src/util/ALE.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";

interface IFlashMinter {
    function setMaxFlashLimit(uint256 _maxFlashLimit) external;

    function flashFee(
        address _token,
        uint256 _value
    ) external view returns (uint256);
}

contract ALEDolaFraxPyUSDYearnV2Test is DolaFraxPyUSDYearnV2MarketForkTest {
    ALE ale;
    IFlashMinter flash;
    address userPk = vm.addr(1);
    CurveDolaLPHelper helper;
    address userPkEscrow;
    IYearnVaultV2 vault = IYearnVaultV2(yearn);

    function setUp() public override {
        super.setUp();

        helper = CurveDolaLPHelper(curveDolaLPHelperAddr);

        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(
            address(market),
            address(dolaFraxPyUSD),
            0,
            2,
            address(yearn)
        );
        ale = new ALE(address(0), triDBRAddr);
        ale.setMarket(address(market), address(DOLA), address(helper), false);

        flash = IFlashMinter(address(ale.flash()));
        flash.setMaxFlashLimit(1000000 ether);
        DOLA.addMinter(address(flash));
        borrowController.allow(address(ale));
        vm.stopPrank();
        userPkEscrow = address(market.predictEscrow(userPk));
    }

    function test_leveragePosition() public {
        vm.prank(gov);
        DOLA.mint(userPk, 1000000 ether);

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), 1000000 ether);
        helper.transformToCollateralAndDeposit(
            1000000 ether,
            userPk,
            abi.encode(address(market), 0)
        );
        vm.stopPrank();

        uint256 sharesAmount = vault.balanceOf(userPkEscrow);
        gibDBR(userPk, 20000 ether);

        uint maxBorrowAmount = _getMaxBorrowAmount(sharesAmount);

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
        uint256 lpAmountAdded = dolaFraxPyUSD.calc_token_amount(amounts, true);
        uint256 sharesAdded = YearnVaultV2Helper.assetToCollateral(
            vault,
            lpAmountAdded
        );
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
        assertEq(vault.balanceOf(userPkEscrow), sharesAmount + sharesAdded);
    }

    function test_leveragePosition_buyDBR(uint256 amount) public {
        vm.assume(amount < 1000000 ether);
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

        uint256 sharesAmount = vault.balanceOf(userPkEscrow);

        uint maxBorrowAmount = _getMaxBorrowAmount(sharesAmount);

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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData;

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
            dolaForDBR,
            (dbrAmount * 95) / 100,
            0
        );

        uint256[2] memory amounts = [maxBorrowAmount, 0];

        uint256 sharesAdded = YearnVaultV2Helper.assetToCollateral(
            vault,
            dolaFraxPyUSD.calc_token_amount(amounts, true)
        );
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
        assertEq(vault.balanceOf(userPkEscrow), sharesAmount + sharesAdded);
        assertGt(dbr.balanceOf(userPk), (dbrAmount * 95) / 100);
    }

    function test_depositAndLeveragePosition_DOLA(uint256 amount) public {
        vm.assume(amount < 1000000 ether);
        vm.assume(amount > 0.001 ether);
        vm.prank(gov);
        uint256 initialDolaDeposit = amount / 10;
        DOLA.mint(userPk, amount);

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), amount - initialDolaDeposit);
        helper.transformToCollateralAndDeposit(
            amount - initialDolaDeposit,
            userPk,
            abi.encode(address(market), 0)
        );
        vm.stopPrank();

        uint256 sharesAmount = vault.balanceOf(userPkEscrow);
        gibDBR(userPk, 20000 ether);

        uint maxBorrowAmount = _getMaxBorrowAmount(sharesAmount);

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
        uint256 lpAmountAdded = dolaFraxPyUSD.calc_token_amount(amounts, true);
        uint256 sharesAdded = YearnVaultV2Helper.assetToCollateral(
            vault,
            lpAmountAdded
        );
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

        assertEq(DOLA.balanceOf(userPk), 0, "dola lp balance");
        assertEq(vault.balanceOf(userPkEscrow), sharesAmount + sharesAdded);
    }

    function test_depositAndLeveragePosition_LP(uint256 amount) public {
        vm.assume(amount < 1000000 ether);
        vm.assume(amount > 0.001 ether);
        vm.prank(gov);
        DOLA.mint(userPk, amount);
        uint256 initialDolaAmount = amount / 10;
        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), amount);
        uint256 initialSharesAmount = helper.transformToCollateral(
            initialDolaAmount,
            abi.encode(address(market), 0)
        );
        helper.transformToCollateralAndDeposit(
            amount - initialDolaAmount,
            userPk,
            abi.encode(address(market), 0)
        );
        vm.stopPrank();

        uint256 sharesAmount = vault.balanceOf(userPkEscrow);
        gibDBR(userPk, 20000 ether);

        uint maxBorrowAmount = _getMaxBorrowAmount(sharesAmount);

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
        uint256 lpAmountAdded = dolaFraxPyUSD.calc_token_amount(amounts, true);
        uint256 sharesAdded = YearnVaultV2Helper.assetToCollateral(
            vault,
            lpAmountAdded
        );
        vm.startPrank(userPk);
        IERC20(address(vault)).approve(address(ale), initialSharesAmount);
        ale.depositAndLeveragePosition(
            initialSharesAmount,
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
            vault.balanceOf(userPkEscrow),
            sharesAmount + sharesAdded + initialSharesAmount
        );
    }

    function test_deleveragePosition(uint sharesAmount) public {
        test_leveragePosition();
        uint256 totalSharesAmount = vault.balanceOf(userPkEscrow);
        vm.assume(sharesAmount > 0.0001 ether);
        vm.assume(sharesAmount <= totalSharesAmount);
        uint256 amountToWithdraw = sharesAmount / 2;

        uint256 dolaRedeemed = dolaFraxPyUSD.calc_withdraw_one_coin(
            YearnVaultV2Helper.collateralToAsset(vault, amountToWithdraw),
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
            vault.balanceOf(userPkEscrow),
            totalSharesAmount - amountToWithdraw,
            "sharesAmount"
        );
        //assertEq(sharesAmount, amountToWithdraw);
        assertApproxEqAbs(
            DOLA.balanceOf(userPk),
            dolaRedeemed / 2,
            1,
            "dolaBalance"
        );
    }

    function test_deleveragePosition_Yearn_Leftover() public {
        test_leveragePosition();
        // No leftover
        assertEq(vault.balanceOf(address(helper)), 0);

        // Add some Yearn to simulate a leftover on the helper
        vm.prank(gov);
        DOLA.mint(userPk, 1000 ether);

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), 1000 ether);
        uint256 yearnLeftover = helper.transformToCollateral(
            1000 ether,
            address(helper),
            abi.encode(address(market), 0)
        );
        vm.stopPrank();

        // Leftover is in helper
        assertEq(vault.balanceOf(address(helper)), yearnLeftover);
        assertEq(vault.balanceOf(userPk), 0);

        uint256 sharesAmount = vault.balanceOf(userPkEscrow);
        uint256 amountToWithdraw = sharesAmount / 2;

        uint256 dolaRedeemed = dolaFraxPyUSD.calc_withdraw_one_coin(
            YearnVaultV2Helper.collateralToAsset(vault, amountToWithdraw),
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
            vault.balanceOf(userPkEscrow),
            sharesAmount - amountToWithdraw
        );
        assertApproxEqAbs(DOLA.balanceOf(userPk), dolaRedeemed / 2, 1);

        // Leftover is in user balance
        assertEq(vault.balanceOf(address(helper)), 0);
        assertEq(vault.balanceOf(userPk), yearnLeftover);
    }

    function test_deleveragePosition_sellDBR() public {
        test_leveragePosition();
        uint256 sharesAmount = vault.balanceOf(userPkEscrow);
        uint256 amountToWithdraw = sharesAmount / 2;

        uint256 dolaRedeemed = dolaFraxPyUSD.calc_withdraw_one_coin(
            YearnVaultV2Helper.collateralToAsset(vault, amountToWithdraw),
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
            debt,
            address(market),
            amountToWithdraw,
            address(0),
            swapData,
            permit,
            abi.encode(address(market), uint(0)),
            dbrData
        );

        assertEq(
            vault.balanceOf(userPkEscrow),
            sharesAmount - amountToWithdraw
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
                oracle.viewPrice(address(yearn), 0) *
                market.collateralFactorBps()) /
            10_000 /
            1e18;
    }
}
