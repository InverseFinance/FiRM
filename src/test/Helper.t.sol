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
import "./mocks/WETH9.sol"; 
import "./mocks/BorrowContract.sol"; 
import {EthFeed} from "./mocks/EthFeed.sol"; 

interface IWeth is IERC20 {
    function approve(address, uint) external;
}
//This test must be run as a mainnet fork, to work correctly
contract HelperTest is FrontierV2Test {

    BalancerHelper helper;
    bytes32 borrowHash;
    address userPk;
    uint maxBorrowAmount;

    function setUp() public {
        initialize(replenishmentPriceBps, collateralFactorBps, replenishmentIncentiveBps, liquidationBonusBps, callOnDepositCallback);

        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), 1_000_000e18);
        vm.stopPrank();
        
        dbr = DolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
        address vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        bytes32 poolId = 0x445494f823f3483ee62d854ebc9f58d5b9972a25000200000000000000000415;
        helper = new BalancerHelper(address(DOLA), address(dbr), address(WETH), poolId, vault); 
        userPk = vm.addr(1);
        vm.startPrank(gov);
        borrowController.allow(address(helper));
        vm.stopPrank();
        
        gibWeth(userPk, wethTestAmount);
        vm.prank(userPk);
        maxBorrowAmount = getMaxBorrowAmount(wethTestAmount);

        borrowHash = keccak256(
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
                                maxBorrowAmount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );

    }

    function testDepositAndBorrowOnBehalf() public {
        uint duration = 365 days;

        vm.startPrank(userPk, userPk);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, borrowHash);

        vm.stopPrank();
        vm.startPrank(userPk, userPk);
        WETH.approve(address(helper), type(uint).max);
        helper.depositAndBorrowOnBehalf(IMarket(address(market)), wethTestAmount, maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);
        vm.stopPrank();

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), wethTestAmount, "failed to deposit WETH");
        assertEq(WETH.balanceOf(userPk), 0, "failed to deposit WETH");
        
        assertGt(duration, market.debts(userPk) * 365 days / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), maxBorrowAmount / 2, "failed to borrow DOLA");
    }

    function testDepositAndBorrowOnBehalf2() public {
        uint duration = 365 days;

        wethTestAmount = 1 ether / 100;
        maxBorrowAmount = 106 ether / 100;
        market = Market(0x63Df5e23Db45a2066508318f172bA45B9CD37035);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, getBorrowHash(maxBorrowAmount, 0));
        IWeth weth = IWeth(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        vm.prank(0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E);
        weth.transfer(userPk, 1 ether);
        borrowController = BorrowController(0x20C7349f6D6A746a25e66f7c235E96DAC880bc0D);
        vm.prank(gov);
        borrowController.allow(address(helper));
        vm.startPrank(userPk, userPk);
        weth.approve(address(helper), type(uint).max);
        (uint dolaNeeded, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(1 ether, duration, 8);
        emit log_named_uint("Dola needed", dolaNeeded);
        emit log_named_uint("Dbr needed", dbrNeeded);
        helper.depositAndBorrowOnBehalf(IMarket(address(market)), wethTestAmount, 1 ether, maxBorrowAmount, duration, block.timestamp, v, r, s);
        vm.stopPrank();

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), wethTestAmount, "failed to deposit WETH");
        assertEq(WETH.balanceOf(userPk), 0, "failed to deposit WETH");
        
        assertGt(duration, market.debts(userPk) * 365 days / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), 1 ether, "failed to borrow DOLA");
    }

    function testDepositNativeEthAndBorrowOnBehalf() public {
        uint duration = 365 days;

        vm.startPrank(userPk, userPk);
        WETH.withdraw(wethTestAmount);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, borrowHash);
        
        helper.depositNativeEthAndBorrowOnBehalf{value:wethTestAmount}(IMarket(address(market)), maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);
        vm.stopPrank();

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), wethTestAmount, "failed to deposit WETH");
        assertEq(WETH.balanceOf(userPk), 0, "failed to deposit WETH");
        
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

        helper.borrowOnBehalf(IMarket(address(market)), maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), wethTestAmount, "failed to deposit WETH");
        assertEq(WETH.balanceOf(userPk), 0, "failed to deposit WETH");
        
        assertGt(duration, market.debts(userPk) * 365 days / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), maxBorrowAmount / 2, "failed to borrow DOLA");
    }

    function testSellDbrAndRepayOnBehalf() public {
        uint duration = 365 days;
        gibDOLA(userPk, 10000 ether);

        vm.startPrank(userPk, userPk);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, borrowHash);

        deposit(wethTestAmount);
        vm.stopPrank();
        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), type(uint).max);
        dbr.approve(address(helper), type(uint).max);
        helper.borrowOnBehalf(IMarket(address(market)), maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);
        helper.sellDbrAndRepayOnBehalf(IMarket(address(market)), market.debts(userPk), dbr.balanceOf(userPk) / 100,dbr.balanceOf(userPk));
        vm.stopPrank();

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), wethTestAmount, "failed to deposit WETH");
        assertEq(WETH.balanceOf(userPk), 0, "failed to deposit WETH");
        
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testSellDbrRepayAndWithdrawOnBehalf() public {
        uint duration = 365 days;
        gibDOLA(userPk, 10000 ether);

        vm.startPrank(userPk, userPk);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, borrowHash);
        deposit(wethTestAmount);
        vm.stopPrank();
        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), type(uint).max);
        dbr.approve(address(helper), type(uint).max);
        helper.borrowOnBehalf(IMarket(address(market)), maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);

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

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), 0, "failed to withdraw WETH");
        assertEq(WETH.balanceOf(userPk), wethTestAmount, "failed to withdraw WETH");
        
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testSellDbrRepayAndWithdrawNativeEthOnBehalf() public {
        uint duration = 365 days;
        gibDOLA(userPk, 10000 ether);

        vm.startPrank(userPk, userPk);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, borrowHash);
        deposit(wethTestAmount);
        vm.stopPrank();
        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), type(uint).max);
        dbr.approve(address(helper), type(uint).max);
        helper.borrowOnBehalf(IMarket(address(market)), maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);

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

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), 0, "failed to withdraw WETH");
        assertEq(userPk.balance, wethTestAmount, "failed to withdraw WETH");
        
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testWithdrawNativeEthOnBehalf() public {
        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);
        
        bytes32 withdrawHash = getWithdrawHash(wethTestAmount, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, withdrawHash);

        helper.withdrawNativeEthOnBehalf(IMarket(address(market)), wethTestAmount, block.timestamp, v, r, s);
        vm.stopPrank();

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), 0, "failed to withdraw WETH");
        assertEq(payable(userPk).balance, wethTestAmount, "failed to withdraw WETH");
    }

    function testDepositNativeEthOnBehalf() public {
        vm.startPrank(userPk, userPk);
        WETH.withdraw(wethTestAmount);

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), 0);
        helper.depositNativeEthOnBehalf{value:wethTestAmount}(IMarket(address(market)));
        vm.stopPrank();

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), wethTestAmount, "failed to deposit WETH");       
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
