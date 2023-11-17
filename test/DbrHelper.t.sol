// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./marketForkTests/MarketBaseForkTest.sol";
import {DbrDistributor} from "src/DbrDistributor.sol";
import {INVEscrow, IXINV, IDbrDistributor} from "src/escrows/INVEscrow.sol";
import {DbrHelper, ICurvePool} from "src/util/DbrHelper.sol";


contract DbrHelperForkTest is MarketBaseForkTest {
    using stdStorage for StdStorage;

    DbrDistributor distributor;
    DbrHelper helper;
    INVEscrow internal escrow;
    address marketAddr = 0xb516247596Ca36bf32876199FBdCaD6B3322330B;
    address feedAddr = 0xC54Ca0a605D5DA34baC77f43efb55519fC53E78e;
    IERC20 INV;
    IXINV xINV;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 18586960);
        distributor = DbrDistributor(
            0xdcd2D918511Ba39F2872EB731BB88681AE184244
        );

        _advancedInit(marketAddr, feedAddr, true);
        vm.startPrank(gov);
        dbr.addMinter(address(distributor));
        vm.stopPrank();

        helper = new DbrHelper();
        INV = helper.inv();
    }

    function _depositAllowAndWarp() internal {
        gibCollateral(user, testAmount);

        vm.startPrank(user, user);
        deposit(testAmount);

        escrow = INVEscrow(address(market.escrows(user)));
        assertEq(escrow.claimable(), 0);

        escrow.setClaimer(address(helper), true);

        vm.warp(block.timestamp + 3600);

        assertGt(escrow.claimable(), 0);
    }

    function test_Fails_to_claim_if_not_allowed() public {
        _depositAllowAndWarp();

        escrow.setClaimer(address(helper), false);

        vm.expectRevert(bytes("ONLY BENEFICIARY OR ALLOWED CLAIMERS"));
        helper.claimAndSellDbr(1, user);

        vm.expectRevert(bytes("ONLY BENEFICIARY OR ALLOWED CLAIMERS"));
        helper.claimSellAndDepositInv(1, user);

        vm.expectRevert(bytes("ONLY BENEFICIARY OR ALLOWED CLAIMERS"));
        helper.claimSellAndRepay(1, marketAddr, user);
    }

    function test_Fails_if_nothing_to_claim() public {
        _depositAllowAndWarp();
        vm.warp(block.timestamp - 3600);
        assertEq(escrow.claimable(), 0);

        vm.expectRevert(DbrHelper.NoDbrToClaim.selector);
        helper.claimAndSellDbr(1, user);
    }

    function test_Fails_if_no_escrow() public {
        vm.expectRevert(abi.encodeWithSelector(DbrHelper.NoEscrow.selector,address(address(this))));
        helper.claimAndSellDbr(1, user);
    }

    function test_Can_claim_and_sell_for_DOLA() public {
        _depositAllowAndWarp();

        assertEq(DOLA.balanceOf(user), 0);

        helper.claimAndSellDbr(1, user);

        assertEq(dbr.balanceOf(user), 0);

        // DOLA in user wallet increased
        assertGt(DOLA.balanceOf(user), 0);

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_for_DOLA_to_other_user() public {
        _depositAllowAndWarp();

        assertEq(DOLA.balanceOf(user), 0);

        helper.claimAndSellDbr(1, user2);

        assertEq(escrow.claimable(), 0);

        assertEq(dbr.balanceOf(user), 0);
        assertEq(dbr.balanceOf(user2), 0);

        // DOLA in user2 wallet increased
        assertGt(DOLA.balanceOf(user2), 0);
        assertEq(DOLA.balanceOf(user), 0);

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_for_INV_and_deposit() public {
        _depositAllowAndWarp();

        IXINV xInv = escrow.xINV();

        uint256 xINVBefore = xInv.balanceOf(address(escrow));
        assertGt(xINVBefore, 0);

        helper.claimSellAndDepositInv(1, user);

        assertEq(escrow.claimable(), 0);

        // xINV balance increased in escrow
        assertGt(xInv.balanceOf(address(escrow)), xINVBefore);

        // No INV nor DBR in helper
        assertEq(INV.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_for_INV_and_deposit_for_other_user()
        public
    {
        _depositAllowAndWarp();

        IXINV xInv = escrow.xINV();
        uint256 xINVBefore = xInv.balanceOf(address(escrow));

        assertGt(xInv.balanceOf(address(escrow)), 0);

        IEscrow escrow2 = market.predictEscrow(user2);

        // escrow2 doesn't exist yet , ofc no xINV bal
        assertEq(address(market.escrows(user2)), address(0));
        assertEq(xInv.balanceOf(address(escrow2)), 0);

        helper.claimSellAndDepositInv(1, user2);

        assertEq(escrow.claimable(), 0);

        // xINV Balance increased for user2 escrow (which has been created)
        assertEq(address(market.escrows(user2)), address(escrow2));
        assertGt(xInv.balanceOf(address(escrow2)), 0);

        // User1 balance didn't increase
        assertEq(xInv.balanceOf(address(escrow)), xINVBefore);

        assertEq(INVEscrow(address(escrow2)).claimable(), 0);
        vm.warp(block.timestamp + 3600);

        // User2 has DBR to claim
        assertGt(INVEscrow(address(escrow2)).claimable(), 0);
    }

    function test_Can_claim_and_sell_for_DOLA_and_repay() public {
        _depositAllowAndWarp();

        uint borrowAmount = market.getCreditLimit(user);
        market.borrow(borrowAmount);

        uint debtBefore = market.debts(user);
        assertEq(borrowAmount, debtBefore);
        uint dolaBefore = DOLA.balanceOf(user);
        assertEq(dolaBefore, borrowAmount);

        helper.claimSellAndRepay(1, marketAddr, user);

        assertEq(dbr.balanceOf(user), 0);

        // DOLA in user wallet didn't reduced
        assertEq(DOLA.balanceOf(user), dolaBefore);
        // User debt is reduced
        assertGt(debtBefore, market.debts(user));

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_for_DOLA_and_repay_only_debt() public {
        _depositAllowAndWarp();

        uint borrowAmount = 100000;
        market.borrow(borrowAmount);

        uint debtBefore = market.debts(user);
        assertEq(borrowAmount, debtBefore);
        uint dolaBefore = DOLA.balanceOf(user);
        assertEq(dolaBefore, borrowAmount);

        helper.claimSellAndRepay(1, marketAddr, user);

        assertEq(dbr.balanceOf(user), 0);

        // DOLA in user wallet increased
        assertGt(DOLA.balanceOf(user), dolaBefore);

        // User debt is now ZERO
        assertEq(0, market.debts(user));

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }
    function test_Can_claim_and_sell_for_DOLA_and_repay_for_other_user()
        public
    {
        _depositAllowAndWarp();
        vm.stopPrank();

        gibCollateral(user2, testAmount);

        vm.startPrank(user2, user2);
        deposit(testAmount);
        uint borrowAmount = market.getCreditLimit(user2);
        market.borrow(borrowAmount);
        vm.stopPrank();

        uint debtBefore = market.debts(user2);
        assertEq(borrowAmount, debtBefore);
        uint dolaBefore = DOLA.balanceOf(user2);
        assertEq(dolaBefore, borrowAmount);

        vm.prank(user, user);
        helper.claimSellAndRepay(1, marketAddr, user2);

        assertEq(dbr.balanceOf(user), 0);

        // DOLA in user2 wallet didn't reduced
        assertEq(DOLA.balanceOf(user2), dolaBefore);
        // User2 debt is reduced
        assertGt(debtBefore, market.debts(user2));
    }
}
