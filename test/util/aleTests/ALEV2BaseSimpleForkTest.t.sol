// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/marketForkTests/SdeUSDMarketForkTest.t.sol";
import {ALEV2} from "src/util/ALEV2.sol";

contract MockExchangeProxy {
    IOracle oracle;
    IERC20 dola;

    constructor(address _oracle, address _dola) {
        oracle = IOracle(_oracle);
        dola = IERC20(_dola);
    }

    function swapDolaIn(
        IERC20 collateral,
        uint256 dolaAmount
    ) external returns (bool success, bytes memory ret) {
        dola.transferFrom(msg.sender, address(this), dolaAmount);
        uint256 collateralAmount = (dolaAmount * 1e18) /
            oracle.viewPrice(address(collateral), 0);
        collateral.transfer(msg.sender, collateralAmount);
        success = true;
    }

    function swapDolaOut(
        IERC20 collateral,
        uint256 collateralAmount
    ) external returns (bool success, bytes memory ret) {
        collateral.transferFrom(msg.sender, address(this), collateralAmount);
        uint256 dolaAmount = (collateralAmount *
            oracle.viewPrice(address(collateral), 0)) / 1e18;
        dola.transfer(msg.sender, dolaAmount);
        success = true;
    }
}

interface IFlashMinter {
    function setMaxFlashLimit(uint256 limit) external;
}

