// SPDX-License-Identifier: UNLICENSED 
pragma solidity ^0.8.13; 

import "../interfaces/IMarket.sol";
import "forge-std/Test.sol"; 
import {FrontierV2Test} from "./FrontierV2Test.sol"; 
import "../BorrowController.sol"; 
import "../DBR.sol"; 
import "../Fed.sol"; 
import {SimpleERC20Escrow} from "../escrows/SimpleERC20Escrow.sol"; 
import "../Market.sol"; 
import {BalancerHelper} from "../util/BalancerHelper.sol";
import "../Oracle.sol"; 
 
import "./mocks/ERC20.sol"; 
import "./mocks/BorrowContract.sol"; 
import {EthFeed} from "./mocks/EthFeed.sol"; 

interface IWeth is IERC20 {
    function approve(address, uint) external;
    function withdraw(uint wad) external;
    function deposit() payable external;
}
//This test must be run as a mainnet fork, to work correctly
contract HelperTest is FrontierV2Test {

    BalancerHelper helper;
    bytes32 borrowHash;
    address userPk;
    uint maxBorrowAmount;
    IWeth weth;

    function setUp() public {
        initialize(replenishmentPriceBps, collateralFactorBps, replenishmentIncentiveBps, liquidationBonusBps, callOnDepositCallback);

        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), 1_000_000e18);
        vm.stopPrank();
        
        dbr = DolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
        address vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        bytes32 poolId = 0x445494f823f3483ee62d854ebc9f58d5b9972a25000200000000000000000415;
        //helper = new BalancerHelper(poolId, vault); 
        helper = BalancerHelper(payable(0x6c31147E995074eA6aaD2Fbe95060B0Aef7363E1));
        userPk = vm.addr(1);
        vm.startPrank(gov);
        borrowController = BorrowController(0x20C7349f6D6A746a25e66f7c235E96DAC880bc0D);
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
        borrowHash = getBorrowHash(maxBorrowAmount, 0);

    }

    function testDepositAndBorrowOnBehalf() public {
        uint duration = 365 days;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, borrowHash);

        vm.startPrank(userPk, userPk);
        helper.depositBuyDbrAndBorrowOnBehalf(IMarket(address(market)), wethTestAmount, maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        assertGt(duration, market.debts(userPk) * 365 days / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), maxBorrowAmount / 2, "failed to borrow DOLA");
    }

    function testDepositAndBorrowOnBehalfFullOnChain() public {
        uint duration = 365 days;

        wethTestAmount = 1 ether / 100;
        maxBorrowAmount = 106 ether / 100;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, getBorrowHash(maxBorrowAmount, 0));


        vm.startPrank(userPk, userPk);
        helper.depositBuyDbrAndBorrowOnBehalf(IMarket(address(market)), 1 ether, 1 ether, maxBorrowAmount, duration, block.timestamp, v, r, s);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 1 ether, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        
        assertGt(duration, market.debts(userPk) * 365 days / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), 1 ether, "failed to borrow DOLA");
    }

    function testDepositNativeEthBuyDbrAndBorrowOnBehalf() public {
        uint duration = 365 days;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, borrowHash);
        uint prevBal = weth.balanceOf(userPk);
        vm.deal(userPk, wethTestAmount);
        
        vm.startPrank(userPk, userPk);
        helper.depositNativeEthBuyDbrAndBorrowOnBehalf{value:wethTestAmount}(IMarket(address(market)), maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk)-prevBal, 0, "failed to deposit weth");
        assertGt(duration, market.debts(userPk) * 365 days / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), maxBorrowAmount / 2, "failed to borrow DOLA");
    }

    function testBorrowOnBehalf() public {
        uint duration = 365 days;

        vm.startPrank(userPk, userPk);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, borrowHash);

        deposit(wethTestAmount);
        vm.stopPrank();
        vm.prank(userPk, userPk);

        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        
        assertGt(duration, market.debts(userPk) * 365 days / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), maxBorrowAmount / 2, "failed to borrow DOLA");
    }

    function testSellDbrAndRepayOnBehalf() public {
        uint duration = 365 days;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, borrowHash);
        gibDOLA(userPk, 10000 ether);

        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);

        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);
        helper.sellDbrAndRepayOnBehalf(IMarket(address(market)), market.debts(userPk), dbr.balanceOf(userPk) / 100,dbr.balanceOf(userPk));
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testSellDbrRepayAndWithdrawOnBehalf() public {
        uint duration = 365 days;
        gibDOLA(userPk, 10000 ether);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, borrowHash);

        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);
        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);

        bytes32 withdrawHash = getWithdrawHash(wethTestAmount, 1);
        (v, r, s) = vm.sign(1, withdrawHash);

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
        assertEq(weth.balanceOf(userPk), wethTestAmount, "failed to withdraw weth");
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testSellDbrRepayAndWithdrawNativeEthOnBehalf() public {
        uint duration = 365 days;
        gibDOLA(userPk, 10000 ether);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, borrowHash);

        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);
        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);

        bytes32 withdrawHash = getWithdrawHash(wethTestAmount, 1);
        (v, r, s) = vm.sign(1, withdrawHash);

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
        assertEq(userPk.balance, wethTestAmount, "failed to withdraw weth");
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testWithdrawNativeEthOnBehalf() public {
        bytes32 withdrawHash = getWithdrawHash(wethTestAmount, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, withdrawHash);

        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);
        helper.withdrawNativeEthOnBehalf(IMarket(address(market)), wethTestAmount, block.timestamp, v, r, s);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 0, "failed to withdraw weth");
        assertEq(payable(userPk).balance, wethTestAmount, "failed to withdraw weth");
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
        uint duration = 365 days;
        gibDOLA(userPk, 10000 ether);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, borrowHash);

        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);
        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);

        bytes32 withdrawHash = getWithdrawHash(wethTestAmount, 1);
        (v, r, s) = vm.sign(1, withdrawHash);

        helper.repayAndWithdrawNativeEthOnBehalf(
            IMarket(address(market)),
            market.debts(userPk),
            wethTestAmount,
            block.timestamp,
            v, r, s);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 0, "failed to withdraw weth");
        assertEq(userPk.balance, wethTestAmount, "failed to withdraw weth");
        assertEq(market.debts(userPk), 0, "Did not repay debt");        
    }

    function testDepositNativeEthAndBorrowOnBehalf() public {
        borrowHash = getBorrowHash(maxBorrowAmount, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, borrowHash);

        vm.startPrank(userPk, userPk);
        weth.withdraw(wethTestAmount);

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 0);
        assertEq(DOLA.balanceOf(userPk), 0);
        helper.depositNativeEthAndBorrowOnBehalf{value:wethTestAmount}(IMarket(address(market)), maxBorrowAmount, block.timestamp, v, r, s);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");       
        assertEq(DOLA.balanceOf(userPk), maxBorrowAmount, "failed to borrow");
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
