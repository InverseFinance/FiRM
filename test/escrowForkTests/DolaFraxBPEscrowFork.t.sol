// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
//import "src/escrows/ConvexCurveEscrow.sol";
import "src/escrows/LPCurveYearnV2Escrow.sol";
import {YearnVaultV2Helper} from "src/util/YearnVaultV2Helper.sol";
import {console} from "forge-std/console.sol";
import {RewardHook} from "test/mocks/RewardHook.sol";

interface DeployedHelper {
    function sharesToAmount(
        address vault,
        uint256 shares
    ) external view returns (uint256);
}

interface IExtraRewardStashV3 {
    function setExtraReward(address _token) external;

    function setRewardHook(address hook) external;

    function operator() external view returns (address);

    function stashRewards() external returns (bool);
}

interface IMintable is IERC20 {
    function mint(address to, uint256 amount) external;
}

contract DolaFraxBPEscrowForkTest is Test {
    address market = address(0xA);
    address beneficiary = address(0xB);
    address friend = address(0xC);
    address holder = address(0x4E2f395De08C11d28bE37Fb2F19f6F5869136567);
    address yearnHolder = address(0x621BcFaA87bA0B7c57ca49e1BB1a8b917C34Ed2F);
    IERC20 dolaFraxBP = IERC20(0xE57180685E3348589E9521aa53Af0BCD497E884d);

    IERC20 cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IRewardPool rewardPool =
        IRewardPool(0x0404d05F3992347d2f0dC3a97bdd147D77C85c1c);
    IConvexBooster booster =
        IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IERC20 depositToken = IERC20(0xf7eCC27CC9DB5d28110AF2d89b176A6623c7E351);
    IYearnVaultV2 public yearn =
        IYearnVaultV2(0xe5F625e8f4D2A038AE9583Da254945285E5a77a4);

    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    IMintable dola = IMintable(0x865377367054516e17014CcdED1e7d814EDC9ce4);

    address operatorOwner = 0x3cE6408F923326f81A7D7929952947748180f1E6; //Booster owner
    address stash = 0xe5A980F96c791c8Ea56c2585840Cab571441510e; //setExtraReward(token)
    address gauge = 0xBE266d68Ce3dDFAb366Bb866F4353B6FC42BA43c;
    uint256 pid = 115;
    LPCurveYearnV2Escrow escrow;
    DeployedHelper deployedHelper =
        DeployedHelper(0x444443bae5bB8640677A8cdF94CB8879Fec948Ec);

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20020781);

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

        escrow = new LPCurveYearnV2Escrow(
            address(rewardPool),
            address(booster),
            address(yearn),
            address(cvx),
            address(crv),
            pid
        );
        vm.prank(market, market);
        escrow.initialize(dolaFraxBP, beneficiary);
    }

    function test_initialize() public {
        LPCurveYearnV2Escrow freshEscrow = new LPCurveYearnV2Escrow(
            address(rewardPool),
            address(booster),
            address(yearn),
            address(cvx),
            address(crv),
            pid
        );
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
        assertEq(freshEscrow.maxLoss(), 1, "Max loss not 0.01%");
    }

    function test_depositToConvex_successful_when_contract_holds_DolaFraxBP(
        uint256 amount
    ) public {
        vm.assume(amount > 1);
        vm.assume(amount < dolaFraxBP.balanceOf(holder));

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
            rewardPool.balanceOf(address(escrow)),
            amount,
            "Staked balance accounting not correct"
        );
    }

    function test_depositToYearn_successful_when_contract_holds_DolaFraxBP(
        uint256 amount
    ) public {
        vm.assume(amount > 1);
        vm.assume(amount < dolaFraxBP.balanceOf(holder));

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
            0,
            "Yearn Balance is not correct"
        );
    }

    function test_withdrawFromConvex_successful_if_deposited(
        uint amount
    ) public {
        vm.assume(amount > 1);
        vm.assume(amount < dolaFraxBP.balanceOf(holder));

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);

        vm.startPrank(beneficiary, beneficiary);

        escrow.depositToConvex();

        assertGt(
            rewardPool.balanceOf(address(escrow)),
            0,
            "Staked balance is 0"
        );
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

        assertEq(
            rewardPool.balanceOf(address(escrow)),
            0,
            "Staked balance is not correct"
        );
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

    function test_withdrawFromYearn_successful_if_deposited(
        uint amount
    ) public {
        vm.assume(amount > 1);
        vm.assume(amount < dolaFraxBP.balanceOf(holder));
        uint256 maxDelta = 2;

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);

        vm.startPrank(beneficiary, beneficiary);
        escrow.depositToYearn();
        assertApproxEqAbs(
            deployedHelper.sharesToAmount(
                address(yearn),
                yearn.balanceOf(address(escrow))
            ),
            amount,
            maxDelta,
            "Helper from Wavey Balance is not correct"
        );
        assertApproxEqAbs(
            YearnVaultV2Helper.collateralToAsset(
                yearn,
                yearn.balanceOf(address(escrow))
            ),
            amount,
            maxDelta,
            "Helper Math is not correct"
        );
        escrow.withdrawFromYearn();
        assertApproxEqAbs(
            escrow.balance(),
            amount,
            maxDelta,
            "Escrow Balance is not correct"
        );

        assertEq(
            yearn.balanceOf(address(escrow)),
            0,
            "Yearn Balance is not correct"
        );
    }

    function test_withdrawFromYearn2_successful_if_deposited(
        uint256 amount
    ) public {
        // Test fuzz deposit to yearn, withdraw exact amount if expected calculated expected amount from yearn based on shares
        vm.assume(amount > 1);
        vm.assume(amount < dolaFraxBP.balanceOf(holder));

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.depositToYearn();
        assertApproxEqAbs(
            deployedHelper.sharesToAmount(
                address(yearn),
                yearn.balanceOf(address(escrow))
            ),
            amount,
            2,
            "Helper from Wavey Balance is not correct"
        );
        assertApproxEqAbs(
            YearnVaultV2Helper.collateralToAsset(
                yearn,
                yearn.balanceOf(address(escrow))
            ),
            amount,
            2,
            "Helper Math is not correct"
        );

        vm.startPrank(address(market), address(market));
        escrow.pay(
            beneficiary,
            YearnVaultV2Helper.collateralToAsset(
                yearn,
                yearn.balanceOf(address(escrow))
            )
        );

        assertEq(
            yearn.balanceOf(address(escrow)),
            0,
            "Yearn Balance is not correct"
        );
    }

    function test_depositToYearn_all_even_if_already_deposit_to_Convex(
        uint256 amount
    ) public {
        uint256 extraDolaFraxBP = 1 ether;
        vm.assume(amount > 1);
        vm.assume(amount < dolaFraxBP.balanceOf(holder) - extraDolaFraxBP);

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);
        vm.prank(beneficiary, beneficiary);
        escrow.depositToConvex();

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), extraDolaFraxBP);

        assertEq(
            rewardPool.balanceOf(address(escrow)),
            amount,
            "Staked balance is not correct"
        );
        assertEq(
            rewardPool.balanceOf(address(escrow)),
            amount,
            "Reward Pool balance is not correct"
        );
        vm.prank(beneficiary, beneficiary);
        escrow.depositToYearn();

        assertEq(
            rewardPool.balanceOf(address(escrow)),
            0,
            "Staked balance is not 0"
        );
        assertEq(
            rewardPool.balanceOf(address(escrow)),
            0,
            "Reward Pool balance is not 0"
        );
        assertEq(
            dolaFraxBP.balanceOf(address(escrow)),
            0,
            "LP Token balance is not 0"
        );
        assertApproxEqAbs(
            yearn.balanceOf(address(escrow)),
            YearnVaultV2Helper.assetToCollateral(
                yearn,
                amount + extraDolaFraxBP
            ),
            1,
            "Yearn Balance is 0"
        );
    }

    function test_depositToConvex_all_even_if_already_deposit_to_Yearn(
        uint amount
    ) public {
        uint256 extraDolaFraxBP = 1 ether;
        vm.assume(amount > 1);
        vm.assume(amount < dolaFraxBP.balanceOf(holder) - extraDolaFraxBP);

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);
        vm.prank(beneficiary, beneficiary);
        escrow.depositToYearn();

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), extraDolaFraxBP);

        assertApproxEqAbs(
            yearn.balanceOf(address(escrow)),
            YearnVaultV2Helper.assetToCollateral(yearn, amount),
            1,
            "Yearn Balance is not correct"
        );
        assertEq(
            rewardPool.balanceOf(address(escrow)),
            0,
            "Staked balance is not 0"
        );
        assertEq(
            rewardPool.balanceOf(address(escrow)),
            0,
            "Reward Pool balance is not 0"
        );

        uint256 lpBalBeforeInYearn = YearnVaultV2Helper.collateralToAsset(
            yearn,
            yearn.balanceOf(address(escrow))
        );
        vm.prank(beneficiary, beneficiary);
        escrow.depositToConvex();

        assertApproxEqAbs(
            rewardPool.balanceOf(address(escrow)),
            lpBalBeforeInYearn + extraDolaFraxBP,
            1,
            "Staked balance is not correct"
        );
        assertApproxEqAbs(
            rewardPool.balanceOf(address(escrow)),
            lpBalBeforeInYearn + extraDolaFraxBP,
            1,
            "Reward Pool balance is not correct"
        );
        assertEq(
            dolaFraxBP.balanceOf(address(escrow)),
            0,
            "LP Token balance is not 0"
        );
        assertEq(
            yearn.balanceOf(address(escrow)),
            0,
            "Yearn Balance is not correct"
        );
    }

    function test_Pay_when_escrow_has_DolaFraxBP_in_Convex(uint amount) public {
        vm.assume(amount > 1);
        vm.assume(amount < dolaFraxBP.balanceOf(holder));

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.depositToConvex();

        uint balanceBefore = escrow.balance();
        uint rewardPoolBalBefore = rewardPool.balanceOf(address(escrow));
        uint beneficiaryBalanceBefore = dolaFraxBP.balanceOf(beneficiary);

        vm.prank(market, market);
        uint256 withdrawAmount = amount / 2;
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

    function test_Pay_partially_with_escrow_balance_when_escrow_has_DolaFraxBP_in_Convex(
        uint amount
    ) public {
        uint256 extraDolaFraxBP = 1 ether;
        vm.assume(amount > 1);
        vm.assume(amount < dolaFraxBP.balanceOf(holder) - extraDolaFraxBP);

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.depositToConvex();

        // Send extra DolaFraxBP to the escrow
        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), extraDolaFraxBP);

        uint balanceBefore = escrow.balance();
        uint rewardPoolBalBefore = rewardPool.balanceOf(address(escrow));
        uint beneficiaryBalanceBefore = dolaFraxBP.balanceOf(beneficiary);

        vm.prank(market, market);
        uint256 withdrawAmount = amount / 2 + extraDolaFraxBP;
        escrow.pay(beneficiary, withdrawAmount);

        assertEq(escrow.balance(), balanceBefore - withdrawAmount);
        // Should withdraw first from the escrow and then partially from the reward pool
        assertEq(
            rewardPool.balanceOf(address(escrow)),
            rewardPoolBalBefore - amount / 2
        );
        assertEq(
            dolaFraxBP.balanceOf(beneficiary),
            beneficiaryBalanceBefore + withdrawAmount
        );
    }

    function test_Pay_when_escrow_has_DolaFraxBP_in_Yearn(
        uint256 amount
    ) public {
        vm.assume(amount > 1);
        vm.assume(amount < dolaFraxBP.balanceOf(holder));

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
        uint balanceBefore = escrow.balance();
        uint yearnBalBefore = YearnVaultV2Helper.collateralToAsset(
            yearn,
            yearn.balanceOf(address(escrow))
        );
        uint beneficiaryBalanceBefore = dolaFraxBP.balanceOf(beneficiary);

        vm.prank(market, market);
        uint256 withdrawAmount = amount / 2;
        escrow.pay(beneficiary, withdrawAmount);

        assertApproxEqAbs(
            escrow.balance(),
            balanceBefore - withdrawAmount,
            1,
            "Escrow Balance after is not correct"
        );
        assertApproxEqAbs(
            YearnVaultV2Helper.collateralToAsset(
                yearn,
                yearn.balanceOf(address(escrow))
            ),
            yearnBalBefore - withdrawAmount,
            2
        );
        assertEq(
            dolaFraxBP.balanceOf(beneficiary),
            beneficiaryBalanceBefore + withdrawAmount
        );
    }

    function test_Pay_partially_with_escrow_balance_when_escrow_has_DolaFraxBP_in_Yearn(
        uint256 amount
    ) public {
        uint256 extraDolaFraxBP = 1 ether;
        vm.assume(amount > 1);
        vm.assume(amount < dolaFraxBP.balanceOf(holder) - extraDolaFraxBP);

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.depositToYearn();

        // Send extra DolaFraxBP to the escrow
        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), extraDolaFraxBP);

        uint balanceBefore = escrow.balance();
        uint yearnBalBefore = YearnVaultV2Helper.collateralToAsset(
            yearn,
            yearn.balanceOf(address(escrow))
        );
        uint beneficiaryBalanceBefore = dolaFraxBP.balanceOf(beneficiary);

        vm.prank(market, market);
        uint256 withdrawAmount = amount / 2 + extraDolaFraxBP;
        escrow.pay(beneficiary, withdrawAmount);

        assertApproxEqAbs(escrow.balance(), balanceBefore - withdrawAmount, 2);
        assertApproxEqAbs(
            YearnVaultV2Helper.collateralToAsset(
                yearn,
                yearn.balanceOf(address(escrow))
            ),
            yearnBalBefore - (amount / 2),
            2
        );
        assertEq(
            dolaFraxBP.balanceOf(beneficiary),
            beneficiaryBalanceBefore + withdrawAmount
        );
    }

    function test_Pay_ALL_when_donation_of_Yearn_when_staked_into_Convex(
        uint amount
    ) public {
        uint256 donationAmount = 1 ether;
        vm.assume(amount > 1);
        vm.assume(amount < dolaFraxBP.balanceOf(holder));

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.depositToConvex();

        // Donate yearn to escrow
        vm.prank(yearnHolder, yearnHolder);
        IERC20(address(yearn)).transfer(address(escrow), donationAmount);

        uint256 lpFromDonation = YearnVaultV2Helper.collateralToAsset(
            yearn,
            yearn.balanceOf(address(escrow))
        );

        uint balanceBefore = escrow.balance();

        vm.prank(market, market);
        uint256 withdrawAmount = amount + lpFromDonation;
        escrow.pay(beneficiary, withdrawAmount);

        assertEq(escrow.balance(), balanceBefore - withdrawAmount);

        assertEq(yearn.balanceOf(address(escrow)), 0);
    }

    function test_Pay_fail_with_OnlyMarket_when_called_by_non_market() public {
        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), 1 ether);
        vm.prank(beneficiary, beneficiary);
        escrow.depositToConvex();

        vm.prank(holder, holder);
        vm.expectRevert(LPCurveYearnV2Escrow.OnlyMarket.selector);
        escrow.pay(beneficiary, 1 ether);
    }

    function test_Claim_successful_when_called_by_beneficiary(
        uint amount
    ) public {
        vm.assume(amount > 1000000);
        vm.assume(amount < dolaFraxBP.balanceOf(holder));
        uint crvBalanceBefore = crv.balanceOf(beneficiary);
        uint cvxBalanceBefore = cvx.balanceOf(beneficiary);

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.depositToConvex();

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
        vm.assume(amount < dolaFraxBP.balanceOf(holder));

        uint crvBalanceBefore = crv.balanceOf(beneficiary);
        uint cvxBalanceBefore = cvx.balanceOf(beneficiary);

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.depositToConvex();

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
        vm.assume(amount < dolaFraxBP.balanceOf(holder));

        uint crvBalanceBefore = crv.balanceOf(beneficiary);
        uint cvxBalanceBefore = cvx.balanceOf(beneficiary);

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.depositToConvex();

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
        vm.assume(amount < dolaFraxBP.balanceOf(holder));

        uint crvBalanceBefore = crv.balanceOf(friend);
        uint cvxBalanceBefore = cvx.balanceOf(friend);

        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.depositToConvex();

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
        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), 1 ether);
        vm.prank(beneficiary);
        escrow.depositToConvex();

        vm.warp(block.timestamp + 14 days);

        vm.prank(beneficiary);
        escrow.allowClaimOnBehalf(friend);

        vm.prank(friend);
        escrow.claimTo(beneficiary);

        vm.warp(block.timestamp + 14 days);

        vm.prank(beneficiary);
        escrow.disallowClaimOnBehalf(friend);

        vm.prank(friend);
        vm.expectRevert(
            LPCurveYearnV2Escrow.OnlyBeneficiaryOrAllowlist.selector
        );
        escrow.claimTo(beneficiary);
    }

    function test_ClaimTo_fails_whenCalledByNonAllowlistedAddress() public {
        vm.prank(holder, holder);
        dolaFraxBP.transfer(address(escrow), 1 ether);
        vm.prank(beneficiary);
        escrow.depositToConvex();

        vm.warp(block.timestamp + 14 days);
        vm.prank(friend);
        vm.expectRevert(
            LPCurveYearnV2Escrow.OnlyBeneficiaryOrAllowlist.selector
        );
        escrow.claimTo(beneficiary);
    }

    function testAllowClaimOnBehalf_fails_whenCalledByNonBeneficiary() public {
        vm.prank(friend);
        vm.expectRevert(LPCurveYearnV2Escrow.OnlyBeneficiary.selector);
        escrow.allowClaimOnBehalf(friend);
    }

    function testDisallowClaimOnBehalf_fails_whenCalledByNonBeneficiary()
        public
    {
        vm.prank(friend);
        vm.expectRevert(LPCurveYearnV2Escrow.OnlyBeneficiary.selector);
        escrow.disallowClaimOnBehalf(friend);
    }

    function test_setMaxLoss_successful_whenCalledByBeneficiary() public {
        uint256 maxLoss = 1000; // 10%
        vm.prank(beneficiary);
        escrow.setMaxLoss(maxLoss);
        assertEq(escrow.maxLoss(), maxLoss);
    }

    function test_setMaxLoss_fails_whenCalledByNonBeneficiary() public {
        uint256 maxLoss = 1000; // 10%
        vm.expectRevert(LPCurveYearnV2Escrow.OnlyBeneficiary.selector);
        escrow.setMaxLoss(maxLoss);
        assertEq(escrow.maxLoss(), 1);
    }
}