abstract contract ALEV2BaseSimpleForkTest is MarketForkTest {
    bytes exceededLimit = "Exceeded credit limit";
    bytes repaymentGtThanDebt = "Repayment greater than debt";

    error NothingToDeposit();

    MockExchangeProxy exchangeProxy;
    ALEV2 ale;
    address triDBR = 0xC7DE47b9Ca2Fc753D6a2F167D8b3e19c6D18b19a;
    IFlashMinter flash;

    function getMaxLeverageBorrowAmount(
        uint256 collateralAmount,
        uint256 iterations
    ) internal view returns (uint256) {
        uint256 maxDolaAmount = getMaxBorrowAmount(collateralAmount);
        uint256 totalDola = maxDolaAmount;
        for (uint i = 0; i < iterations; i++) {
            uint256 dolaAmount = getMaxBorrowAmount(
                convertDolaToCollat(maxDolaAmount)
            );
            maxDolaAmount = dolaAmount;
            totalDola += dolaAmount;
        }
        return totalDola;
    }

    function test_depositAndLeveragePosition_buyDBR(uint256 amount) public {
        vm.assume(amount < 50000 ether);
        vm.assume(amount > 0.000001 ether);
        // We are going to deposit and leverage the position
        //  uint amount = 13606;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, amount);

        uint maxBorrowAmount = getMaxBorrowAmount(amount) / 10; // we want to borrow only 10% of the max amount to exchange

        // recharge mocked proxy for swap, we need to swap DOLA to collateral

        deal(
            address(market.collateral()),
            address(exchangeProxy),
            convertDolaToCollat(maxBorrowAmount)
        );

        vm.startPrank(userPk, userPk);

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

        ALEV2.DBRHelper memory dbrData = ALEV2.DBRHelper(
            dolaForDBR,
            (dbrAmount * 98) / 100,
            0
        ); // DBR buy

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            collateral,
            maxBorrowAmount
        );

        assertEq(dbr.balanceOf(userPk), 0);

        collateral.approve(address(ale), amount);

        // We set amount as initial deposit
        ale.depositAndLeveragePosition(
            amount,
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData,
            false
        );

        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            amount + convertDolaToCollat(maxBorrowAmount)
        );
        assertEq(DOLA.balanceOf(userPk), 0);

        assertGt(dbr.balanceOf(userPk), (dbrAmount * 98) / 100);
    }

    function test_fail_depositAndLeveragePosition_buyDBR_with_ZERO_deposit()
        public
    {
        // We are going to deposit and leverage the position
        uint amount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, amount);

        uint maxBorrowAmount = getMaxBorrowAmount(amount) / 10; // we want to borrow only 10% of the max amount to exchange

        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        deal(
            address(market.collateral()),
            address(exchangeProxy),
            convertDolaToCollat(maxBorrowAmount)
        );

        vm.startPrank(userPk, userPk);

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

        ALEV2.DBRHelper memory dbrData = ALEV2.DBRHelper(
            dolaForDBR,
            (dbrAmount * 98) / 100, // DBR buy,
            0 // Dola to borrow and withdraw after leverage
        );

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            collateral,
            maxBorrowAmount
        );

        assertEq(dbr.balanceOf(userPk), 0);

        collateral.approve(address(ale), amount);

        // We try to set 0 as initial deposit, reverts
        vm.expectRevert(NothingToDeposit.selector);
        ale.depositAndLeveragePosition(
            0,
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData,
            false
        );
    }

    function test_leveragePosition_buyDBR_withdrawDOLA() public {
        // We are going to deposit some CRV, then leverage the position
        uint amount = 1000 ether;
        uint dolaToWithdraw = 100 ether;

        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, amount);

        uint maxBorrowAmount = getMaxBorrowAmount(amount);

        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        deal(
            address(market.collateral()),
            address(exchangeProxy),
            convertDolaToCollat(maxBorrowAmount + dolaToWithdraw)
        );

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        deposit(amount);

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
                        maxBorrowAmount + dolaForDBR + dolaToWithdraw,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        ALEV2.DBRHelper memory dbrData = ALEV2.DBRHelper(
            dolaForDBR,
            (dbrAmount * 98) / 100, // DBR buy
            dolaToWithdraw // Dola to borrow and withdraw after leverage
        );

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            collateral,
            maxBorrowAmount
        );

        assertEq(dbr.balanceOf(userPk), 0);

        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            amount + convertDolaToCollat(maxBorrowAmount)
        );
        assertEq(DOLA.balanceOf(userPk), dolaToWithdraw);

        assertGt(dbr.balanceOf(userPk), (dbrAmount * 98) / 100);
    }

    function test_leveragePosition_buyDBR() public {
        // We are going to deposit some CRV, then leverage the position
        uint amount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, amount);

        uint maxBorrowAmount = getMaxBorrowAmount(amount);

        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        deal(
            address(market.collateral()),
            address(exchangeProxy),
            convertDolaToCollat(maxBorrowAmount)
        );

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        deposit(amount);

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

        ALEV2.DBRHelper memory dbrData = ALEV2.DBRHelper(
            dolaForDBR,
            (dbrAmount * 98) / 100, // DBR buy
            0 // Dola to borrow and withdraw after leverage
        );

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            collateral,
            maxBorrowAmount
        );

        assertEq(dbr.balanceOf(userPk), 0);

        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            amount + convertDolaToCollat(maxBorrowAmount)
        );
        assertEq(DOLA.balanceOf(userPk), 0);

        assertGt(dbr.balanceOf(userPk), (dbrAmount * 98) / 100);
    }

    function test_deleveragePosition_sellDBR() public {
        uint amount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, amount);
        gibDBR(userPk, amount);

        // Max Amount borrowable is the one available from collateral amount +
        // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        uint borrowAmount = getMaxBorrowAmount(amount) / 2;

        // recharge mocked proxy for swap, we need to swap collateral to DOLA
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), convertCollatToDola(amount / 10));
        vm.stopPrank();

        vm.startPrank(userPk, userPk);
        // CRV deposit and DOLA borrow
        deposit(amount);
        market.borrow(borrowAmount);

        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            amount
        );
        assertEq(DOLA.balanceOf(userPk), borrowAmount);

        // We are going to withdraw only 1/10 of the collateral to deleverage
        uint256 amountToWithdraw = collateral.balanceOf(
            address(market.predictEscrow(userPk))
        ) / 10;

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
                        0,
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
        ); // Sell DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            collateral,
            amountToWithdraw
        );

        dbr.approve(address(ale), dbr.balanceOf(userPk));

        ale.deleveragePosition(
            convertCollatToDola(amountToWithdraw),
            address(market),
            address(exchangeProxy),
            amountToWithdraw,
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // Some collateral has been withdrawn
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            amount - amountToWithdraw
        );

        // User still has dola and actually he has more bc he sold his DBRs
        assertGt(DOLA.balanceOf(userPk), borrowAmount);

        assertEq(dbr.balanceOf(userPk), 0);
    }

    function test_deleveragePosition_withdrawALL_sellDBR() public {
        uint amount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, amount);
        gibDBR(userPk, amount);

        // Max Amount borrowable is the one available from collateral amount +
        // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        uint borrowAmount = getMaxBorrowAmount(amount) / 2;

        // recharge mocked proxy for swap, we need to swap collateral to DOLA
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), convertCollatToDola(amount));
        vm.stopPrank();

        vm.startPrank(userPk, userPk);
        // CRV deposit and DOLA borrow
        deposit(amount);
        market.borrow(borrowAmount);

        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            amount
        );
        assertEq(DOLA.balanceOf(userPk), borrowAmount);

        // We are going to withdraw ALL the collateral to deleverage
        uint256 amountToWithdraw = collateral.balanceOf(
            address(market.predictEscrow(userPk))
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
                        0,
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
        ); // Sell DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            collateral,
            amountToWithdraw / 2
        );

        dbr.approve(address(ale), dbr.balanceOf(userPk));

        assertEq(collateral.balanceOf(userPk), 0);

        ale.deleveragePosition(
            borrowAmount,
            address(market),
            address(exchangeProxy),
            amountToWithdraw,
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // No collateral left in the escrow
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            0
        );

        // User still has dola and actually he has more bc he sold his DBRs
        assertGt(DOLA.balanceOf(userPk), borrowAmount," Dola balance didn't increase");

        assertEq(dbr.balanceOf(userPk), 0, "DBR were not sold");

        assertEq(collateral.balanceOf(userPk), amountToWithdraw / 2);
    }

    function test_max_leveragePosition() public {
        // We are going to deposit some CRV, then fully leverage the position

        uint amount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, amount);
        gibDBR(userPk, amount);

        // Max Amount borrowable is the one available from collateral amount +
        // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        uint maxBorrowAmount = getMaxLeverageBorrowAmount(amount, 100);

        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        deal(
            address(market.collateral()),
            address(exchangeProxy),
            convertDolaToCollat(maxBorrowAmount)
        );

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        deposit(amount);

        // We are going to leverage the max amount we can borrow
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

        ALEV2.DBRHelper memory dbrData; // NO DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            collateral,
            maxBorrowAmount
        );

        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            amount + convertDolaToCollat(maxBorrowAmount)
        );
        assertEq(DOLA.balanceOf(userPk), 0);
    }

    function test_max_deleveragePosition(uint amount) public {
        // We are going to deposit some CRV, then fully leverage the position
        vm.assume(amount < 40000 ether);
        vm.assume(amount > 0.00000001 ether);

        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, amount);
        gibDBR(userPk, amount);

        // Max Amount borrowable is the one available from collateral amount +
        // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        uint maxBorrowAmount = getMaxBorrowAmount(amount);

        // recharge mocked proxy for swap, we need to swap collateral to DOLA
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), convertCollatToDola(amount));
        vm.stopPrank();

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        deposit(amount);
        market.borrow(maxBorrowAmount);

        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            amount
        );
        assertEq(DOLA.balanceOf(userPk), maxBorrowAmount);

        // We are going to deleverage and withdraw ALL collateral
        uint256 amountToWithdraw = collateral.balanceOf(
            address(market.predictEscrow(userPk))
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
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        ALEV2.DBRHelper memory dbrData; // NO DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            collateral,
            amountToWithdraw
        );

        ale.deleveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            amountToWithdraw,
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // No collateral in the escrow
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            0
        );
        // All collateral is swapped to DOLA and sent to the user
        assertEq(DOLA.balanceOf(userPk), convertCollatToDola(amount));
    }

    function test_max_leverageAndDeleveragePosition(uint256 amount) public {
        // We are going to deposit some CRV, then fully leverage the position
        // and then fully deleverage it (withdrawing ALL the collateral)
        vm.assume(amount < 40000 ether);
        vm.assume(amount > 0.00000001 ether);

        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, amount);
        gibDBR(userPk, amount);

        // Max Amount borrowable is the one available from collateral amount +
        // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        uint maxBorrowAmount = getMaxLeverageBorrowAmount(amount, 100);

        // recharge proxy for swap, we need to swap DOLA to collateral
        deal(
            address(market.collateral()),
            address(exchangeProxy),
            convertDolaToCollat(maxBorrowAmount)
        );
        // we also need to mint DOLA into the swap mock bc we will swap ALL the collateral, not only the one added from the leverage
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), convertCollatToDola(amount));
        vm.stopPrank();

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        deposit(amount);

        // We are going to leverage the max amount we can borrow
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

        ALEV2.DBRHelper memory dbrData; // NO DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            collateral,
            maxBorrowAmount
        );

        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // We now deleverage and withdraw ALL the collateral (which will be swapped for DOLA)
        uint256 amountToWithdraw = collateral.balanceOf(
            address(market.predictEscrow(userPk))
        );

        hash = keccak256(
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
        (v, r, s) = vm.sign(1, hash);

        permit = ALEV2.Permit(block.timestamp, v, r, s);

        swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            collateral,
            amountToWithdraw
        );

        ale.deleveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            amountToWithdraw,
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // We have fully deleveraged the position (no collateral left in the escrow)
        // extra DOLA swapped is sent to the user (after burning)
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            0
        );
        assertEq(
            DOLA.balanceOf(userPk),
            convertCollatToDola(amountToWithdraw) - maxBorrowAmount
        );
    }

    function test_deleveragePosition_if_collateral_no_debt() public {
        uint amount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, amount);
        gibDBR(userPk, amount);

        // recharge mocked proxy for swap, we need to swap collateral to DOLA
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), convertCollatToDola(amount));
        vm.stopPrank();

        vm.startPrank(userPk, userPk);
        deposit(amount);

        uint256 amountToWithdraw = amount;

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
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        ALEV2.DBRHelper memory dbrData; // NO DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            collateral,
            amountToWithdraw
        );

        //  vm.expectRevert(repaymentGtThanDebt);
        // WE can deleverage even if we have no debt, will be swapped to DOLA and sent to the user
        ale.deleveragePosition(
            0,
            address(market),
            address(exchangeProxy),
            amountToWithdraw,
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            0
        );
        assertEq(DOLA.balanceOf(userPk), convertCollatToDola(amount));
    }

    function test_fail_leveragePosition_if_no_collateral() public {
        // We are going to deposit some CRV, then leverage the position
        uint amount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, amount);
        gibDBR(userPk, amount);

        uint maxBorrowAmount = getMaxBorrowAmount(amount);

        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        deal(
            address(market.collateral()),
            address(exchangeProxy),
            convertDolaToCollat(maxBorrowAmount)
        );

        vm.startPrank(userPk, userPk);

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

        ALEV2.DBRHelper memory dbrData; // NO DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            collateral,
            maxBorrowAmount
        );

        vm.expectRevert(exceededLimit);
        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );
    }

    function test_fail_deleveragePosition_if_no_collateral() public {
        uint amount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, amount);
        gibDBR(userPk, amount);

        // recharge mocked proxy for swap, we need to swap collateral to DOLA
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), convertCollatToDola(amount));
        vm.stopPrank();

        vm.startPrank(userPk, userPk);

        uint256 amountToWithdraw = amount;

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
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        ALEV2.DBRHelper memory dbrData; // NO DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            collateral,
            amountToWithdraw
        );

        // Cannot make a repayment without debt
        vm.expectRevert(repaymentGtThanDebt);
        ale.deleveragePosition(
            1 ether,
            address(market),
            address(exchangeProxy),
            amountToWithdraw,
            swapData,
            permit,
            bytes(""),
            dbrData
        );
    }

    function test_fail_max_leveragePosition_buyDBR() public {
        // We are going to deposit some CRV, then fully leverage the position

        uint amount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, amount);
        gibDBR(userPk, amount);

        // Max Amount borrowable is the one available from collateral amount +
        // all redeposited amount as collateral
        uint maxBorrowAmount = getMaxLeverageBorrowAmount(amount, 100);

        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        deal(
            address(market.collateral()),
            address(exchangeProxy),
            convertDolaToCollat(maxBorrowAmount)
        );

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        deposit(amount);

        // Calculate the amount of DOLA needed to buy the DBR to cover for the borrowing period
        (uint256 dolaForDBR, uint256 dbrAmount) = ale
            .approximateDolaAndDbrNeeded(maxBorrowAmount, 365 days, 8);

        // We are going to leverage the max amount we can borrow + the amount needed to buy the DBR
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

        ALEV2.DBRHelper memory dbrData = ALEV2.DBRHelper(
            dolaForDBR,
            (dbrAmount * 99) / 100,
            0
        ); // buy DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            collateral,
            maxBorrowAmount
        );

        // Cannot MAX leverage a position and buying DBR at the same time
        vm.expectRevert(exceededLimit);
        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );
    }

    function test_fail_setMarket_NoMarket() public {
        address fakeMarket = address(0x69);

        vm.expectRevert(
            abi.encodeWithSelector(ALEV2.NoMarket.selector, fakeMarket)
        );
        ale.setMarket(fakeMarket, address(0), address(0), true);
    }

    function test_fail_setMarket_Wrong_BuySellToken_Without_Helper() public {
        address fakeBuySellToken = address(0x69);

        vm.expectRevert(
            abi.encodeWithSelector(
                ALEV2.MarketSetupFailed.selector,
                address(market),
                fakeBuySellToken,
                address(collateral),
                address(0)
            )
        );
        ale.setMarket(address(market), fakeBuySellToken, address(0), true);

        vm.expectRevert();
        ale.setMarket(address(market), address(0), address(0), true);
    }

    function test_fail_updateMarketHelper_NoMarket() public {
        address wrongMarket = address(0x69);
        address newHelper = address(0x70);

        vm.expectRevert(
            abi.encodeWithSelector(ALEV2.MarketNotSet.selector, wrongMarket)
        );
        ale.updateMarketHelper(wrongMarket, newHelper);
    }
}
