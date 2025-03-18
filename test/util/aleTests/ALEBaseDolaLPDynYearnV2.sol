pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {CurveDolaLPHelperDynamic} from "src/util/CurveDolaLPHelperDynamic.sol";
import "test/marketForkTests/MarketForkTest.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALEV2} from "src/util/ALEV2.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";

interface IFlashMinter {
    function setMaxFlashLimit(uint256 _maxFlashLimit) external;

    function flashFee(
        address _token,
        uint256 _value
    ) external view returns (uint256);
}
interface ICurve {
    function add_liquidity(
        uint256[] memory _amounts,
        uint256 _min_mint_amount
    ) external returns (uint256);
}
abstract contract ALEBaseDolaLPDynYearnV2Test is MarketForkTest {
    ALEV2 ale;
    IFlashMinter flash;
    address userPk = vm.addr(1);
    CurveDolaLPHelperDynamic helper;
    address userPkEscrow;
    IYearnVaultV2 vault;
    ICurvePool curvePool;

    function test_leveragePosition() public {
        vm.prank(gov);
        DOLA.mint(userPk, 1000000 ether);

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), 1000000 ether);
        helper.convertToCollateralAndDeposit(
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

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        bytes memory swapData;

        ALEV2.DBRHelper memory dbrData;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = maxBorrowAmount;
        uint256 lpAmountAdded = curvePool.calc_token_amount(amounts, true);
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

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        bytes memory swapData;

        ALEV2.DBRHelper memory dbrData = ALEV2.DBRHelper(
            dolaForDBR,
            (dbrAmount * 98) / 100,
            0
        );

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = maxBorrowAmount;
        uint256 sharesAdded = YearnVaultV2Helper.assetToCollateral(
            vault,
            curvePool.calc_token_amount(amounts, true)
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
        assertGt(dbr.balanceOf(userPk), (dbrAmount * 98) / 100);
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

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        bytes memory swapData;

        ALEV2.DBRHelper memory dbrData;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = maxBorrowAmount + initialDolaDeposit;
        uint256 lpAmountAdded = curvePool.calc_token_amount(amounts, true);
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

        assertEq(DOLA.balanceOf(userPk), 0);
        assertEq(vault.balanceOf(userPkEscrow), sharesAmount + sharesAdded);
    }

    function test_depositAndLeveragePosition_LP() public {
        vm.prank(gov);
        DOLA.mint(userPk, 11000 ether);

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), 11000 ether);
        uint256 initialSharesAmount = helper.convertToCollateral(
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

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        bytes memory swapData;

        ALEV2.DBRHelper memory dbrData;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = maxBorrowAmount;
        uint256 lpAmountAdded = curvePool.calc_token_amount(amounts, true);
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
        vm.assume(sharesAmount > 0.00001 ether);
        vm.assume(sharesAmount <= totalSharesAmount);
        uint256 amountToWithdraw = sharesAmount / 2;

        uint256 dolaRedeemed = curvePool.calc_withdraw_one_coin(
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
            vault.balanceOf(userPkEscrow),
            totalSharesAmount - amountToWithdraw
        );
        assertApproxEqAbs(DOLA.balanceOf(userPk), dolaRedeemed / 2, 1);
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
        uint256 yearnLeftover = helper.convertToCollateral(
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

        uint256 dolaRedeemed = curvePool.calc_withdraw_one_coin(
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

        uint256 dolaRedeemed = curvePool.calc_withdraw_one_coin(
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
                oracle.viewPrice(address(vault), 0) *
                market.collateralFactorBps()) /
            10_000 /
            1e18;
    }
}
