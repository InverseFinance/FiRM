// SPDX-License-Identifier: UNLICENSED 
pragma solidity ^0.8.13; 

import "src/interfaces/IMarket.sol";
import "forge-std/Test.sol"; 
import {FrontierV2Test} from "./FrontierV2Test.sol"; 
import {BorrowController} from "src/BorrowController.sol"; 
import "src/DBR.sol"; 
import "src/Fed.sol"; 
import {SimpleERC20Escrow} from "src/escrows/SimpleERC20Escrow.sol"; 
import "src/Market.sol"; 
import {CurveHelper} from "src/util/CurveHelper.sol";
import "src/Oracle.sol"; 
 
import "./mocks/BorrowContract.sol"; 

interface IWeth is IERC20 {
    function approve(address, uint) external;
    function withdraw(uint wad) external;
    function deposit() payable external;
}
//This test must be run as a mainnet fork, to work correctly
contract OffchainHelperTest is FrontierV2Test {

    CurveHelper helper;
    bytes32 borrowHash;
    address userPk;
    uint maxBorrowAmount;
    IWeth weth;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);


        initialize(replenishmentPriceBps, collateralFactorBps, replenishmentIncentiveBps, liquidationBonusBps, callOnDepositCallback);

        vm.warp(block.timestamp - 7 days);

        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), 1_000_000e18);
        vm.stopPrank();
        
        dbr = DolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
        address pool = 0xC7DE47b9Ca2Fc753D6a2F167D8b3e19c6D18b19a;
        helper = new CurveHelper(pool); 
        userPk = vm.addr(1);
        vm.startPrank(gov);
        borrowController = BorrowController(0x44B7895989Bc7886423F06DeAa844D413384b0d6);
        borrowController.allow(address(helper));
        vm.stopPrank();
        
        market = Market(0x63Df5e23Db45a2066508318f172bA45B9CD37035);
        weth = IWeth(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        vm.prank(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
        weth.transfer(userPk, wethTestAmount);
        
        maxBorrowAmount = getMaxBorrowAmount(wethTestAmount);
        vm.startPrank(userPk, userPk);
        weth.approve(address(helper), type(uint).max);
        weth.approve(address(market), type(uint).max);
        DOLA.approve(address(helper), type(uint).max);
        dbr.approve(address(helper), type(uint).max);
        vm.stopPrank();

    }

    function testDepositAndBorrowOnBehalf() public {
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, getBorrowHash(borrowAmount + dolaForDbr, 0));

        vm.startPrank(userPk, userPk);
        assertEq(borrowController.isPriceStale(address(market)), false);
        helper.depositBuyDbrAndBorrowOnBehalf(IMarket(address(market)), wethTestAmount, borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);
        vm.stopPrank();

        assertLt(dbr.balanceOf(userPk), dbrNeeded * 1001 / 1000);
        assertGt(dbr.balanceOf(userPk), dbrNeeded * 999 / 1000);
        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        assertEq(DOLA.balanceOf(userPk), borrowAmount, "failed to borrow DOLA");
    }

    function testDepositNativeEthBuyDbrAndBorrowOnBehalf() public {
        uint duration = 365 days;
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, duration, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, getBorrowHash(borrowAmount + dolaForDbr, 0));
        uint prevBal = weth.balanceOf(userPk);
        vm.deal(userPk, wethTestAmount);
        
        vm.startPrank(userPk, userPk);
        helper.depositNativeEthBuyDbrAndBorrowOnBehalf{value:wethTestAmount}(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);
        vm.stopPrank();

        assertLt(dbr.balanceOf(userPk), dbrNeeded * 101 / 100);
        assertGt(dbr.balanceOf(userPk), dbrNeeded * 99 / 100);
        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk)-prevBal, 0, "failed to deposit weth");
        assertGt(duration, market.debts(userPk) * duration / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), borrowAmount, "failed to borrow DOLA");
    }

    function testBorrowOnBehalf() public {
        uint duration = 365 days;

        vm.startPrank(userPk, userPk);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, getBorrowHash(borrowAmount + dolaForDbr, 0));

        deposit(wethTestAmount);
        vm.stopPrank();
        vm.prank(userPk, userPk);

        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        
        assertGt(duration, market.debts(userPk) * 365 days / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), borrowAmount, "failed to borrow DOLA");
    }

    function testSellDbrAndRepayOnBehalf() public {
        vm.startPrank(userPk, userPk);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, getBorrowHash(borrowAmount + dolaForDbr, 0));

        gibDOLA(userPk, 10000 ether);

        deposit(wethTestAmount);

        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);
        helper.sellDbrAndRepayOnBehalf(IMarket(address(market)), market.debts(userPk), dbr.balanceOf(userPk) / 100,dbr.balanceOf(userPk));
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testSellDbrAndRepayOnBehalf_HigherDBRAmountThanOwned() public {
        vm.startPrank(userPk, userPk);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, getBorrowHash(borrowAmount + dolaForDbr, 0));

        gibDOLA(userPk, 10000 ether);

        deposit(wethTestAmount);

        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);
        helper.sellDbrAndRepayOnBehalf(IMarket(address(market)), market.debts(userPk), dbr.balanceOf(userPk) / 100,dbr.balanceOf(userPk)+1);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testSellDbrAndRepayOnBehalf_EarnMoreFromDBRSellThanRepay() public {
        vm.startPrank(userPk, userPk);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, getBorrowHash(borrowAmount + dolaForDbr, 0));

        gibDOLA(userPk, 10000 ether);

        deposit(wethTestAmount);
        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);
        //Reduce debt to 1
        market.repay(userPk, market.debts(userPk) - 1 ether);
        uint dolaBalanceBefore = DOLA.balanceOf(userPk);
        helper.sellDbrAndRepayOnBehalf(IMarket(address(market)), market.debts(userPk), dbr.balanceOf(userPk) / 100,dbr.balanceOf(userPk));
        vm.stopPrank();

        assertGt(DOLA.balanceOf(userPk), dolaBalanceBefore, "DOLA balance did not increase");
        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testSellDbrRepayAndWithdrawOnBehalf() public {
        gibDOLA(userPk, 10000 ether);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, getBorrowHash(borrowAmount + dolaForDbr, 0));

        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);
        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);

        bytes32 withdrawHash = getWithdrawHash(wethTestAmount, 1);
        (v, r, s) = vm.sign(1, withdrawHash);
        uint pkBalanceBefore = weth.balanceOf(userPk);

        helper.sellDbrRepayAndWithdrawOnBehalf(
            IMarket(address(market)),
            market.debts(userPk),
            dbr.balanceOf(userPk) / 100,
            dbr.balanceOf(userPk), 
            wethTestAmount,
            block.timestamp,
            v, r, s);
        vm.stopPrank();
        
        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 0, "failed to withdraw weth");
        assertEq(weth.balanceOf(userPk) - pkBalanceBefore, wethTestAmount, "failed to withdraw weth");
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testSellDbrRepayAndWithdrawNativeEthOnBehalf() public {
        gibDOLA(userPk, 10000 ether);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, getBorrowHash(borrowAmount + dolaForDbr, 0));

        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);
        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);

        bytes32 withdrawHash = getWithdrawHash(wethTestAmount, 1);
        (v, r, s) = vm.sign(1, withdrawHash);
        
        uint pkBalanceBefore = userPk.balance;
        helper.sellDbrRepayAndWithdrawNativeEthOnBehalf(
            IMarket(address(market)),
            market.debts(userPk),
            dbr.balanceOf(userPk) / 100,
            dbr.balanceOf(userPk), 
            wethTestAmount,
            block.timestamp,
            v, r, s);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 0, "failed to withdraw weth");
        assertEq(userPk.balance - pkBalanceBefore, wethTestAmount, "failed to withdraw weth");
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testWithdrawNativeEthOnBehalf() public {
        bytes32 withdrawHash = getWithdrawHash(wethTestAmount, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, withdrawHash);

        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);
        uint pkBalanceBefore = userPk.balance;
        helper.withdrawNativeEthOnBehalf(IMarket(address(market)), wethTestAmount, block.timestamp, v, r, s);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 0, "failed to withdraw weth");
        assertEq(payable(userPk).balance - pkBalanceBefore, wethTestAmount, "failed to withdraw weth");
    }

    function testDepositNativeEthOnBehalf() public {
        uint prevBal = weth.balanceOf(address(market.predictEscrow(userPk)));
        vm.deal(userPk, wethTestAmount);

        vm.startPrank(userPk, userPk);
        helper.depositNativeEthOnBehalf{value:wethTestAmount}(IMarket(address(market)));
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount+prevBal, "failed to deposit weth");       
    }

    function testRepayAndWithdrawNativeEthOnBehalf() public {
        gibDOLA(userPk, 10000 ether);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, getBorrowHash(borrowAmount + dolaForDbr, 0));


        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);
        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);

        bytes32 withdrawHash = getWithdrawHash(wethTestAmount, 1);
        (v, r, s) = vm.sign(1, withdrawHash);

        uint pkBalanceBefore = userPk.balance;
        helper.repayAndWithdrawNativeEthOnBehalf(
            IMarket(address(market)),
            market.debts(userPk),
            wethTestAmount,
            block.timestamp,
            v, r, s);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 0, "failed to withdraw weth");
        assertEq(userPk.balance - pkBalanceBefore, wethTestAmount, "failed to withdraw weth");
        assertEq(market.debts(userPk), 0, "Did not repay debt");        
    }

    function testDepositNativeEthAndBorrowOnBehalf() public {
        uint borrowAmount = maxBorrowAmount / 2;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, getBorrowHash(borrowAmount, 0));

        vm.startPrank(userPk, userPk);
        weth.withdraw(wethTestAmount);

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 0);
        assertEq(DOLA.balanceOf(userPk), 0);
        helper.depositNativeEthAndBorrowOnBehalf{value:wethTestAmount}(IMarket(address(market)), borrowAmount, block.timestamp, v, r, s);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");       
        assertEq(DOLA.balanceOf(userPk), borrowAmount, "failed to borrow");
        assertEq(market.debts(userPk), DOLA.balanceOf(userPk), "Debt not equal borrow"); 
    }

    function getWithdrawHash(uint amount, uint nonce) public view returns(bytes32){
         bytes32 withdrawHash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                address(helper),
                                userPk,
                                amount,
                                nonce,
                                block.timestamp
                            )
                        )
                    )
                );
        return withdrawHash;
    }

    function getBorrowHash(uint amount, uint nonce) public view returns(bytes32){
        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                address(helper),
                                userPk,
                                amount,
                                nonce,
                                block.timestamp
                            )
                        )
                    )
                );
        return hash;
    }
}
