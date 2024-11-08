// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";
import {SimpleERC20Escrow} from "src/escrows/SimpleERC20Escrow.sol";
import {StYEthPriceFeed} from "src/feeds/StYEthPriceFeed.sol";
import {ERC4626Helper, IERC4626} from "src/util/ERC4626Helper.sol";
import {ERC4626Helper, IERC4626, IMultiMarketTransformHelper} from "src/util/ERC4626Helper.sol";

contract StYEthMarketForkTest is MarketBaseForkTest {
    SimpleERC20Escrow escrow;
    StYEthPriceFeed stYEthFeed;
    IERC20 yEth = IERC20(0x1BED97CBC3c24A4fb5C069C6E311a967386131f7);
    IERC20 stYEth = IERC20(0x583019fF0f430721aDa9cfb4fac8F06cA104d0B4);
    ERC4626Helper helper;
    bytes data;
    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 19015193);

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

        // Setup ERC4626Helper
        helper = new ERC4626Helper(gov, pauseGuardian);
        vm.startPrank(gov);
        helper.setMarket(
            address(market),
            address(yEthAddr),
            address(styEthAddr)
        );
        data = abi.encode(address(market));
        vm.stopPrank();
    }

    function test_wrapAndDeposit(uint initAmount) public {
        vm.assume(initAmount > 3);
        vm.assume(initAmount < 10000000000000 ether);
        deal(address(yEth), user, initAmount, true);

        vm.startPrank(user);
        yEth.approve(address(helper), type(uint).max);
        helper.transformToCollateralAndDeposit(initAmount, user, data);
        assertEq(yEth.balanceOf(user), 0);
    }

    function test_withdrawAndUnwrap(uint initAmount) public {
        vm.assume(initAmount > 3);
        vm.assume(initAmount < 10000000000000 ether);

        address userPk = vm.addr(1);
        deal(address(yEth), userPk, initAmount, true);

        vm.startPrank(userPk);
        yEth.approve(address(helper), type(uint).max);
        helper.transformToCollateralAndDeposit(initAmount / 2, userPk, data);
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

        IMultiMarketTransformHelper.Permit
            memory permit = IMultiMarketTransformHelper.Permit({
                deadline: block.timestamp,
                v: v,
                r: r,
                s: s
            });
        helper.withdrawAndTransformFromCollateral(
            withdrawAmount,
            userPk,
            permit,
            data
        );

        assertApproxEqAbs(yEth.balanceOf(userPk), initAmount, 2);
        assertEq(market.predictEscrow(userPk).balance(), 0);
    }

    function test_Errors() public {
        deal(address(yEth), user, 10 ether, true);

        vm.startPrank(user);
        yEth.approve(address(helper), type(uint).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Helper.MarketNotSet.selector,
                address(0)
            )
        );
        helper.transformToCollateralAndDeposit(
            10 ether,
            address(0),
            abi.encode(address(0))
        );

        // vm.mockCall(
        //     address(stYEth),
        //     abi.encodeWithSelector(
        //         IERC4626.deposit.selector,
        //         10 ether,
        //         address(helper)
        //     ),
        //     abi.encode(uint(0))
        // );
        vm.mockCall(
            address(stYEth),
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(helper)),
            abi.encode(uint(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626Helper.InsufficientShares.selector)
        );

        helper.transformToCollateralAndDeposit(10 ether, user, data);

        vm.expectRevert(
            abi.encodeWithSelector(
                ERC4626Helper.MarketNotSet.selector,
                address(0)
            )
        );
        IMultiMarketTransformHelper.Permit
            memory permit = IMultiMarketTransformHelper.Permit({
                deadline: block.timestamp,
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            });
        data = abi.encode(address(0));
        helper.withdrawAndTransformFromCollateral(10 ether, user, permit, data);

        vm.clearMockedCalls();

        address userPk = vm.addr(1);
        deal(address(yEth), userPk, 10 ether, true);

        vm.startPrank(userPk);
        yEth.approve(address(helper), type(uint).max);
        data = abi.encode(address(market));
        helper.transformToCollateralAndDeposit(10 ether, userPk, data);
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

        vm.mockCall(
            address(stYEth),
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(helper)),
            abi.encode(uint(0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626Helper.InsufficientShares.selector)
        );
        IMultiMarketTransformHelper.Permit
            memory permit2 = IMultiMarketTransformHelper.Permit({
                deadline: block.timestamp,
                v: v,
                r: r,
                s: s
            });
        helper.withdrawAndTransformFromCollateral(
            withdrawAmount,
            userPk,
            permit2,
            data
        );
    }
}
