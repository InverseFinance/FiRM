// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/marketForkTests/MarketForkTest.sol";
import "../DBR.sol";
import "test/mocks/ERC20.sol";
import {ALE} from "../util/ALE.sol";
import {ConfigAddr} from "src/test/ConfigAddr.sol";

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
    function setFlashLoanRate(uint256 rate) external;
}

contract ALEForkTest is MarketForkTest {
    bytes onlyGovUnpause = "Only governance can unpause";
    bytes onlyPauseGuardianOrGov =
        "Only pause guardian or governance can pause";
    bytes exceededLimit = "Exceeded credit limit";
    bytes repaymentGtThanDebt = "Repayment greater than debt";

    error NothingToDeposit();

    MockExchangeProxy exchangeProxy;
    ALE ale;
    address triDBR = 0xC7DE47b9Ca2Fc753D6a2F167D8b3e19c6D18b19a;
    IFlashMinter flash;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 18164420);
        init(crvMarketAddr, crvUsdFeedAddr);

        vm.prank(gov);
        market.pauseBorrows(false);

        vm.startPrank(chair, chair);
        fed.expansion(IMarket(address(market)), 100_000e18);
        vm.stopPrank();

        exchangeProxy = new MockExchangeProxy(
            address(market.oracle()),
            address(DOLA)
        );

        ale = new ALE(address(exchangeProxy), triDBR);
        // ALE setup
        vm.prank(gov);
        DOLA.addMinter(address(ale));

        ale.setMarket(
            address(market),
            address(market.collateral()),
            address(market.collateral()),
            address(0),
            true
        );

        // Allow contract
        vm.startPrank(gov);
        borrowController.allow(address(ale));

        flash = IFlashMinter(address(ale.flash()));
        flash.setFlashLoanRate(0);
        vm.stopPrank();
    }

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

    function test_depositAndLeveragePosition_buyDBR(
        uint256 crvTestAmount
    ) public {
        vm.assume(crvTestAmount < 50000 ether);
        vm.assume(crvTestAmount > 0.000001 ether);
        // We are going to deposit and leverage the position
        //  uint crvTestAmount = 13606;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, crvTestAmount);

        uint maxBorrowAmount = getMaxBorrowAmount(crvTestAmount) / 10; // we want to borrow only 10% of the max amount to exchange

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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
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

        collateral.approve(address(ale), crvTestAmount);

        // We set crvTestAmount as initial deposit
        ale.depositAndLeveragePosition(
            crvTestAmount,
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
            crvTestAmount + convertDolaToCollat(maxBorrowAmount)
        );
        assertEq(DOLA.balanceOf(userPk), 0);

        assertGt(dbr.balanceOf(userPk), (dbrAmount * 98) / 100);
    }

    function test_fail_depositAndLeveragePosition_buyDBR_with_ZERO_deposit()
        public
    {
        // We are going to deposit and leverage the position
        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, crvTestAmount);

        uint maxBorrowAmount = getMaxBorrowAmount(crvTestAmount) / 10; // we want to borrow only 10% of the max amount to exchange

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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
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

        collateral.approve(address(ale), crvTestAmount);

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
        uint crvTestAmount = 1000 ether;
        uint dolaToWithdraw = 100 ether;

        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, crvTestAmount);

        uint maxBorrowAmount = getMaxBorrowAmount(crvTestAmount);

        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        deal(
            address(market.collateral()),
            address(exchangeProxy),
            convertDolaToCollat(maxBorrowAmount + dolaToWithdraw)
        );

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        deposit(crvTestAmount);

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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
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
            crvTestAmount + convertDolaToCollat(maxBorrowAmount)
        );
        assertEq(DOLA.balanceOf(userPk), dolaToWithdraw);

        assertGt(dbr.balanceOf(userPk), (dbrAmount * 98) / 100);
    }

    function test_leveragePosition_buyDBR() public {
        // We are going to deposit some CRV, then leverage the position
        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, crvTestAmount);

        uint maxBorrowAmount = getMaxBorrowAmount(crvTestAmount);

        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        deal(
            address(market.collateral()),
            address(exchangeProxy),
            convertDolaToCollat(maxBorrowAmount)
        );

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        deposit(crvTestAmount);

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

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
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
            crvTestAmount + convertDolaToCollat(maxBorrowAmount)
        );
        assertEq(DOLA.balanceOf(userPk), 0);

        assertGt(dbr.balanceOf(userPk), (dbrAmount * 98) / 100);
    }

    function test_deleveragePosition_sellDBR() public {
        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        // Max Amount borrowable is the one available from collateral amount +
        // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        uint borrowAmount = getMaxBorrowAmount(crvTestAmount) / 2;

        // recharge mocked proxy for swap, we need to swap collateral to DOLA
        vm.startPrank(gov);
        DOLA.mint(
            address(exchangeProxy),
            convertCollatToDola(crvTestAmount / 10)
        );
        vm.stopPrank();

        vm.startPrank(userPk, userPk);
        // CRV deposit and DOLA borrow
        deposit(crvTestAmount);
        market.borrow(borrowAmount);

        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            crvTestAmount
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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
            dbr.balanceOf(userPk),
            0,
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
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // Some collateral has been withdrawn
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            crvTestAmount - amountToWithdraw
        );

        // User still has dola and actually he has more bc he sold his DBRs
        assertGt(DOLA.balanceOf(userPk), borrowAmount);

        assertEq(dbr.balanceOf(userPk), 0);
    }

    function test_deleveragePosition_withdrawALL_sellDBR() public {
        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        // Max Amount borrowable is the one available from collateral amount +
        // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        uint borrowAmount = getMaxBorrowAmount(crvTestAmount) / 2;

        // recharge mocked proxy for swap, we need to swap collateral to DOLA
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), convertCollatToDola(crvTestAmount));
        vm.stopPrank();

        vm.startPrank(userPk, userPk);
        // CRV deposit and DOLA borrow
        deposit(crvTestAmount);
        market.borrow(borrowAmount);

        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            crvTestAmount
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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
            dbr.balanceOf(userPk),
            0,
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
            amountToWithdraw,
            address(exchangeProxy),
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
        assertGt(DOLA.balanceOf(userPk), borrowAmount);

        assertEq(dbr.balanceOf(userPk), 0);

        assertEq(collateral.balanceOf(userPk), amountToWithdraw / 2);
    }

    function test_max_leveragePosition() public {
        // We are going to deposit some CRV, then fully leverage the position

        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        // Max Amount borrowable is the one available from collateral amount +
        // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        uint maxBorrowAmount = getMaxLeverageBorrowAmount(crvTestAmount, 100);

        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        deal(
            address(market.collateral()),
            address(exchangeProxy),
            convertDolaToCollat(maxBorrowAmount)
        );

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        deposit(crvTestAmount);

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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData; // NO DBR

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
            crvTestAmount + convertDolaToCollat(maxBorrowAmount)
        );
        assertEq(DOLA.balanceOf(userPk), 0);
    }

    function test_max_deleveragePosition(uint crvTestAmount) public {
        // We are going to deposit some CRV, then fully leverage the position
        vm.assume(crvTestAmount < 40000 ether);
        vm.assume(crvTestAmount > 0.00000001 ether);

        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        // Max Amount borrowable is the one available from collateral amount +
        // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        uint maxBorrowAmount = getMaxBorrowAmount(crvTestAmount);

        // recharge mocked proxy for swap, we need to swap collateral to DOLA
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), convertCollatToDola(crvTestAmount));
        vm.stopPrank();

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        deposit(crvTestAmount);
        market.borrow(maxBorrowAmount);

        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            crvTestAmount
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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData; // NO DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            collateral,
            amountToWithdraw
        );

        ale.deleveragePosition(
            maxBorrowAmount,
            address(market),
            amountToWithdraw,
            address(exchangeProxy),
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
        assertEq(DOLA.balanceOf(userPk), convertCollatToDola(crvTestAmount));
    }

    function test_max_leverageAndDeleveragePosition(
        uint256 crvTestAmount
    ) public {
        // We are going to deposit some CRV, then fully leverage the position
        // and then fully deleverage it (withdrawing ALL the collateral)
        vm.assume(crvTestAmount < 40000 ether);
        vm.assume(crvTestAmount > 0.00000001 ether);

        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        // Max Amount borrowable is the one available from collateral amount +
        // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        uint maxBorrowAmount = getMaxLeverageBorrowAmount(crvTestAmount, 100);

        // recharge proxy for swap, we need to swap DOLA to collateral
        deal(
            address(market.collateral()),
            address(exchangeProxy),
            convertDolaToCollat(maxBorrowAmount)
        );
        // we also need to mint DOLA into the swap mock bc we will swap ALL the collateral, not only the one added from the leverage
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), convertCollatToDola(crvTestAmount));
        vm.stopPrank();

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        deposit(crvTestAmount);

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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData; // NO DBR

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

        permit = ALE.Permit(block.timestamp, v, r, s);

        swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            collateral,
            amountToWithdraw
        );

        ale.deleveragePosition(
            maxBorrowAmount,
            address(market),
            amountToWithdraw,
            address(exchangeProxy),
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
        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        // recharge mocked proxy for swap, we need to swap collateral to DOLA
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), convertCollatToDola(crvTestAmount));
        vm.stopPrank();

        vm.startPrank(userPk, userPk);
        deposit(crvTestAmount);

        uint256 amountToWithdraw = crvTestAmount;

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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData; // NO DBR

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
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            0
        );
        assertEq(DOLA.balanceOf(userPk), convertCollatToDola(crvTestAmount));
    }

    function test_fail_leveragePosition_if_no_collateral() public {
        // We are going to deposit some CRV, then leverage the position
        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        uint maxBorrowAmount = getMaxBorrowAmount(crvTestAmount);

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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData; // NO DBR

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
        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        // recharge mocked proxy for swap, we need to swap collateral to DOLA
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), convertCollatToDola(crvTestAmount));
        vm.stopPrank();

        vm.startPrank(userPk, userPk);

        uint256 amountToWithdraw = crvTestAmount;

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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData; // NO DBR

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
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );
    }

    function test_fail_max_leveragePosition_buyDBR() public {
        // We are going to deposit some CRV, then fully leverage the position

        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        deal(address(market.collateral()), userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        // Max Amount borrowable is the one available from collateral amount +
        // all redeposited amount as collateral
        uint maxBorrowAmount = getMaxLeverageBorrowAmount(crvTestAmount, 100);

        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        deal(
            address(market.collateral()),
            address(exchangeProxy),
            convertDolaToCollat(maxBorrowAmount)
        );

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        deposit(crvTestAmount);

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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
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
            abi.encodeWithSelector(ALE.NoMarket.selector, fakeMarket)
        );
        ale.setMarket(fakeMarket, address(0), address(0), address(0), true);
    }

    function test_fail_setMarket_WrongCollateral_NoHelper() public {
        ale.updateMarketHelper(address(market), address(0));

        address fakeCollateral = address(0x69);

        vm.expectRevert(
            abi.encodeWithSelector(
                ALE.WrongCollateral.selector,
                address(market),
                fakeCollateral,
                address(0),
                address(0)
            )
        );
        ale.setMarket(
            address(market),
            fakeCollateral,
            address(0),
            address(0),
            true
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ALE.WrongCollateral.selector,
                address(market),
                address(0),
                fakeCollateral,
                address(0)
            )
        );
        ale.setMarket(
            address(market),
            address(0),
            fakeCollateral,
            address(0),
            true
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ALE.WrongCollateral.selector,
                address(market),
                fakeCollateral,
                fakeCollateral,
                address(0)
            )
        );
        ale.setMarket(
            address(market),
            fakeCollateral,
            fakeCollateral,
            address(0),
            true
        );
    }

    function test_fail_setMarket_WrongCollateral_WithHelper() public {
        address fakeCollateral = address(0x69);
        address dummyHelper = address(0x70);
        vm.expectRevert(
            abi.encodeWithSelector(
                ALE.WrongCollateral.selector,
                address(market),
                fakeCollateral,
                address(0),
                dummyHelper
            )
        );
        ale.setMarket(
            address(market),
            fakeCollateral,
            address(0),
            dummyHelper,
            true
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ALE.WrongCollateral.selector,
                address(market),
                address(0),
                fakeCollateral,
                dummyHelper
            )
        );
        ale.setMarket(
            address(market),
            address(0),
            fakeCollateral,
            dummyHelper,
            true
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ALE.WrongCollateral.selector,
                address(market),
                fakeCollateral,
                fakeCollateral,
                dummyHelper
            )
        );
        ale.setMarket(
            address(market),
            fakeCollateral,
            fakeCollateral,
            dummyHelper,
            true
        );
    }

    function test_fail_updateMarketHelper_NoMarket() public {
        address wrongMarket = address(0x69);
        address newHelper = address(0x70);

        vm.expectRevert(
            abi.encodeWithSelector(ALE.MarketNotSet.selector, wrongMarket)
        );
        ale.updateMarketHelper(wrongMarket, newHelper);
    }
}
