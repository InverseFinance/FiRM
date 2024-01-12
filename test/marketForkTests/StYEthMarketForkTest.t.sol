// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";
import {SimpleERC20Escrow} from "src/escrows/SimpleERC20Escrow.sol";
import {StYEthPriceFeed} from "src/feeds/StYEthPriceFeed.sol";
import {VaultHelper} from "src/escrows/VaultHelper.sol";

contract StYEthMarketForkTest is MarketBaseForkTest {
    SimpleERC20Escrow escrow;
    StYEthPriceFeed stYEthFeed;
    IERC20 yEth = IERC20(0x1BED97CBC3c24A4fb5C069C6E311a967386131f7);
    IERC20 stYEth = IERC20(0x583019fF0f430721aDa9cfb4fac8F06cA104d0B4);
    VaultHelper helper;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        escrow = new SimpleERC20Escrow();
        stYEthFeed = new StYEthPriceFeed();

        Market market = new Market(
            gov,
            lender,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbr)),
            stYEth,
            IOracle(address(oracle)),
            5000,
            5000,
            1000,
            true
        );

        _advancedInit(address(market), address(stYEthFeed), true);

        // Setup VaultHelper
        helper = new VaultHelper(address(stYEth), address(market), address(yEth));
    }

    function test_wrapAndDeposit(uint initAmount) public { 
        vm.assume(initAmount > 3);
        vm.assume(initAmount < 10000000000000 ether);
        deal(address(yEth), user, initAmount, true);

        vm.startPrank(user);
        yEth.approve(address(helper), type(uint).max);
        helper.wrapAndDeposit(user, initAmount);
        assertEq(yEth.balanceOf(user), 0);
    }

    function test_withdrawAndUnwrap(uint initAmount) public {
        vm.assume(initAmount > 3);
        vm.assume(initAmount < 10000000000000 ether);

        address userPk = vm.addr(1);
        deal(address(yEth), userPk, initAmount, true);

        vm.startPrank(userPk);
        yEth.approve(address(helper), type(uint).max);
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

        assertApproxEqAbs(yEth.balanceOf(userPk), initAmount, 2);
        assertEq(market.predictEscrow(userPk).balance(), 0);
    }

    function test_Errors() public {
        deal(address(yEth), user, 10 ether, true);

        vm.startPrank(user);
        yEth.approve(address(helper), type(uint).max);
        vm.expectRevert(abi.encodeWithSelector(VaultHelper.AddressZero.selector));
        helper.wrapAndDeposit(address(0), 10 ether);

        vm.mockCall(address(stYEth),abi.encodeWithSelector(IERC20.balanceOf.selector, address(helper)), abi.encode(uint(0)));
        vm.expectRevert(abi.encodeWithSelector(VaultHelper.InsufficientShares.selector));
        helper.wrapAndDeposit(user, 10 ether);

        vm.expectRevert(abi.encodeWithSelector(VaultHelper.AddressZero.selector));
        helper.withdrawAndUnwrap(address(0), 10 ether, block.timestamp, 0, bytes32(0), bytes32(0));

        vm.clearMockedCalls();

        address userPk = vm.addr(1);
        deal(address(yEth), userPk, 10 ether, true);

        vm.startPrank(userPk);
        yEth.approve(address(helper), type(uint).max);
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

        vm.mockCall(address(stYEth),abi.encodeWithSelector(IERC20.balanceOf.selector, address(helper)), abi.encode(uint(0)));
        vm.expectRevert(abi.encodeWithSelector(VaultHelper.InsufficientShares.selector));
        helper.withdrawAndUnwrap(userPk, withdrawAmount, block.timestamp, v, r, s);
    }
}