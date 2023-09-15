// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/escrows/ConvexEscrow.sol";

contract MockRewards {

    IERC20 token;
    constructor(address _token){
        token = IERC20(_token);
    }

    function getReward(address account) external {
        token.transfer(account, 1 ether);
    }
}

contract ConvexEscrowForkTest is Test{

    address market = address(0xA);
    address beneficiary = address(0xB);
    address friend = address(0xC);
    address holder = address(0x50BE13b54f3EeBBe415d20250598D81280e56772);
    IERC20 dola = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 cvxCrv = IERC20(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7);
    ICvxRewardPool rewardPool = ICvxRewardPool(0xCF50b810E57Ac33B91dCF525C6ddd9881B139332);
        
    ConvexEscrow escrow;


    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        
        escrow = new ConvexEscrow();
        vm.startPrank(market, market);
        escrow.initialize(address(cvx), beneficiary);
        vm.stopPrank();
    }

    function testOnDeposit_successful_whenContractHoldsCvxCrv() public {
        uint balanceBefore = escrow.balance();
        uint stakedBalanceBefore = rewardPool.balanceOf(address(escrow));
        
        vm.prank(holder, holder);
        cvx.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        assertEq(escrow.balance(), balanceBefore + 1 ether);
        assertEq(rewardPool.balanceOf(address(escrow)), stakedBalanceBefore + 1 ether);
    }

    function testPay_successful_whenContractHasStakedCvxCrv() public {
        vm.prank(holder, holder);
        cvx.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        uint balanceBefore = escrow.balance();
        uint stakedBalanceBefore = rewardPool.balanceOf(address(escrow));
        uint beneficiaryBalanceBefore = cvx.balanceOf(beneficiary);

        vm.prank(market, market);
        escrow.pay(beneficiary, 1 ether);


        assertEq(escrow.balance(), balanceBefore - 1 ether);
        assertEq(rewardPool.balanceOf(address(escrow)), stakedBalanceBefore - 1 ether);
        assertEq(cvx.balanceOf(beneficiary), beneficiaryBalanceBefore + 1 ether);
    }

    function testPay_failWithONLYMARKET_whenCalledByNonMarket() public {
        vm.prank(holder, holder);
        cvx.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.prank(holder, holder);
        vm.expectRevert("ONLY MARKET");
        escrow.pay(beneficiary, 1 ether);
    }

    function testClaim_successful_whenCalledByBeneficiary() public {
        uint cvxCrvBalanceBefore = cvxCrv.balanceOf(beneficiary);
        vm.prank(holder, holder);
        cvx.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.claim();

        assertGt(cvxCrv.balanceOf(beneficiary), cvxCrvBalanceBefore);
    }

    function testClaim_successful() public {
        uint cvxCrvBalanceBefore = cvxCrv.balanceOf(beneficiary);
        vm.prank(holder, holder);
        cvx.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        
        vm.startPrank(beneficiary);
        vm.warp(block.timestamp + 14 days);
        escrow.claim();
        vm.stopPrank();

        assertGt(cvxCrv.balanceOf(beneficiary), cvxCrvBalanceBefore, "cvxCrv balance did not increase");
    }

    function testClaimTo_successful_whenExtraRewardsAdded() public {
        uint cvxCrvBalanceBefore = cvxCrv.balanceOf(beneficiary);
        uint dolaBalanceBefore = dola.balanceOf(beneficiary);
        vm.prank(holder, holder);
        cvx.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        MockRewards reward = new MockRewards(address(dola));
        deal(address(dola), address(reward), 10 ether);
        vm.prank(rewardPool.rewardManager());
        rewardPool.addExtraReward(address(reward));
        
        vm.startPrank(beneficiary);
        vm.warp(block.timestamp + 14 days);
        address[] memory rewards = new address[](1);
        rewards[0] = address(dola);
        escrow.claimTo(beneficiary, rewards);
        vm.stopPrank();

        assertGt(cvxCrv.balanceOf(beneficiary), cvxCrvBalanceBefore, "cvxCrv balance did not increase");
        assertGt(dola.balanceOf(beneficiary), dolaBalanceBefore, "Dola extra reward balance did not increase");
    }

    function testClaimTo_fails_whenTryingToClaimCollateral() public {
        vm.prank(holder, holder);
        cvx.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        MockRewards reward = new MockRewards(address(cvx));
        deal(address(cvx), address(reward), 10 ether);
        vm.prank(rewardPool.rewardManager());
        rewardPool.addExtraReward(address(reward));
        
        vm.startPrank(beneficiary);
        vm.warp(block.timestamp + 14 days);
        address[] memory rewards = new address[](1);
        rewards[0] = address(cvx);
        vm.expectRevert("CANT CLAIM COLLATERAL");
        escrow.claimTo(beneficiary, rewards);
        vm.stopPrank();
    }

    function testClaimTo_fails_whenArraySizeMismatched() public {
        vm.prank(holder, holder);
        cvx.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        MockRewards reward = new MockRewards(address(cvx));
        deal(address(cvx), address(reward), 10 ether);
        vm.prank(rewardPool.rewardManager());
        rewardPool.addExtraReward(address(reward));
        
        vm.startPrank(beneficiary);
        vm.warp(block.timestamp + 14 days);
        address[] memory rewards = new address[](2);
        rewards[0] = address(cvx);
        vm.expectRevert("UNEQUAL ARRAY");
        escrow.claimTo(beneficiary, rewards);

        rewards = new address[](0);
        vm.expectRevert("UNEQUAL ARRAY");
        escrow.claimTo(beneficiary, rewards);
        vm.stopPrank();
    }

    function testClaimTo_successful_whenCalledByBeneficiary() public {
        uint cvxCrvBalanceBefore = cvxCrv.balanceOf(friend);
        vm.prank(holder, holder);
        cvx.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.claimTo(friend);

        assertGt(cvxCrv.balanceOf(friend), cvxCrvBalanceBefore);
    }

    function testClaimTo_successful_whenCalledByAllowlistedAddress() public {
        uint cvxCrvBalanceBefore = cvxCrv.balanceOf(beneficiary);
        vm.prank(holder, holder);
        cvx.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.allowClaimOnBehalf(friend);
        vm.prank(friend);
        escrow.claimTo(beneficiary);

        assertGt(cvxCrv.balanceOf(beneficiary), cvxCrvBalanceBefore);
    }

    function testClaimTo_fails_whenAllowlistedAddressIsDisallowed() public {
        vm.prank(holder, holder);
        cvx.transfer(address(escrow), 1 ether);
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
        vm.expectRevert("ONLY BENEFICIARY OR ALLOWED");
        escrow.claimTo(beneficiary);
    }

    function testClaimTo_fails_whenCalledByNonAllowlistedAddress() public {
        vm.prank(holder, holder);
        cvx.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(friend);
        vm.expectRevert("ONLY BENEFICIARY OR ALLOWED");
        escrow.claimTo(beneficiary);
    }

    function testAllowClaimOnBehalf_fails_whenCalledByNonBeneficiary() public {
        vm.prank(friend);
        vm.expectRevert("ONLY BENEFICIARY");
        escrow.allowClaimOnBehalf(friend);
    }

    function testDisallowClaimOnBehalf_fails_whenCalledByNonBeneficiary() public {
        vm.prank(friend);
        vm.expectRevert("ONLY BENEFICIARY");
        escrow.disallowClaimOnBehalf(friend);
    }

}
