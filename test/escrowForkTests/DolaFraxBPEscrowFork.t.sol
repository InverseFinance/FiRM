// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
//import "src/escrows/ConvexCurveEscrow.sol";
import "src/escrows/DolaFraxBPEscrow.sol";
import {YearnVaultV2Helper} from "src/util/YearnVaultV2Helper.sol";

contract DolaFraxBPEscrowForkTest is Test {
    address market = address(0xA);
    address beneficiary = address(0xB);
    address friend = address(0xC);
    address holder = address(0x4E2f395De08C11d28bE37Fb2F19f6F5869136567);
    address yearnHolder = address(0x621BcFaA87bA0B7c57ca49e1BB1a8b917C34Ed2F);
    IERC20 dolaFraxBP = IERC20(0xE57180685E3348589E9521aa53Af0BCD497E884d);

    IERC20 threeCrv = IERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    IERC20 cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IRewardPool rewardPool =
        IRewardPool(0x0404d05F3992347d2f0dC3a97bdd147D77C85c1c);
    IConvexBooster booster =
        IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IERC20 depositToken = IERC20(0xf7eCC27CC9DB5d28110AF2d89b176A6623c7E351);
    IYearnVaultV2 public yearn =
        IYearnVaultV2(0xe5F625e8f4D2A038AE9583Da254945285E5a77a4);
    DolaFraxBPEscrow escrow;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        escrow = new DolaFraxBPEscrow();
        vm.startPrank(market, market);
        escrow.initialize(dolaFraxBP, beneficiary);
        vm.stopPrank();
    }

    function test_initialize() public {
        DolaFraxBPEscrow freshEscrow = new DolaFraxBPEscrow();
        vm.prank(address(market));
        freshEscrow.initialize(dolaFraxBP, holder);
        assertEq(
            address(freshEscrow.market()),
            address(market),
            "Market not equal market"
        );
        assertEq(freshEscrow.beneficiary(), holder, "Holder not beneficiary");
        assertEq(
            address(freshEscrow.token()),
            address(dolaFraxBP),
            "dolaFraxBP not Token"
        );
    }

    function test_depositToConvex_successful_when_contract_holds_DolaFraxBP()
        public
    {
        uint256 amount = 1 ether;
        uint256 balanceBefore = escrow.balance();
        uint256 stakedBalanceBefore = rewardPool.balanceOf(address(escrow));

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);
        vm.prank(beneficiary, beneficiary);
        escrow.depositToConvex();

        assertEq(
            escrow.balance(),
            balanceBefore + amount,
            "Escrow Balance is not correct"
        );
        assertEq(
            rewardPool.balanceOf(address(escrow)),
            stakedBalanceBefore + amount,
            "Reward Pool Balance is not correct"
        );
        assertEq(
            escrow.stakedBalance(),
            amount,
            "Staked balance accounting not correct"
        );
    }

    function test_depositToYearn_successful_when_contract_holds_DolaFraxBP()
        public
    {
        uint256 amount = 1 ether;

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);
        vm.prank(beneficiary, beneficiary);
        escrow.depositToYearn();

        assertApproxEqAbs(
            escrow.balance(),
            amount,
            2,
            "Escrow Balance is not correct"
        );
        assertApproxEqAbs(
            yearn.balanceOf(address(escrow)),
            YearnVaultV2Helper.assetToCollateral(yearn, amount),
            2,
            "Yearn Balance is not correct"
        );
    }

    function test_withdrawFromConvex_successful_if_deposited() public {
        uint256 amount = 1 ether;
        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);

        vm.startPrank(beneficiary, beneficiary);

        escrow.depositToConvex();

        assertGt(escrow.stakedBalance(), 0, "Staked balance is 0");
        assertGt(
            rewardPool.balanceOf(address(escrow)),
            0,
            "Reward Pool balance is 0"
        );
        assertEq(
            dolaFraxBP.balanceOf(address(escrow)),
            0,
            "LP Token balance is greater than 0"
        );
        assertEq(
            depositToken.balanceOf(address(escrow)),
            0,
            "Convex Deposit Token balance is greater than 0"
        );
        assertGt(
            rewardPool.balanceOf(address(escrow)),
            0,
            "RewardPool Balance is 0"
        );
        escrow.withdrawFromConvex();

        assertEq(escrow.stakedBalance(), 0, "Staked balance is not correct");
        assertEq(
            rewardPool.balanceOf(address(escrow)),
            0,
            "Reward Pool balance is 0"
        );
        assertEq(
            dolaFraxBP.balanceOf(address(escrow)),
            amount,
            "LP Token balance is not correct"
        );
        assertEq(
            depositToken.balanceOf(address(escrow)),
            0,
            "Convex Deposit Token balance is greater than 0"
        );
        assertEq(
            rewardPool.balanceOf(address(escrow)),
            0,
            "RewardPool Balance is not 0"
        );
    }

    function test_withdrawFromYearn_successful_if_deposited() public {
        uint256 amount = 1 ether;

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);
        vm.startPrank(beneficiary, beneficiary);
        escrow.depositToYearn();

        escrow.withdrawFromYearn();
        assertApproxEqAbs(
            escrow.balance(),
            amount,
            1,
            "Escrow Balance is not correct"
        );
        assertEq(
            yearn.balanceOf(address(escrow)),
            0,
            "Yearn Balance is not correct"
        );
    }

    function test_Pay_successful_when_contract_has_staked_DolaFraxBP() public {
        uint256 amount = 1 ether;
        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.depositToConvex();

        uint balanceBefore = escrow.balance();
        uint rewardPoolBalBefore = rewardPool.balanceOf(address(escrow));
        uint beneficiaryBalanceBefore = dolaFraxBP.balanceOf(beneficiary);

        vm.prank(market, market);
        uint256 withdrawAmount = 0.5 ether;
        escrow.pay(beneficiary, withdrawAmount);

        assertEq(escrow.balance(), balanceBefore - withdrawAmount);
        assertEq(
            rewardPool.balanceOf(address(escrow)),
            rewardPoolBalBefore - withdrawAmount
        );
        assertEq(
            dolaFraxBP.balanceOf(beneficiary),
            beneficiaryBalanceBefore + withdrawAmount
        );
    }

    function testPay_fail_with_OnlyMarket_when_called_by_non_market() public {
        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), 1 ether);
        vm.prank(beneficiary, beneficiary);
        escrow.depositToConvex();

        vm.prank(holder, holder);
        vm.expectRevert(DolaFraxBPEscrow.OnlyMarket.selector);
        escrow.pay(beneficiary, 1 ether);
    }

    // function testClaim_successful_when_called_by_beneficiary() public {
    //     uint crvBalanceBefore = crv.balanceOf(beneficiary);
    //     uint cvxBalanceBefore = cvx.balanceOf(beneficiary);
    //     //uint threeCrvBalanceBefore = threeCrv.balanceOf(beneficiary);
    //     vm.prank(holder, holder);
    //     dolaFraxBP.transfer(address(escrow), 1 ether);

    //     vm.prank(beneficiary, beneficiary);
    //     escrow.depositToConvex();

    //     vm.warp(block.timestamp + 14 days);
    //     vm.prank(beneficiary);
    //     escrow.claim();

    //     assertGt(
    //         crv.balanceOf(beneficiary),
    //         crvBalanceBefore,
    //         "Did not get CRV reward"
    //     );
    //     assertGt(
    //         cvx.balanceOf(beneficiary),
    //         cvxBalanceBefore,
    //         "Did not get CVX reward"
    //     );
    //     // assertEq(threeCrv.balanceOf(beneficiary), threeCrvBalanceBefore);
    // }

    // function testClaim_successful_whenForcedToClaim() public {
    //     uint crvBalanceBefore = crv.balanceOf(beneficiary);
    //     uint cvxBalanceBefore = cvx.balanceOf(beneficiary);
    //     uint threeCrvBalanceBefore = threeCrv.balanceOf(beneficiary);
    //     vm.prank(holder, holder);
    //     cvxCrv.transfer(address(escrow), 1 ether);
    //     escrow.onDeposit();

    //     vm.warp(block.timestamp + 14 days);
    //     stakingWrapper.getReward(address(escrow));
    //     vm.prank(beneficiary);
    //     escrow.claim();

    //     assertGt(crv.balanceOf(beneficiary), crvBalanceBefore);
    //     assertGt(cvx.balanceOf(beneficiary), cvxBalanceBefore);
    //     assertEq(threeCrv.balanceOf(beneficiary), threeCrvBalanceBefore);
    // }

    // function testClaim_successful_whenRewardWeightSetTo5000() public {
    //     uint crvBalanceBefore = crv.balanceOf(beneficiary);
    //     uint cvxBalanceBefore = cvx.balanceOf(beneficiary);
    //     uint threeCrvBalanceBefore = threeCrv.balanceOf(beneficiary);
    //     vm.prank(holder, holder);
    //     cvxCrv.transfer(address(escrow), 1 ether);
    //     escrow.onDeposit();

    //     vm.startPrank(beneficiary);
    //     escrow.setRewardWeight(5000);
    //     vm.warp(block.timestamp + 14 days);
    //     escrow.claim();
    //     vm.stopPrank();

    //     assertGt(
    //         crv.balanceOf(beneficiary),
    //         crvBalanceBefore,
    //         "Crv balance did not increase"
    //     );
    //     assertGt(
    //         cvx.balanceOf(beneficiary),
    //         cvxBalanceBefore,
    //         "Cvx balance did not increase"
    //     );
    //     assertGt(
    //         threeCrv.balanceOf(beneficiary),
    //         threeCrvBalanceBefore,
    //         "Three curve balance did not increase"
    //     );
    // }

    // function testClaim_successful_whenRewardWeightSetTo10000() public {
    //     uint crvBalanceBefore = crv.balanceOf(beneficiary);
    //     uint cvxBalanceBefore = cvx.balanceOf(beneficiary);
    //     uint threeCrvBalanceBefore = threeCrv.balanceOf(beneficiary);
    //     vm.prank(holder, holder);
    //     cvxCrv.transfer(address(escrow), 1 ether);
    //     escrow.onDeposit();

    //     vm.startPrank(beneficiary);
    //     escrow.setRewardWeight(10000);
    //     vm.warp(block.timestamp + 14 days);
    //     escrow.claim();
    //     vm.stopPrank();

    //     assertEq(crv.balanceOf(beneficiary), crvBalanceBefore);
    //     assertEq(cvx.balanceOf(beneficiary), cvxBalanceBefore);
    //     assertGt(
    //         threeCrv.balanceOf(beneficiary),
    //         threeCrvBalanceBefore,
    //         "Three curve balance did not increase"
    //     );
    // }

    // function testClaimTo_successful_whenCalledByBeneficiary() public {
    //     uint crvBalanceBefore = crv.balanceOf(friend);
    //     uint cvxBalanceBefore = cvx.balanceOf(friend);
    //     uint threeCrvBalanceBefore = threeCrv.balanceOf(friend);
    //     vm.prank(holder, holder);
    //     cvxCrv.transfer(address(escrow), 1 ether);
    //     escrow.onDeposit();

    //     vm.warp(block.timestamp + 14 days);
    //     vm.prank(beneficiary);
    //     escrow.claimTo(friend);

    //     assertGt(crv.balanceOf(friend), crvBalanceBefore);
    //     assertGt(cvx.balanceOf(friend), cvxBalanceBefore);
    //     assertEq(threeCrv.balanceOf(friend), threeCrvBalanceBefore);
    // }

    // function testClaimTo_successful_whenCalledByAllowlistedAddress() public {
    //     uint crvBalanceBefore = crv.balanceOf(beneficiary);
    //     uint cvxBalanceBefore = cvx.balanceOf(beneficiary);
    //     uint threeCrvBalanceBefore = threeCrv.balanceOf(beneficiary);
    //     vm.prank(holder, holder);
    //     cvxCrv.transfer(address(escrow), 1 ether);
    //     escrow.onDeposit();

    //     vm.warp(block.timestamp + 14 days);
    //     vm.prank(beneficiary);
    //     escrow.allowClaimOnBehalf(friend);
    //     vm.prank(friend);
    //     escrow.claimTo(beneficiary);

    //     assertGt(crv.balanceOf(beneficiary), crvBalanceBefore);
    //     assertGt(cvx.balanceOf(beneficiary), cvxBalanceBefore);
    //     assertEq(threeCrv.balanceOf(beneficiary), threeCrvBalanceBefore);
    // }

    // function testClaimTo_fails_whenAllowlistedAddressIsDisallowed() public {
    //     vm.prank(holder, holder);
    //     cvxCrv.transfer(address(escrow), 1 ether);
    //     escrow.onDeposit();

    //     vm.warp(block.timestamp + 14 days);
    //     vm.prank(beneficiary);
    //     escrow.allowClaimOnBehalf(friend);
    //     vm.prank(friend);
    //     escrow.claimTo(beneficiary);
    //     vm.warp(block.timestamp + 14 days);
    //     vm.prank(beneficiary);
    //     escrow.disallowClaimOnBehalf(friend);
    //     vm.prank(friend);
    //     vm.expectRevert("ONLY BENEFICIARY OR ALLOWED");
    //     escrow.claimTo(beneficiary);
    // }

    // function testClaimTo_fails_whenCalledByNonAllowlistedAddress() public {
    //     vm.prank(holder, holder);
    //     cvxCrv.transfer(address(escrow), 1 ether);
    //     escrow.onDeposit();

    //     vm.warp(block.timestamp + 14 days);
    //     vm.prank(friend);
    //     vm.expectRevert("ONLY BENEFICIARY OR ALLOWED");
    //     escrow.claimTo(beneficiary);
    // }

    // function testAllowClaimOnBehalf_fails_whenCalledByNonBeneficiary() public {
    //     vm.prank(friend);
    //     vm.expectRevert("ONLY BENEFICIARY");
    //     escrow.allowClaimOnBehalf(friend);
    // }

    // function testDisallowClaimOnBehalf_fails_whenCalledByNonBeneficiary()
    //     public
    // {
    //     vm.prank(friend);
    //     vm.expectRevert("ONLY BENEFICIARY");
    //     escrow.disallowClaimOnBehalf(friend);
    // }

    // function testSetRewardWeight_fails_whenCalledByNonBeneficiary() public {
    //     vm.prank(friend);
    //     vm.expectRevert("ONLY BENEFICIARY OR ALLOWED");
    //     escrow.setRewardWeight(10000);
    // }

    // function testSetRewardWeight_fails_whenSetOver10000() public {
    //     vm.prank(beneficiary);
    //     vm.expectRevert("WEIGHT > 10000");
    //     escrow.setRewardWeight(10001);
    // }
}
