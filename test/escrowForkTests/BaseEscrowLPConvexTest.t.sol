// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/escrows/ConvexEscrowV2.sol";
import {console} from "forge-std/console.sol";
import {RewardHook} from "test/mocks/RewardHook.sol";

interface IExtraRewardStashV3 {
    function setExtraReward(address _token) external;

    function setRewardHook(address hook) external;

    function operator() external view returns (address);

    function stashRewards() external returns (bool);
}

interface IMintable is IERC20 {
    function mint(address to, uint256 amount) external;
}

abstract contract BaseEscrowLPConvexTest is Test {
    address market = address(0xA);
    address beneficiary = address(0xB);
    address friend = address(0xC);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    IMintable dola = IMintable(0x865377367054516e17014CcdED1e7d814EDC9ce4);

    IERC20 cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IConvexBooster booster =
        IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address operatorOwner = 0x3cE6408F923326f81A7D7929952947748180f1E6; //Booster owner

    address lpHolder;
    IERC20 curvePool;
    address gauge;
    uint256 pid;
    IRewardPool rewardPool;
    IERC20 depositToken;
    address stash;

    ConvexEscrowV2 escrow;

    struct ConvexInfo {
        uint256 pid;
        address rewardPool;
        address depositToken;
        address stash;
    }

    function init(
        address _curvePool,
        address _lpHolder,
        address _gauge,
        ConvexInfo memory _convexInfo,
        bool _addExtraDolaReward
    ) public {
        curvePool = IERC20(_curvePool);
        lpHolder = _lpHolder;
        gauge = _gauge;
        pid = _convexInfo.pid;
        rewardPool = IRewardPool(_convexInfo.rewardPool);
        depositToken = IERC20(_convexInfo.depositToken);
        stash = _convexInfo.stash;

        if (_addExtraDolaReward) {
            // Setup Dola reward
            vm.prank(operatorOwner);
            IExtraRewardStashV3(stash).setExtraReward(address(dola));

            RewardHook hook = new RewardHook(stash, address(dola));

            vm.prank(operatorOwner);
            IExtraRewardStashV3(stash).setRewardHook(address(hook));

            // Send rewards
            vm.prank(gov);
            dola.mint(address(hook), 100 ether);

            vm.prank(operatorOwner);
            booster.earmarkRewards(pid);
        }

        escrow = new ConvexEscrowV2(
            address(rewardPool),
            address(booster),
            address(cvx),
            address(crv),
            pid
        );
        vm.prank(market, market);
        escrow.initialize(curvePool, beneficiary);
    }

    function test_initialize() public {
        ConvexEscrowV2 freshEscrow = new ConvexEscrowV2(
            address(rewardPool),
            address(booster),
            address(cvx),
            address(crv),
            pid
        );
        vm.prank(address(market));
        freshEscrow.initialize(curvePool, lpHolder);
        assertEq(
            address(freshEscrow.market()),
            address(market),
            "Market not equal market"
        );
        assertEq(freshEscrow.beneficiary(), lpHolder, "Holder not beneficiary");
        assertEq(
            address(freshEscrow.token()),
            address(curvePool),
            "curvePool not Token"
        );
    }

    function test_onDeposit_successful_when_contract_holds_CurveLP(
        uint256 amount
    ) public {
        vm.assume(amount > 1);
        vm.assume(amount < curvePool.balanceOf(lpHolder));

        uint256 balanceBefore = escrow.balance();
        uint256 stakedBalanceBefore = rewardPool.balanceOf(address(escrow));

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);
        vm.prank(beneficiary, beneficiary);
        escrow.onDeposit();

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
            rewardPool.balanceOf(address(escrow)),
            amount,
            "Staked balance accounting not correct"
        );
    }

    function test_Pay_when_escrow_has_CurveLP_in_Convex(uint amount) public {
        vm.assume(amount > 1);
        vm.assume(amount < curvePool.balanceOf(lpHolder));

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.onDeposit();

        uint balanceBefore = escrow.balance();
        uint rewardPoolBalBefore = rewardPool.balanceOf(address(escrow));
        uint beneficiaryBalanceBefore = curvePool.balanceOf(beneficiary);

        vm.prank(market, market);
        uint256 withdrawAmount = amount / 2;
        escrow.pay(beneficiary, withdrawAmount);

        assertEq(escrow.balance(), balanceBefore - withdrawAmount);
        assertEq(
            rewardPool.balanceOf(address(escrow)),
            rewardPoolBalBefore - withdrawAmount
        );
        assertEq(
            curvePool.balanceOf(beneficiary),
            beneficiaryBalanceBefore + withdrawAmount
        );
    }

    function test_Pay_partially_with_escrow_balance_when_escrow_has_CurveLP_in_Convex(
        uint amount
    ) public {
        uint256 extraCurveLP = 1 ether;
        vm.assume(amount > 1);
        vm.assume(amount < curvePool.balanceOf(lpHolder) - extraCurveLP);

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.onDeposit();

        // Send extra CurveLP to the escrow
        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), extraCurveLP);

        uint balanceBefore = escrow.balance();
        uint rewardPoolBalBefore = rewardPool.balanceOf(address(escrow));
        uint beneficiaryBalanceBefore = curvePool.balanceOf(beneficiary);

        vm.prank(market, market);
        uint256 withdrawAmount = amount / 2 + extraCurveLP;
        escrow.pay(beneficiary, withdrawAmount);

        assertEq(escrow.balance(), balanceBefore - withdrawAmount);
        // Should withdraw first from the escrow and then partially from the reward pool
        assertEq(
            rewardPool.balanceOf(address(escrow)),
            rewardPoolBalBefore - amount / 2
        );
        assertEq(
            curvePool.balanceOf(beneficiary),
            beneficiaryBalanceBefore + withdrawAmount
        );
    }

    function test_Pay_ALL_when_donation_of_LP_when_staked_into_Convex(
        uint amount
    ) public {
        uint256 donationAmount = 1 ether;
        vm.assume(amount > 1);
        vm.assume(amount < curvePool.balanceOf(lpHolder) - donationAmount);

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.onDeposit();

        // Donate lp to the escrow
        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), donationAmount);

        uint balanceBefore = escrow.balance();

        vm.prank(market, market);
        uint256 withdrawAmount = amount + donationAmount;
        escrow.pay(beneficiary, withdrawAmount);

        assertEq(escrow.balance(), balanceBefore - withdrawAmount);
    }

    function test_Pay_fail_with_OnlyMarket_when_called_by_non_market() public {
        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), 1 ether);
        vm.prank(beneficiary, beneficiary);
        escrow.onDeposit();

        vm.prank(lpHolder, lpHolder);
        vm.expectRevert(ConvexEscrowV2.OnlyMarket.selector);
        escrow.pay(beneficiary, 1 ether);
    }

    function test_Claim_successful_when_called_by_beneficiary(
        uint amount
    ) public {
        vm.assume(amount > 1000000);
        vm.assume(amount < curvePool.balanceOf(lpHolder));
        uint crvBalanceBefore = crv.balanceOf(beneficiary);
        uint cvxBalanceBefore = cvx.balanceOf(beneficiary);

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);

        vm.prank(beneficiary);
        escrow.claim();

        assertGt(
            crv.balanceOf(address(beneficiary)),
            crvBalanceBefore,
            "Did not get CRV reward"
        );
        assertGt(
            cvx.balanceOf(address(beneficiary)),
            cvxBalanceBefore,
            "Did not get CVX reward"
        );
        assertGt(
            dola.balanceOf(address(beneficiary)),
            0,
            "Did not get Dola reward"
        );
    }

    function test_Claim_successful_whenForcedToClaim(uint amount) public {
        vm.assume(amount > 1000000);
        vm.assume(amount < curvePool.balanceOf(lpHolder));

        uint crvBalanceBefore = crv.balanceOf(beneficiary);
        uint cvxBalanceBefore = cvx.balanceOf(beneficiary);

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.onDeposit();

        vm.warp(block.timestamp + 30 days);

        vm.prank(beneficiary);
        escrow.claim();

        assertGt(
            crv.balanceOf(address(beneficiary)),
            crvBalanceBefore,
            "Did not get CRV reward"
        );
        assertGt(
            cvx.balanceOf(address(beneficiary)),
            cvxBalanceBefore,
            "Did not get CVX reward"
        );
        assertGt(
            dola.balanceOf(address(beneficiary)),
            0,
            "Did not get Dola reward"
        );
    }

    function test_ClaimTo_successful_whenCalledByBeneficiary(
        uint amount
    ) public {
        vm.assume(amount > 1000000);
        vm.assume(amount < curvePool.balanceOf(lpHolder));

        uint crvBalanceBefore = crv.balanceOf(beneficiary);
        uint cvxBalanceBefore = cvx.balanceOf(beneficiary);

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.onDeposit();

        vm.warp(block.timestamp + 30 days);

        assertEq(
            dola.balanceOf(address(beneficiary)),
            0,
            "Dola balance is not 0"
        );
        vm.prank(beneficiary);
        escrow.claimTo(beneficiary);

        assertGt(
            crv.balanceOf(address(beneficiary)),
            crvBalanceBefore,
            "Did not get CRV reward"
        );
        assertGt(
            cvx.balanceOf(address(beneficiary)),
            cvxBalanceBefore,
            "Did not get CVX reward"
        );
        assertGt(
            dola.balanceOf(address(beneficiary)),
            0,
            "Did not get Dola reward"
        );
    }

    function testClaimTo_successful_whenCalledByAllowlistedAddress(
        uint amount
    ) public {
        vm.assume(amount > 1000000);
        vm.assume(amount < curvePool.balanceOf(lpHolder));

        uint crvBalanceBefore = crv.balanceOf(friend);
        uint cvxBalanceBefore = cvx.balanceOf(friend);

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.onDeposit();

        vm.warp(block.timestamp + 30 days);

        vm.prank(beneficiary);
        escrow.allowClaimOnBehalf(friend);
        vm.prank(friend);
        escrow.claimTo(friend);

        assertGt(
            crv.balanceOf(address(friend)),
            crvBalanceBefore,
            "Did not get CRV reward"
        );
        assertGt(
            cvx.balanceOf(address(friend)),
            cvxBalanceBefore,
            "Did not get CVX reward"
        );
        assertGt(dola.balanceOf(address(friend)), 0, "Did not get Dola reward");
    }

    function test_ClaimTo_fails_whenAllowlistedAddressIsDisallowed() public {
        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), 1 ether);
        vm.prank(beneficiary);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);

        vm.prank(beneficiary);
        escrow.allowClaimOnBehalf(friend);

        vm.prank(friend);
        escrow.claimTo(beneficiary);

        vm.warp(block.timestamp + 14 days);

        vm.prank(beneficiary);
        escrow.disallowClaimOnBehalf(friend);

        vm.prank(friend);
        vm.expectRevert(ConvexEscrowV2.OnlyBeneficiaryOrAllowlist.selector);
        escrow.claimTo(beneficiary);
    }

    function test_ClaimTo_fails_whenCalledByNonAllowlistedAddress() public {
        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), 1 ether);
        vm.prank(beneficiary);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(friend);
        vm.expectRevert(ConvexEscrowV2.OnlyBeneficiaryOrAllowlist.selector);
        escrow.claimTo(beneficiary);
    }

    function testAllowClaimOnBehalf_fails_whenCalledByNonBeneficiary() public {
        vm.prank(friend);
        vm.expectRevert(ConvexEscrowV2.OnlyBeneficiary.selector);
        escrow.allowClaimOnBehalf(friend);
    }

    function testDisallowClaimOnBehalf_fails_whenCalledByNonBeneficiary()
        public
    {
        vm.prank(friend);
        vm.expectRevert(ConvexEscrowV2.OnlyBeneficiary.selector);
        escrow.disallowClaimOnBehalf(friend);
    }
}
