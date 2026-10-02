// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/marketForkTests/MarketForkTest.sol";
import {ALEV2} from "src/util/ALEV2.sol";
import {MockExchangeProxy, IFlashMinter} from "test/util/aleTests/ALEV2BaseSimpleForkTest.t.sol";

/// @dev Regression test for the allowance clobbering bug on the fused ALEV2:
/// the inherited helper flow (depositBuyDbrAndBorrowOnBehalf) used to overwrite
/// the standing max collateral approval granted to the market via setMarket with
/// an exact-amount approval, which market.deposit consumed down to zero, breaking
/// every subsequent leveragePosition on that market
/// (see mainnet tx 0xf7d3a9b5e7bb181fbaefd65ea3eb9c5f38dd356c4134376b8c64abb63ea532f2
/// which zeroed the CVX allowance of the deployed ALEV2 for the CVX market).
/// ALEV2 now grants no standing approvals at all: every flow approves the exact
/// amount it consumes right before use, so no flow can break another and the
/// contract holds zero allowances at rest.
contract ALECvxHelperAllowanceForkTest is MarketForkTest {
    address cvxMarketAddr = 0xdc2265cBD15beD67b5F2c0B82e23FcE4a07ddF6b;
    address cvxFeedAddr = 0xd962fC30A72A84cE50161031391756Bf2876Af5D;

    MockExchangeProxy exchangeProxy;
    ALEV2 ale;
    IFlashMinter flash;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        init(cvxMarketAddr, cvxFeedAddr);

        exchangeProxy = new MockExchangeProxy(address(oracle), address(DOLA));

        vm.startPrank(gov, gov);
        ale = new ALEV2(newTriDBRAddr, gov);
        ale.setMarket(address(market), address(collateral), address(0), true);
        ale.allowProxy(address(exchangeProxy));
        borrowController.allow(address(ale));
        // Avoid flakiness from the CVX feed heartbeat when forking at latest block
        borrowController.setStalenessThreshold(address(market), 2 days);

        flash = IFlashMinter(address(ale.flash()));
        DOLA.addMinter(address(flash));
        flash.setMaxFlashLimit(10000000e18);
        vm.stopPrank();

        vm.prank(chair, chair);
        fed.expansion(IMarket(address(market)), 1_000_000e18);
    }

    function test_depositBuyDbrAndBorrowOnBehalf_leaves_no_allowance() public {
        uint amount = 1000 ether;
        address userPk = vm.addr(1);
        gibCollateral(userPk, amount);
        uint dolaBefore = DOLA.balanceOf(userPk);
        uint dbrBefore = dbr.balanceOf(userPk);

        assertEq(
            collateral.allowance(address(ale), address(market)),
            0,
            "setMarket should not grant any allowance"
        );

        uint dolaAmount = getMaxBorrowAmount(amount) / 2;
        (uint dolaForDBR, uint dbrAmount) = ale.approximateDolaAndDbrNeeded(
            dolaAmount,
            365 days,
            8
        );
        (uint8 v, bytes32 r, bytes32 s) = signBorrowOnBehalf(
            userPk,
            1,
            dolaAmount + dolaForDBR,
            address(ale)
        );

        vm.startPrank(userPk, userPk);
        collateral.approve(address(ale), amount);
        ale.depositBuyDbrAndBorrowOnBehalf(
            IMarket(address(market)),
            amount,
            dolaAmount,
            dolaForDBR,
            (dbrAmount * 98) / 100,
            block.timestamp,
            v,
            r,
            s
        );
        vm.stopPrank();

        // Ad-hoc approval: the deposit consumes the exact approval entirely
        assertEq(
            collateral.allowance(address(ale), address(market)),
            0,
            "allowance left standing after helper flow"
        );
        assertEq(DOLA.balanceOf(userPk) - dolaBefore, dolaAmount);
        assertGt(dbr.balanceOf(userPk) - dbrBefore, (dbrAmount * 98) / 100);
        assertEq(market.predictEscrow(userPk).balance(), amount);
    }

    function test_leveragePosition_still_works_after_helper_deposit() public {
        // Step 1: helper deposit+borrow flow. Before the fix this zeroed the
        // ALE's CVX allowance for the market.
        uint amount = 1000 ether;
        address userPk = vm.addr(1);
        gibCollateral(userPk, amount);

        uint dolaAmount = getMaxBorrowAmount(amount) / 2;
        (uint dolaForDBR, uint dbrAmount) = ale.approximateDolaAndDbrNeeded(
            dolaAmount,
            365 days,
            8
        );
        (uint8 v, bytes32 r, bytes32 s) = signBorrowOnBehalf(
            userPk,
            1,
            dolaAmount + dolaForDBR,
            address(ale)
        );

        vm.startPrank(userPk, userPk);
        collateral.approve(address(ale), amount);
        ale.depositBuyDbrAndBorrowOnBehalf(
            IMarket(address(market)),
            amount,
            dolaAmount,
            dolaForDBR,
            (dbrAmount * 98) / 100,
            block.timestamp,
            v,
            r,
            s
        );
        vm.stopPrank();

        // Step 2: lever up as another user. Before the fix this reverted with
        // "ERC20: transfer amount exceeds allowance" on market.deposit.
        uint amount2 = 1000 ether;
        address user2Pk = vm.addr(2);
        gibCollateral(user2Pk, amount2);

        uint borrowAmount = getMaxBorrowAmount(amount2) / 2;
        // recharge mocked proxy for swap, we need to swap DOLA to collateral
        deal(
            address(collateral),
            address(exchangeProxy),
            convertDolaToCollat(borrowAmount)
        );

        (v, r, s) = signBorrowOnBehalf(user2Pk, 2, borrowAmount, address(ale));
        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);
        ALEV2.DBRHelper memory dbrData; // NO DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            collateral,
            borrowAmount
        );

        vm.startPrank(user2Pk, user2Pk);
        collateral.approve(address(ale), amount2);
        ale.depositAndLeveragePosition(
            amount2,
            borrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData,
            true
        );
        vm.stopPrank();

        // Balance in escrow is equal to the collateral deposited + the extra
        // collateral swapped from the leverage
        assertEq(
            market.predictEscrow(user2Pk).balance(),
            amount2 + convertDolaToCollat(borrowAmount),
            "leverage deposit failed"
        );
        // No allowances left standing after the leverage flow either
        assertEq(
            collateral.allowance(address(ale), address(market)),
            0,
            "allowance left standing after leverage flow"
        );
    }

    function test_depositBuyDbrAndBorrowOnBehalf_works_without_setMarket()
        public
    {
        // The helper flow must keep working for markets never configured via
        // setMarket (standalone helper semantics: exact approval, fully consumed)
        vm.startPrank(gov, gov);
        ALEV2 freshAle = new ALEV2(newTriDBRAddr, gov);
        borrowController.allow(address(freshAle));
        vm.stopPrank();

        uint amount = 1000 ether;
        address userPk = vm.addr(1);
        gibCollateral(userPk, amount);
        uint dolaBefore = DOLA.balanceOf(userPk);

        assertEq(collateral.allowance(address(freshAle), address(market)), 0);

        uint dolaAmount = getMaxBorrowAmount(amount) / 2;
        (uint dolaForDBR, uint dbrAmount) = freshAle
            .approximateDolaAndDbrNeeded(dolaAmount, 365 days, 8);
        (uint8 v, bytes32 r, bytes32 s) = signBorrowOnBehalf(
            userPk,
            1,
            dolaAmount + dolaForDBR,
            address(freshAle)
        );

        vm.startPrank(userPk, userPk);
        collateral.approve(address(freshAle), amount);
        freshAle.depositBuyDbrAndBorrowOnBehalf(
            IMarket(address(market)),
            amount,
            dolaAmount,
            dolaForDBR,
            (dbrAmount * 98) / 100,
            block.timestamp,
            v,
            r,
            s
        );
        vm.stopPrank();

        // Exact approval path: fully consumed by the deposit
        assertEq(collateral.allowance(address(freshAle), address(market)), 0);
        assertEq(DOLA.balanceOf(userPk) - dolaBefore, dolaAmount);
        assertEq(market.predictEscrow(userPk).balance(), amount);
    }

    function signBorrowOnBehalf(
        address signer,
        uint256 pk,
        uint256 dolaBorrowAmount,
        address caller
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        caller,
                        signer,
                        dolaBorrowAmount,
                        market.nonces(signer),
                        block.timestamp
                    )
                )
            )
        );
        (v, r, s) = vm.sign(pk, hash);
    }
}
