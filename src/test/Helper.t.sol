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


//This test must be run as a mainnet fork, to work correctly
contract HelperTest is FrontierV2Test {

    BalancerHelper helper;
    BorrowContract borrowContract;

    function setUp() public {
        initialize(replenishmentPriceBps, collateralFactorBps, replenishmentIncentiveBps, liquidationBonusBps, callOnDepositCallback);

        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), 1_000_000e18);
        vm.stopPrank();
        
        dbr = DolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
        borrowContract = new BorrowContract(address(market), payable(address(WETH)));
        address vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
        bytes32 poolId = 0x445494f823f3483ee62d854ebc9f58d5b9972a25000200000000000000000415;
        helper = new BalancerHelper(address(DOLA), address(dbr), poolId, vault); 
        vm.startPrank(gov);
        borrowController.allow(address(helper));
        vm.stopPrank();
    }

    function testDepositAndBorrowOnBehalf() public {
        address userPk = vm.addr(1);
        uint duration = 365 days;
        gibWeth(userPk, wethTestAmount);

        vm.startPrank(userPk, userPk);
        uint maxBorrowAmount = getMaxBorrowAmount(wethTestAmount);
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
                                maxBorrowAmount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        vm.stopPrank();
        vm.startPrank(userPk, userPk);
        WETH.approve(address(helper), type(uint).max);
        helper.depositAndBorrowOnBehalf(IMarket(address(market)),wethTestAmount, maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);
        vm.stopPrank();

        emit log_named_uint("DBR balance", dbr.balanceOf(userPk));
        emit log_named_uint("Dola balance", DOLA.balanceOf(userPk));
        emit log_named_uint("Debt", market.debts(userPk));

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), wethTestAmount, "failed to deposit WETH");
        assertEq(WETH.balanceOf(userPk), 0, "failed to deposit WETH");
        
        assertGt(duration, market.debts(userPk) * 365 days / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), maxBorrowAmount / 2, "failed to borrow DOLA");
    }

    function testBorrowOnBehalf() public {
        address userPk = vm.addr(1);
        uint duration = 365 days;
        gibWeth(userPk, wethTestAmount);

        vm.startPrank(userPk, userPk);
        uint maxBorrowAmount = getMaxBorrowAmount(wethTestAmount);
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
                                maxBorrowAmount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(wethTestAmount);
        vm.stopPrank();
        vm.prank(userPk, userPk);
        helper.borrowOnBehalf(IMarket(address(market)), maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);

        emit log_named_uint("DBR balance", dbr.balanceOf(userPk));
        emit log_named_uint("Dola balance", DOLA.balanceOf(userPk));
        emit log_named_uint("Debt", market.debts(userPk));

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), wethTestAmount, "failed to deposit WETH");
        assertEq(WETH.balanceOf(userPk), 0, "failed to deposit WETH");
        
        assertGt(duration, market.debts(userPk) * 365 days / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), maxBorrowAmount / 2, "failed to borrow DOLA");
    }

    function testSellDbrRepayAndWithdrawOnBehalf() public {
        address userPk = vm.addr(1);
        uint duration = 365 days;
        gibWeth(userPk, wethTestAmount);

        vm.startPrank(userPk, userPk);
        uint maxBorrowAmount = getMaxBorrowAmount(wethTestAmount);
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
                                maxBorrowAmount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(wethTestAmount);
        vm.stopPrank();
        vm.prank(userPk, userPk);
        helper.borrowOnBehalf(IMarket(address(market)), maxBorrowAmount / 2, maxBorrowAmount, duration, block.timestamp, v, r, s);

        emit log_named_uint("DBR balance", dbr.balanceOf(userPk));
        emit log_named_uint("Dola balance", DOLA.balanceOf(userPk));
        emit log_named_uint("Debt", market.debts(userPk));

        assertEq(WETH.balanceOf(address(market.escrows(userPk))), wethTestAmount, "failed to deposit WETH");
        assertEq(WETH.balanceOf(userPk), 0, "failed to deposit WETH");
        
        assertGt(duration, market.debts(userPk) * 365 days / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), maxBorrowAmount / 2, "failed to borrow DOLA");
    }



}
