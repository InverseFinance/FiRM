// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./marketForkTests/MarketBaseForkTest.sol";
import {DbrDistributor} from "src/DbrDistributor.sol";
import {INVEscrow, IXINV, IDbrDistributor} from "src/escrows/INVEscrow.sol";
import "src/util/DbrHelper.sol";

contract FakeMarket {
    IERC20 public constant dola =
        IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);

    function debts(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function repay(address user, uint256 amount) external {
        user;
        dola.transferFrom(msg.sender, address(this), amount);
    }
}

contract DbrHelperForkTest is MarketBaseForkTest {
    using stdStorage for StdStorage;

    DbrDistributor distributor;
    DbrHelper helper;
    INVEscrow internal escrow;
    address marketAddr = 0xb516247596Ca36bf32876199FBdCaD6B3322330B;
    address feedAddr = 0xC54Ca0a605D5DA34baC77f43efb55519fC53E78e;
    IERC20 INV;
    IXINV xINV;
    FakeMarket fakeMarket;

    event Sell(
        address indexed claimer,
        uint amountIn,
        uint amountOut,
        uint indexOut,
        address indexed receiver
    );
    event RepayDebt(
        address indexed claimer,
        address indexed market,
        address indexed to,
        uint dolaAmount
    );
    event DepositInv(
        address indexed claimer,
        address indexed to,
        uint invAmount
    );
    event MarketApproved(address indexed market, bool approved);

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
        helper.approveMarket(marketAddr, true);
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

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            user2,
            address(0),
            10000,
            0,
            address(0),
            address(0),
            0
        );

        vm.expectRevert(bytes("ONLY BENEFICIARY OR ALLOWED CLAIMERS"));
        helper.claimAndSell(sell, repay);
    }

    function test_Fails_if_nothing_to_claim() public {
        _depositAllowAndWarp();
        vm.warp(block.timestamp - 3600);
        assertEq(escrow.claimable(), 0);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            user2,
            address(0),
            10000,
            0,
            address(0),
            address(0),
            0
        );

        vm.expectRevert(DbrHelper.NoDbrToClaim.selector);
        helper.claimAndSell(sell, repay);
    }

    function test_Fails_if_no_escrow() public {
        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            user2,
            address(0),
            10000,
            0,
            address(0),
            address(0),
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DbrHelper.NoEscrow.selector,
                address(address(this))
            )
        );
        helper.claimAndSell(sell, repay);
    }

    function test_Fails_exploit_fakeMarket() public {
        _depositAllowAndWarp();
        uint256 borrowAmount = market.getCreditLimit(user);
        market.borrow(borrowAmount);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        fakeMarket = new FakeMarket();

        (sell, repay) = _getArguments(
            address(0),
            user,
            address(0),
            10000,
            0,
            address(fakeMarket),
            user,
            10000
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DbrHelper.RepayParamsNotCorrect.selector,
                repay.percentage,
                repay.to,
                repay.market,
                sell.sellForDola,
                false
            )
        );
        (uint256 dolaAmount, , uint256 dolaRepaid, ) = helper.claimAndSell(
            sell,
            repay
        );
    }

    function test_approveMarket() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        vm.prank(user, user);
        helper.approveMarket(marketAddr, false);
        assertEq(helper.isMarket(marketAddr), true);
        assertEq(
            DOLA.allowance(address(helper), marketAddr),
            type(uint256).max
        );

        vm.expectEmit(true, false, false, true);
        emit MarketApproved(marketAddr, false);

        helper.approveMarket(marketAddr, false);
        assertEq(helper.isMarket(marketAddr), false);
        assertEq(DOLA.allowance(address(helper), marketAddr), 0);

        vm.expectEmit(true, false, false, true);
        emit MarketApproved(marketAddr, true);

        helper.approveMarket(marketAddr, true);
        assertEq(helper.isMarket(marketAddr), true);
        assertEq(
            DOLA.allowance(address(helper), marketAddr),
            type(uint256).max
        );

        helper.approveMarket(address(0x10), true);
        assertEq(helper.isMarket(address(0x10)), true);
        assertEq(
            DOLA.allowance(address(helper), address(0x10)),
            type(uint256).max
        );
    }

    function test_Can_claim_and_sell_ALL_for_DOLA() public {
        _depositAllowAndWarp();

        assertEq(DOLA.balanceOf(user), 0);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            user,
            address(0),
            10000,
            0,
            address(0),
            address(0),
            0
        );

        vm.expectEmit(true, true, false, false);
        emit Sell(user, 0, 0, 0, user);
        
        helper.claimAndSell(sell, repay);

        assertEq(dbr.balanceOf(user), 0);

        // DOLA in user wallet increased
        assertGt(DOLA.balanceOf(user), 0);

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_HALF_for_DOLA() public {
        _depositAllowAndWarp();

        assertEq(DOLA.balanceOf(user), 0);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            user,
            user,
            address(0),
            5000,
            0,
            address(0),
            address(0),
            0
        );
        (uint256 dolaAmount, , , uint256 dbrAmount) = helper.claimAndSell(
            sell,
            repay
        );

        assertEq(dbr.balanceOf(user), dbrAmount);

        // DOLA in user wallet increased
        assertEq(DOLA.balanceOf(user), dolaAmount);

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_ALL_for_DOLA_to_other_user() public {
        _depositAllowAndWarp();

        assertEq(DOLA.balanceOf(user), 0);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            user2,
            address(0),
            10000,
            0,
            address(0),
            address(0),
            0
        );
        
        vm.expectEmit(true, true, false, false);
        emit Sell(user, 0, 0, 0, user2);

        (uint256 dolaAmount, , , ) = helper.claimAndSell(sell, repay);

        assertEq(escrow.claimable(), 0);

        assertEq(dbr.balanceOf(user), 0);
        assertEq(dbr.balanceOf(user2), 0);

        // DOLA in user2 wallet increased
        assertEq(DOLA.balanceOf(user2), dolaAmount);
        assertEq(DOLA.balanceOf(user), 0);

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_HALF_for_DOLA_to_other_user() public {
        _depositAllowAndWarp();

        assertEq(DOLA.balanceOf(user), 0);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            user2,
            user2,
            address(0),
            5000,
            0,
            address(0),
            address(0),
            0
        );
        (uint256 dolaAmount, , , uint256 dbrAmount) = helper.claimAndSell(
            sell,
            repay
        );

        assertEq(escrow.claimable(), 0);

        assertEq(dbr.balanceOf(user), 0);
        assertEq(dbr.balanceOf(user2), dbrAmount);

        // DOLA in user2 wallet increased
        assertEq(DOLA.balanceOf(user2), dolaAmount);
        assertEq(DOLA.balanceOf(user), 0);

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_ALL_for_INV_and_deposit() public {
        _depositAllowAndWarp();

        IXINV xInv = escrow.xINV();

        uint256 xINVBefore = xInv.balanceOf(address(escrow));
        assertGt(xINVBefore, 0);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            address(0),
            user,
            0,
            10000,
            address(0),
            address(0),
            0
        );

        (, uint256 invAmount, , ) = helper.claimAndSell(sell, repay);

        assertEq(escrow.claimable(), 0);

        // xINV balance increased in escrow
        assertApproxEqAbs(
            xInv.balanceOf(address(escrow)),
            xINVBefore + invAmount,
            0.00001 ether
        );

        // No INV nor DBR in helper
        assertEq(INV.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_HALF_for_INV_and_deposit() public {
        _depositAllowAndWarp();

        IXINV xInv = escrow.xINV();

        uint256 xINVBefore = xInv.balanceOf(address(escrow));
        assertGt(xINVBefore, 0);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            user,
            address(0),
            user,
            0,
            5000,
            address(0),
            address(0),
            0
        );

        vm.expectEmit(true, true, false, false);

        emit DepositInv(user,user,0);

        (, uint256 invAmount, , uint256 dbrAmount) = helper.claimAndSell(
            sell,
            repay
        );

        assertEq(escrow.claimable(), 0);

        // xINV balance increased in escrow
        assertApproxEqAbs(
            xInv.balanceOf(address(escrow)),
            xINVBefore + invAmount,
            0.00001 ether
        );
        // DBR balance increased in user wallet
        assertEq(dbr.balanceOf(user), dbrAmount);

        // No INV nor DBR in helper
        assertEq(INV.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_ALL_for_INV_and_deposit_for_other_user()
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

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            address(0),
            user2,
            0,
            10000,
            address(0),
            address(0),
            0
        );

        helper.claimAndSell(sell, repay);

        assertEq(escrow.claimable(), 0);

        // xINV Balance increased for user2 escrow (which has been created)
        assertEq(address(market.escrows(user2)), address(escrow2));
        assertGt(xInv.balanceOf(address(escrow2)), 0);

        assertEq(dbr.balanceOf(user2), 0);

        // User1 balance didn't increase
        assertEq(xInv.balanceOf(address(escrow)), xINVBefore);

        assertEq(INVEscrow(address(escrow2)).claimable(), 0);
        vm.warp(block.timestamp + 3600);

        // User2 has DBR to claim
        assertGt(INVEscrow(address(escrow2)).claimable(), 0);
    }

    function test_Can_claim_and_sell_HALF_for_INV_and_deposit_for_other_user()
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

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            user2,
            address(0),
            user2,
            0,
            5000,
            address(0),
            address(0),
            0
        );

        (, , , uint256 dbrAmount) = helper.claimAndSell(sell, repay);

        assertEq(escrow.claimable(), 0);

        // xINV Balance increased for user2 escrow (which has been created)
        assertEq(address(market.escrows(user2)), address(escrow2));
        assertGt(xInv.balanceOf(address(escrow2)), 0);

        assertGt(dbrAmount, 0);
        assertEq(dbr.balanceOf(user2), dbrAmount);

        // User1 balance didn't increase
        assertEq(xInv.balanceOf(address(escrow)), xINVBefore);

        assertEq(INVEscrow(address(escrow2)).claimable(), 0);
        vm.warp(block.timestamp + 3600);

        // User2 has DBR to claim
        assertGt(INVEscrow(address(escrow2)).claimable(), 0);
    }

    function test_Can_claim_and_sell_ALL_for_DOLA_and_ALL_for_repay() public {
        _depositAllowAndWarp();

        uint borrowAmount = market.getCreditLimit(user);
        market.borrow(borrowAmount);

        uint debtBefore = market.debts(user);
        assertEq(borrowAmount, debtBefore);
        uint dolaBefore = DOLA.balanceOf(user);
        assertEq(dolaBefore, borrowAmount);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            user,
            address(0),
            10000,
            0,
            marketAddr,
            user,
            10000
        );

        (uint256 dolaAmount, , uint256 dolaRepaid, ) = helper.claimAndSell(
            sell,
            repay
        );

        assertEq(dbr.balanceOf(user), 0);
        assertEq(dolaAmount, dolaRepaid);
        assertGt(dolaAmount, 0);

        // DOLA in user wallet didn't reduced
        assertEq(DOLA.balanceOf(user), dolaBefore);
        // User debt is reduced
        assertEq(debtBefore - dolaRepaid, market.debts(user));

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_only_DBR() public {
        _depositAllowAndWarp();

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            user,
            address(0),
            address(0),
            0,
            0,
            address(0),
            address(0),
            0
        );

        (uint256 dolaAmount, , , uint256 dbrAmount) = helper.claimAndSell(
            sell,
            repay
        );

        assertEq(dbr.balanceOf(user), dbrAmount);
        assertEq(DOLA.balanceOf(user), 0);
        assertEq(dolaAmount, 0);
        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_ALL_for_DOLA_and_HALF_for_repay() public {
        _depositAllowAndWarp();

        uint borrowAmount = market.getCreditLimit(user);
        market.borrow(borrowAmount);

        uint debtBefore = market.debts(user);
        assertEq(borrowAmount, debtBefore);
        uint dolaBefore = DOLA.balanceOf(user);
        assertEq(dolaBefore, borrowAmount);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            user,
            address(0),
            10000,
            0,
            marketAddr,
            user,
            5000
        );

        vm.expectEmit(true, true, false, false);
        emit Sell(user, 0, 0, 0, address(helper));

        vm.expectEmit(true, true, true, false);
        emit RepayDebt(user, marketAddr, user, 0);

        (uint256 dolaAmount, , uint256 dolaRepaid, ) = helper.claimAndSell(
            sell,
            repay
        );

        assertEq(dbr.balanceOf(user), 0);
        assertApproxEqAbs(dolaAmount, dolaRepaid * 2, 1);
        assertGt(dolaAmount, 0);

        // DOLA in user wallet increased by dolaAmount-dolaRepaid
        assertEq(DOLA.balanceOf(user), dolaBefore + dolaAmount - dolaRepaid);

        // User debt is reduced
        assertEq(debtBefore - dolaRepaid, market.debts(user));

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_HALF_for_DOLA_and_use_HALF_for_repay()
        public
    {
        _depositAllowAndWarp();

        uint borrowAmount = market.getCreditLimit(user);
        market.borrow(borrowAmount);

        uint debtBefore = market.debts(user);
        assertEq(borrowAmount, debtBefore);
        uint dolaBefore = DOLA.balanceOf(user);
        assertEq(dolaBefore, borrowAmount);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            user,
            user,
            address(0),
            5000,
            0,
            marketAddr,
            user,
            5000
        );

        (uint256 dolaAmount, , uint256 dolaRepaid, uint256 dbrAmount) = helper
            .claimAndSell(sell, repay);

        assertGt(dbrAmount, 0);
        assertEq(dbr.balanceOf(user), dbrAmount);
        assertApproxEqAbs(dolaAmount, dolaRepaid * 2, 1);
        assertGt(dolaAmount, 0);

        // DOLA in user wallet increased by dolaAmount-dolaRepaid
        assertEq(DOLA.balanceOf(user), dolaBefore + dolaAmount - dolaRepaid);

        // User debt is reduced
        assertEq(debtBefore - dolaRepaid, market.debts(user));

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_HALF_for_INV_and_HALF_for_DOLA_and_use_HALF_for_repay()
        public
    {
        _depositAllowAndWarp();

        uint borrowAmount = market.getCreditLimit(user);
        market.borrow(borrowAmount);

        uint debtBefore = market.debts(user);
        assertEq(borrowAmount, debtBefore);
        uint dolaBefore = DOLA.balanceOf(user);
        assertEq(dolaBefore, borrowAmount);

        IXINV xInv = escrow.xINV();

        uint256 xINVBefore = xInv.balanceOf(address(escrow));
        assertGt(xINVBefore, 0);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            user,
            user,
            5000,
            5000,
            marketAddr,
            user,
            5000
        );

        (
            uint256 dolaAmount,
            uint256 invAmount,
            uint256 dolaRepaid,
            uint256 dbrAmount
        ) = helper.claimAndSell(sell, repay);

        assertEq(dbrAmount, 0);
        assertEq(dbr.balanceOf(user), 0);
        assertApproxEqAbs(dolaAmount, dolaRepaid * 2, 1);
        assertGt(dolaAmount, 0);
        assertGt(invAmount, 0);
        assertGt(xInv.balanceOf(address(escrow)), xINVBefore);

        // DOLA in user wallet increased by dolaAmount-dolaRepaid
        assertEq(DOLA.balanceOf(user), dolaBefore + dolaAmount - dolaRepaid);

        // User debt is reduced
        assertEq(debtBefore - dolaRepaid, market.debts(user));

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_HALF_for_INV_and_HALF_for_DOLA_and_use_ALL_for_repay()
        public
    {
        _depositAllowAndWarp();

        uint borrowAmount = market.getCreditLimit(user);
        market.borrow(borrowAmount);

        uint debtBefore = market.debts(user);
        assertEq(borrowAmount, debtBefore);
        uint dolaBefore = DOLA.balanceOf(user);
        assertEq(dolaBefore, borrowAmount);

        IXINV xInv = escrow.xINV();

        uint256 xINVBefore = xInv.balanceOf(address(escrow));
        assertGt(xINVBefore, 0);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            user,
            user,
            5000,
            5000,
            marketAddr,
            user,
            10000
        );

        (
            uint256 dolaAmount,
            uint256 invAmount,
            uint256 dolaRepaid,
            uint256 dbrAmount
        ) = helper.claimAndSell(sell, repay);

        assertEq(dbrAmount, 0);
        assertEq(dbr.balanceOf(user), 0);
        assertEq(dolaAmount, dolaRepaid);
        assertGt(dolaAmount, 0);
        assertGt(invAmount, 0);
        assertGt(xInv.balanceOf(address(escrow)), xINVBefore);

        // DOLA in user wallet increased by dolaAmount-dolaRepaid
        assertEq(DOLA.balanceOf(user), dolaBefore + dolaAmount - dolaRepaid);

        // User debt is reduced
        assertEq(debtBefore - dolaRepaid, market.debts(user));

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_HALF_for_INV_and_HALF_for_DOLA() public {
        _depositAllowAndWarp();

        assertEq(DOLA.balanceOf(user), 0);

        IXINV xInv = escrow.xINV();

        uint256 xINVBefore = xInv.balanceOf(address(escrow));
        assertGt(xINVBefore, 0);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            user,
            user,
            5000,
            5000,
            address(0),
            address(0),
            0
        );

        (
            uint256 dolaAmount,
            uint256 invAmount,
            uint256 dolaRepaid,
            uint256 dbrAmount
        ) = helper.claimAndSell(sell, repay);

        assertEq(dbrAmount, 0);
        assertEq(dbr.balanceOf(user), 0);
        assertGt(dolaAmount, 0);
        assertGt(invAmount, 0);

        // DOLA in user wallet increased by dolaAmount
        assertEq(DOLA.balanceOf(user), dolaAmount);

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_1Qtr_for_INV_and_HALF_for_DOLA_and_use_HALF_for_repay()
        public
    {
        _depositAllowAndWarp();

        uint borrowAmount = market.getCreditLimit(user);
        market.borrow(borrowAmount);

        uint debtBefore = market.debts(user);
        assertEq(borrowAmount, debtBefore);
        uint dolaBefore = DOLA.balanceOf(user);
        assertEq(dolaBefore, borrowAmount);

        IXINV xInv = escrow.xINV();

        uint256 xINVBefore = xInv.balanceOf(address(escrow));
        assertGt(xINVBefore, 0);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            user,
            user,
            user,
            5000,
            2500,
            marketAddr,
            user,
            5000
        );

        (
            uint256 dolaAmount,
            uint256 invAmount,
            uint256 dolaRepaid,
            uint256 dbrAmount
        ) = helper.claimAndSell(sell, repay);

        assertGt(dbrAmount, 0);
        assertEq(dbr.balanceOf(user), dbrAmount);
        assertApproxEqAbs(dolaAmount, dolaRepaid * 2, 1);
        assertGt(dolaAmount, 0);
        assertGt(invAmount, 0);
        assertGt(xInv.balanceOf(address(escrow)), xINVBefore);

        // DOLA in user wallet increased by dolaAmount-dolaRepaid
        assertEq(DOLA.balanceOf(user), dolaBefore + dolaAmount - dolaRepaid);

        // User debt is reduced
        assertEq(debtBefore - dolaRepaid, market.debts(user));

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
        assertEq(INV.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_1Qtr_for_INV_and_HALF_for_DOLA() public {
        _depositAllowAndWarp();

        uint borrowAmount = market.getCreditLimit(user);
        market.borrow(borrowAmount);

        uint debtBefore = market.debts(user);
        assertEq(borrowAmount, debtBefore);
        uint dolaBefore = DOLA.balanceOf(user);
        assertEq(dolaBefore, borrowAmount);

        IXINV xInv = escrow.xINV();

        uint256 xINVBefore = xInv.balanceOf(address(escrow));
        assertGt(xINVBefore, 0);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            user,
            user,
            user,
            5000,
            2500,
            address(0),
            address(0),
            0
        );

        (
            uint256 dolaAmount,
            uint256 invAmount,
            uint256 dolaRepaid,
            uint256 dbrAmount
        ) = helper.claimAndSell(sell, repay);

        assertGt(dbrAmount, 0);
        assertEq(dbr.balanceOf(user), dbrAmount);
        assertEq(dolaRepaid, 0);
        assertGt(dolaAmount, 0);
        assertGt(invAmount, 0);
        assertGt(xInv.balanceOf(address(escrow)), xINVBefore);

        // DOLA in user wallet increased by dolaAmount
        assertEq(DOLA.balanceOf(user), dolaBefore + dolaAmount);

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
        assertEq(INV.balanceOf(address(helper)), 0);
    }

    function test_Fail_claim_and_sell_wrong_arguments() public {
        _depositAllowAndWarp();

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            user,
            user,
            5000,
            4999,
            address(0),
            address(0),
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(DbrHelper.AddressZero.selector, address(dbr))
        );
        helper.claimAndSell(sell, repay);

        (sell, repay) = _getArguments(
            address(0),
            address(0),
            user,
            5000,
            5000,
            address(0),
            address(0),
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DbrHelper.AddressZero.selector,
                address(DOLA)
            )
        );
        helper.claimAndSell(sell, repay);

        (sell, repay) = _getArguments(
            address(0),
            address(0),
            address(0),
            0,
            10000,
            address(0),
            address(0),
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(DbrHelper.AddressZero.selector, address(INV))
        );
        helper.claimAndSell(sell, repay);

        (sell, repay) = _getArguments(
            address(0),
            user,
            address(0),
            10000,
            0,
            marketAddr,
            address(0),
            5000
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DbrHelper.RepayParamsNotCorrect.selector,
                repay.percentage,
                repay.to,
                repay.market,
                sell.sellForDola,
                true
            )
        );
        helper.claimAndSell(sell, repay);

        (sell, repay) = _getArguments(
            user,
            user,
            address(0),
            10001,
            0,
            address(0),
            address(0),
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(DbrHelper.SellPercentageTooHigh.selector)
        );
        helper.claimAndSell(sell, repay);

        (sell, repay) = _getArguments(
            address(0),
            user,
            address(0),
            10000,
            0,
            address(0),
            user,
            5000
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DbrHelper.RepayParamsNotCorrect.selector,
                repay.percentage,
                repay.to,
                repay.market,
                sell.sellForDola,
                false
            )
        );
        helper.claimAndSell(sell, repay);

        // Return Zero DBR balance on helper
        vm.mockCall(
            address(dbr),
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(helper)),
            abi.encode(uint(0))
        );

        (sell, repay) = _getArguments(
            address(0),
            user,
            address(0),
            10000,
            0,
            address(0),
            address(0),
            0
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                DbrHelper.ClaimedWrongAmount.selector,
                0,
                escrow.claimable()
            )
        );
        helper.claimAndSell(sell, repay);

        // Return Zero DBR claimable on escrow
        vm.mockCall(
            address(escrow),
            abi.encodeWithSelector(IINVEscrow.claimable.selector),
            abi.encode(uint(0))
        );

        vm.expectRevert(
            abi.encodeWithSelector(DbrHelper.NoDbrToClaim.selector)
        );
        helper.claimAndSell(sell, repay);

        vm.clearMockedCalls();
        (sell, repay) = _getArguments(
            address(0),
            user,
            address(0),
            10000,
            0,
            marketAddr,
            user,
            10001
        );

        vm.expectRevert(
            abi.encodeWithSelector(DbrHelper.RepayPercentageTooHigh.selector)
        );
        helper.claimAndSell(sell, repay);
    }

    function test_Can_claim_and_sell_for_DOLA_and_ALL_for_repay_only_debt()
        public
    {
        _depositAllowAndWarp();

        uint borrowAmount = 10000;
        market.borrow(borrowAmount);

        uint debtBefore = market.debts(user);
        assertEq(borrowAmount, debtBefore);
        uint dolaBefore = DOLA.balanceOf(user);
        assertEq(dolaBefore, borrowAmount);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            user,
            address(0),
            10000,
            0,
            marketAddr,
            user,
            10000
        );

        (uint256 dolaAmount, , uint256 dolaRepaid, ) = helper.claimAndSell(
            sell,
            repay
        );

        assertEq(dbr.balanceOf(user), 0);

        // DOLA in user wallet increased
        assertEq(DOLA.balanceOf(user), dolaBefore + dolaAmount - dolaRepaid);

        // User debt is now ZERO
        assertEq(0, market.debts(user));

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_89_for_DOLA_and_10_for_INV_PART_for_repay_only_debt()
        public
    {
        _depositAllowAndWarp();

        uint borrowAmount = 10000;
        market.borrow(borrowAmount);

        uint debtBefore = market.debts(user);
        assertEq(borrowAmount, debtBefore);
        uint dolaBefore = DOLA.balanceOf(user);
        assertEq(dolaBefore, borrowAmount);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            user,
            user,
            user,
            8900,
            1000,
            marketAddr,
            user,
            9000
        );

        (uint256 dolaAmount, , uint256 dolaRepaid, uint256 dbrAmount) = helper
            .claimAndSell(sell, repay);

        assertGt(dbrAmount, 0);
        assertEq(dbr.balanceOf(user), dbrAmount);

        // DOLA in user wallet increased
        assertEq(DOLA.balanceOf(user), dolaBefore + dolaAmount - dolaRepaid);

        // User debt is now ZERO
        assertEq(0, market.debts(user));

        // No DOLA nor DBR in helper
        assertEq(DOLA.balanceOf(address(helper)), 0);
        assertEq(dbr.balanceOf(address(helper)), 0);
    }

    function test_Can_claim_and_sell_for_DOLA_and_ALL_for_repay_for_other_user()
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

        uint dolaBeforeUser = DOLA.balanceOf(user);

        DbrHelper.ClaimAndSell memory sell;
        DbrHelper.Repay memory repay;

        (sell, repay) = _getArguments(
            address(0),
            user,
            address(0),
            10000,
            0,
            marketAddr,
            user2,
            10000
        );

        vm.prank(user, user);
        (uint256 dolaAmount, , uint256 dolaRepaid, ) = helper.claimAndSell(
            sell,
            repay
        );

        assertEq(dbr.balanceOf(user), 0);

        // DOLA in user2 wallet didn't reduced
        assertEq(DOLA.balanceOf(user2), dolaBefore);
        // User2 debt is reduced but not fully repaid
        assertEq(debtBefore - dolaRepaid, market.debts(user2));
        assertGt(market.debts(user2), 0);

        // User1 DOLA didn't increase (all went to repay debt)
        assertEq(DOLA.balanceOf(user), dolaBeforeUser);
    }

    function _getArguments(
        address toDbr,
        address toDola,
        address toInv,
        uint256 sellForDola,
        uint256 sellForInv,
        address repayMarket,
        address toRepay,
        uint256 repayPercentage
    )
        internal
        pure
        returns (
            DbrHelper.ClaimAndSell memory sell,
            DbrHelper.Repay memory repay
        )
    {
        sell = DbrHelper.ClaimAndSell({
            toDbr: toDbr,
            toDola: toDola,
            toInv: toInv,
            minOutDola: 1,
            sellForDola: sellForDola,
            minOutInv: 1,
            sellForInv: sellForInv
        });
        repay = DbrHelper.Repay({
            market: repayMarket,
            to: toRepay,
            percentage: repayPercentage
        });
        return (sell, repay);
    }
}
