// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";
import {SimpleERC20Escrow} from "src/escrows/SimpleERC20Escrow.sol";
import {SFraxPriceFeed} from "src/feeds/SFraxPriceFeed.sol";
import {VaultHelper} from "src/escrows/VaultHelper.sol";

contract SFraxMarketForkTest is MarketBaseForkTest {
    SimpleERC20Escrow escrow;
    SFraxPriceFeed sFraxFeed;
    IERC20 frax = IERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    IERC20 sFrax = IERC20(0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32);
    VaultHelper helper;
    address fraxToUsd = 0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        
        escrow = new SimpleERC20Escrow();
        sFraxFeed = new SFraxPriceFeed();

        Market market = new Market(
            gov,
            lender,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbr)),
            sFrax,
            IOracle(address(oracle)),
            5000,
            5000,
            1000,
            true
        );

        _advancedInit(address(market), address(sFraxFeed), true);

        // Setup VaultHelper
        helper = new VaultHelper(address(sFrax), address(market), address(frax));
    }

    function test_wrapAndDeposit(uint initAmount) public { 
        vm.assume(initAmount > 3);
        vm.assume(initAmount < 10000000000000 ether);
        deal(address(frax), user, initAmount, true);
        
        vm.startPrank(user);
        frax.approve(address(helper), type(uint).max);
        helper.wrapAndDeposit(user, initAmount);
        assertEq(frax.balanceOf(user), 0);
    }

    function test_withdrawAndUnwrap(uint initAmount) public {
        vm.assume(initAmount > 3);
        vm.assume(initAmount < 10000000000000 ether);
   
        address userPk = vm.addr(1);
        deal(address(frax), userPk, initAmount, true);
        
        vm.startPrank(userPk);
        frax.approve(address(helper), type(uint).max);
        helper.wrapAndDeposit(userPk, initAmount/2);
        // Amount of SHARES to withdraw
        uint256 withdrawAmount = market.predictEscrow(userPk).balance();
        
        bytes32 hash = keccak256(
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
                                withdrawAmount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        helper.withdrawAndUnwrap(userPk, withdrawAmount, block.timestamp, v, r, s);
        
        assertApproxEqAbs(frax.balanceOf(userPk), initAmount, 2);
        assertEq(market.predictEscrow(userPk).balance(), 0);
    }

    function test_Errors() public {
        deal(address(frax), user, 10 ether, true);
        
        vm.startPrank(user);
        frax.approve(address(helper), type(uint).max);
        vm.expectRevert(abi.encodeWithSelector(VaultHelper.AddressZero.selector));
        helper.wrapAndDeposit(address(0), 10 ether);

        vm.mockCall(address(sFrax),abi.encodeWithSelector(IERC20.balanceOf.selector, address(helper)), abi.encode(uint(0)));
        vm.expectRevert(abi.encodeWithSelector(VaultHelper.InsufficientShares.selector));
        helper.wrapAndDeposit(user, 10 ether);

        vm.expectRevert(abi.encodeWithSelector(VaultHelper.AddressZero.selector));
        helper.withdrawAndUnwrap(address(0), 10 ether, block.timestamp, 0, bytes32(0), bytes32(0));

        vm.clearMockedCalls();

        address userPk = vm.addr(1);
        deal(address(frax), userPk, 10 ether, true);
        
        vm.startPrank(userPk);
        frax.approve(address(helper), type(uint).max);
        helper.wrapAndDeposit(userPk, 10 ether);
        // Amount of SHARES to withdraw
        uint256 withdrawAmount = market.predictEscrow(userPk).balance();
        
        bytes32 hash = keccak256(
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
                                withdrawAmount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        vm.mockCall(address(sFrax),abi.encodeWithSelector(IERC20.balanceOf.selector, address(helper)), abi.encode(uint(0)));
        vm.expectRevert(abi.encodeWithSelector(VaultHelper.InsufficientShares.selector));
        helper.withdrawAndUnwrap(userPk, withdrawAmount, block.timestamp, v, r, s);
    }
}
