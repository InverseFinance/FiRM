// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./FiRMForkTest.sol";
import "../BorrowController.sol";
import "../DBR.sol";
import "../Fed.sol";
import "../Market.sol";
import "../Oracle.sol";
import "./mocks/ERC20.sol";
import "./mocks/BorrowContract.sol";
import {ALE} from "../util/ALE.sol";

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
        uint256 collateralAmount = dolaAmount * 1e18 /
            oracle.viewPrice(address(collateral), 0) ;
        collateral.transfer(msg.sender, collateralAmount);
        bytes memory ret;
        success = true;
    }

    function swapDolaOut(
        IERC20 collateral,
        uint256 collateralAmount
    ) external returns (bool success, bytes memory ret) {
        collateral.transferFrom(msg.sender, address(this), collateralAmount);
        uint256 dolaAmount = collateralAmount *
            oracle.viewPrice(address(collateral), 0) / 1e18; 
        dola.transfer(msg.sender, dolaAmount);
        bytes memory ret;
        success = true;
    }
}

contract ALEForkTest is FiRMForkTest {
    bytes onlyGovUnpause = "Only governance can unpause";
    bytes onlyPauseGuardianOrGov =
        "Only pause guardian or governance can pause";
    bytes exceededLimit = "Exceeded credit limit";
    bytes repaymentGtThanDebt = "Repayment greater than debt";

    BorrowContract borrowContract;
    IERC20 WETH;
    MockExchangeProxy exchangeProxy;
    ALE ale;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        init();

        vm.startPrank(chair, chair);
        fed.expansion(IMarket(address(market)), 100_000e18);
        vm.stopPrank();

        borrowContract = new BorrowContract(
            address(market),
            payable(address(market.collateral()))
        );

        exchangeProxy = new MockExchangeProxy(
            address(market.oracle()),
            address(DOLA)
        );

        ale = new ALE(address(DOLA), address(exchangeProxy));
        // ALE setup
        vm.prank(gov);
        DOLA.addMinter(address(ale));

        ale.setMarket(address(market), address(market.collateral()));
        ale.setMarketCollateral(address(market.collateral()), address(market.collateral()));

        // Allow contract
        vm.prank(gov);
        borrowController.allow(address(ale));
    }

    function test_leveragePosition() public {
        // We are going to deposit some CRV, then leverage the position
        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        gibWeth(userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        uint maxBorrowAmount = getMaxBorrowAmount(crvTestAmount);

        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        gibWeth(address(exchangeProxy), convertDolaToCollat(maxBorrowAmount));  

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        deposit(crvTestAmount);

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

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            collateral,
            maxBorrowAmount
        );

        ale.leveragePosition(
            maxBorrowAmount,
            address(market.collateral()),
            address(exchangeProxy),
            swapData,
            permit,
            bytes("")
        );

        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            crvTestAmount + convertDolaToCollat(maxBorrowAmount) 
        );
        assertEq(DOLA.balanceOf(userPk), 0);
    }

    function test_deleveragePosition() public {
        // We are going to deposit some CRV, then fully leverage the position

        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        gibWeth(userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        // Max Amount borrowable is the one available from collateral amount + 
        // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        uint borrowAmount = getMaxBorrowAmount(crvTestAmount)/2;

        // recharge mocked proxy for swap, we need to swap collateral to DOLA
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), convertCollatToDola(crvTestAmount/10));
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
        uint256 amountToWithdraw = collateral.balanceOf(address(market.predictEscrow(userPk)))/10;

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

        ALE.Permit memory  permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            collateral,
            amountToWithdraw
        );
        
        ale.deleveragePosition(
            convertCollatToDola(amountToWithdraw),
            address(market.collateral()),
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            bytes("")
        );

        // Some collateral has been withdrawn
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            crvTestAmount - amountToWithdraw
        );
        // User still has dola but has some debt repaid
        assertEq(DOLA.balanceOf(userPk), borrowAmount);
    }

    function test_max_leveragePosition() public {
        // We are going to deposit some CRV, then fully leverage the position

        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        gibWeth(userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        // Max Amount borrowable is the one available from collateral amount + 
        // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        uint maxBorrowAmount = getMaxBorrowAmount(crvTestAmount);
        uint extraBorrowAmount = getMaxBorrowAmount(convertDolaToCollat(maxBorrowAmount));
        maxBorrowAmount = maxBorrowAmount + extraBorrowAmount;

        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        gibWeth(address(exchangeProxy), convertDolaToCollat(maxBorrowAmount));  

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

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            collateral,
            maxBorrowAmount
        );

        ale.leveragePosition(
            maxBorrowAmount,
            address(market.collateral()),
            address(exchangeProxy),
            swapData,
            permit,
            bytes("")
        );

        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            crvTestAmount + convertDolaToCollat(maxBorrowAmount) 
        );
        assertEq(DOLA.balanceOf(userPk), 0);
    }

    function test_max_deleveragePosition() public {
        // We are going to deposit some CRV, then fully leverage the position

        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        gibWeth(userPk, crvTestAmount);
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
        uint256 amountToWithdraw = collateral.balanceOf(address(market.predictEscrow(userPk)));

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

        ALE.Permit memory  permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            collateral,
            amountToWithdraw
        );
       
        ale.deleveragePosition(
            maxBorrowAmount,
            address(market.collateral()),
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            bytes("")
        );

        // No collateral in the escrow
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            0
        );
        // All collateral is swapped to DOLA and sent to the user
        assertEq(DOLA.balanceOf(userPk), convertCollatToDola(crvTestAmount));
    }

    function test_max_leverageAndDeleveragePosition() public {
        // We are going to deposit some CRV, then fully leverage the position
        // and then fully deleverage it (withdrawing ALL the collateral)

        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        gibWeth(userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        // Max Amount borrowable is the one available from collateral amount + 
        // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        uint maxBorrowAmount = getMaxBorrowAmount(crvTestAmount);
        uint extraBorrowAmount = getMaxBorrowAmount(convertDolaToCollat(maxBorrowAmount));
        maxBorrowAmount = maxBorrowAmount + extraBorrowAmount;

        // recharge proxy for swap, we need to swap DOLA to collateral
        gibWeth(address(exchangeProxy), convertDolaToCollat(maxBorrowAmount));  
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

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            collateral,
            maxBorrowAmount
        );

        ale.leveragePosition(
            maxBorrowAmount,
            address(market.collateral()),
            address(exchangeProxy),
            swapData,
            permit,
            bytes("")
        );

        // We now deleverage and withdraw ALL the collateral (which will be swapped for DOLA)
        uint256 amountToWithdraw = collateral.balanceOf(address(market.predictEscrow(userPk)));

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
            address(market.collateral()),
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            bytes("")
        );

        // We have fully deleveraged the position (no collateral left in the escrow) 
        // extra DOLA swapped is sent to the user (after burning)
        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            0
        );
        assertEq(DOLA.balanceOf(userPk),convertCollatToDola(amountToWithdraw) - maxBorrowAmount);
    }

    function test_fail_leveragePosition_if_no_collateral() public {
        // We are going to deposit some CRV, then leverage the position
        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        gibWeth(userPk, crvTestAmount);
        gibDBR(userPk, crvTestAmount);

        uint maxBorrowAmount = getMaxBorrowAmount(crvTestAmount);

        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        gibWeth(address(exchangeProxy), convertDolaToCollat(maxBorrowAmount));  

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

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            collateral,
            maxBorrowAmount
        );
       
        vm.expectRevert(exceededLimit);
        ale.leveragePosition(
            maxBorrowAmount,
            address(collateral),
            address(exchangeProxy),
            swapData,
            permit,
            bytes("")
        );

    }

    function test_deleveragePosition_if_collateral_no_debt() public {
        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        gibWeth(userPk, crvTestAmount);
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

        ALE.Permit memory  permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            collateral,
            amountToWithdraw
        );
        
      //  vm.expectRevert(repaymentGtThanDebt);
      // WE can deleverage even if we have no debt, will be swapped to DOLA and sent to the user
        ale.deleveragePosition(
            0,
            address(collateral),
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            bytes("")
        );

        assertEq(
            collateral.balanceOf(address(market.predictEscrow(userPk))),
            0
        );
        assertEq(DOLA.balanceOf(userPk), convertCollatToDola(crvTestAmount));
       
    }

    function test_fail_deleveragePosition_if_no_collateral() public {
        uint crvTestAmount = 1 ether;
        address userPk = vm.addr(1);
        gibWeth(userPk, crvTestAmount);
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

        ALE.Permit memory  permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            collateral,
            amountToWithdraw
        );
        
       
      // Cannot make a repayment without debt
        vm.expectRevert(repaymentGtThanDebt);
        ale.deleveragePosition(
            1 ether,
            address(collateral),
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            bytes("")
        );
    }
}
