// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/RewardDistributor.sol";
import "src/test/mocks/DBR.sol";
import "src/test/mocks/ERC20.sol";

contract RewardDistributorTest is Test {
    DBRMock dbr;
    RewardDistributor distributor;
    address borrower = address(0xA);
    address gov = address(0xB);
    address operator = address(0xC);
    address market = address(0xD);
    address mallory = address(0x1337);
    ERC20 token1 = new ERC20("Token 1", "TKN1", 18);

    function setUp() public {
        dbr = new DBRMock();
        dbr.allowMarket(address(market));
        distributor = new RewardDistributor(address(dbr), gov);
        deal(address(token1), gov, 1_000_000 ether);
    }

    function test_activateReward_nominal() external {
        vm.startPrank(gov);
        token1.approve(address(distributor), type(uint).max);
        uint rewardRate = 10000;
        uint maxRatePerDebt = 100;
        uint tokenAmount = 100_000 ether;
        distributor.activateReward(address(token1), market, rewardRate, maxRatePerDebt, tokenAmount);
        vm.stopPrank();
        assertEq(distributor.activeMarketRewards(market, 0), address(token1), "token1 not active");
        assertEq(distributor.getLastUpdate(market, address(token1)), block.timestamp, "Lastupdate out of sync");
        assertEq(distributor.getRewardRate(market, address(token1)), rewardRate, "Reward rate set imporproperly");
        assertEq(distributor.getMaxRatePerDebt(market, address(token1)), maxRatePerDebt, "Max rate per debt set imporproperly");
        assertEq(distributor.getSurplus(market, address(token1)), tokenAmount, "Surplus not equal to tokens supplied");
        assertEq(token1.balanceOf(address(distributor)), tokenAmount, "Didn't receive necessary amount");
    }

    function test_activateReward_MultipleRewards() external {
        ERC20 token2 = new ERC20("TOKEN 2", "TKN2", 18);
        deal(address(token2), gov, 1_000_000 ether);
        vm.startPrank(gov);
        token1.approve(address(distributor), type(uint).max);
        token2.approve(address(distributor), type(uint).max);
        uint rewardRate = 10000;
        uint maxRatePerDebt = 100;
        uint tokenAmount = 100_000 ether;
        distributor.activateReward(address(token1), market, rewardRate, maxRatePerDebt, tokenAmount);
        distributor.activateReward(address(token2), market, rewardRate, maxRatePerDebt, tokenAmount);
        vm.stopPrank();
        assertEq(distributor.activeMarketRewards(market, 0), address(token1), "token1 not active");
        assertEq(distributor.getLastUpdate(market, address(token1)), block.timestamp, "Lastupdate out of sync");
        assertEq(distributor.getRewardRate(market, address(token1)), rewardRate, "Reward rate set imporproperly");
        assertEq(distributor.getMaxRatePerDebt(market, address(token1)), maxRatePerDebt, "Max rate per debt set imporproperly");
        assertEq(distributor.getSurplus(market, address(token1)), tokenAmount, "Surplus not equal to tokens supplied");
        assertEq(token1.balanceOf(address(distributor)), tokenAmount, "Didn't receive necessary amount");
        assertEq(distributor.activeMarketRewards(market, 1), address(token2), "token2 not active");
        assertEq(distributor.getLastUpdate(market, address(token2)), block.timestamp, "Lastupdate out of sync");
        assertEq(distributor.getRewardRate(market, address(token2)), rewardRate, "Reward rate set imporproperly");
        assertEq(distributor.getMaxRatePerDebt(market, address(token2)), maxRatePerDebt, "Max rate per debt set imporproperly");
        assertEq(distributor.getSurplus(market, address(token2)), tokenAmount, "Surplus not equal to tokens supplied");
        assertEq(token2.balanceOf(address(distributor)), tokenAmount, "Didn't receive necessary amount");
    }

    function test_activateReward_failsWhenAlreadyActive() external {
        vm.startPrank(gov);
        token1.approve(address(distributor), type(uint).max);
        uint rewardRate = 10000;
        uint maxRatePerDebt = 100;
        uint tokenAmount = 100_000 ether;
        distributor.activateReward(address(token1), market, rewardRate, maxRatePerDebt, tokenAmount);
        vm.expectRevert(abi.encodeWithSelector(RewardDistributor.TokenAlreadyActive.selector, market));
        distributor.activateReward(address(token1), market, rewardRate, maxRatePerDebt, tokenAmount);
        vm.stopPrank();
    }

    function test_activateReward_failsRatesAreZero() external {
        vm.startPrank(gov);
        token1.approve(address(distributor), type(uint).max);
        uint rewardRate = 10000;
        uint maxRatePerDebt = 100;
        uint tokenAmount = 100_000 ether;
        vm.expectRevert(RewardDistributor.ActiveRateCantBeZero.selector);
        distributor.activateReward(address(token1), market, 0, maxRatePerDebt, tokenAmount);
        vm.expectRevert(RewardDistributor.ActiveRateCantBeZero.selector);
        distributor.activateReward(address(token1), market, rewardRate, 0, tokenAmount);
        vm.expectRevert(RewardDistributor.ActiveRateCantBeZero.selector);
        distributor.activateReward(address(token1), market, 0, 0, tokenAmount);
        vm.stopPrank();
    }

    function test_deactivateReward_nominal() external {
        vm.startPrank(gov);
        token1.approve(address(distributor), type(uint).max);
        uint rewardRate = 10000;
        uint maxRatePerDebt = 100;
        uint tokenAmount = 100_000 ether;
        distributor.activateReward(address(token1), market, rewardRate, maxRatePerDebt, tokenAmount);
        vm.warp(block.timestamp + 5);
        distributor.deactivateReward(address(token1), market);
        assertEq(distributor.getActiveRewardsCount(market), 0, "Active rewards not zero");
        assertEq(distributor.getLastUpdate(market, address(token1)), block.timestamp, "Timestamp out of sync");
        assertEq(distributor.getRewardRate(market, address(token1)), 0, "RewardRate not 0");
        assertEq(distributor.getMaxRatePerDebt(market, address(token1)), 0, "max rate per debt not 0");
        vm.stopPrank();
    }

    function test_deactivateReward_FailsWhenRewardNotActive() external {
        vm.startPrank(gov);
        token1.approve(address(distributor), type(uint).max);
        vm.expectRevert(RewardDistributor.TokenInactive.selector);
        distributor.deactivateReward(address(token1), market);
        vm.stopPrank();
    }

    function test_onIncreaseDebt_nominal() external {
        vm.prank(market);
        distributor.onIncreaseDebt(borrower, 1 ether);
        assertEq(distributor.marketBorrowerDebt(market, borrower), 1 ether, "Borrower Market debt not equal to increase");
        assertEq(distributor.marketBorrowerDebt(address(0), borrower), 1 ether, "Borrower Global debt not equal to increase");
        assertEq(distributor.marketDebt(market), 1 ether, "Market debt not equal to increase");
        assertEq(distributor.marketDebt(address(0)), 1 ether, "Global debt not equal to increase");
    }

    /// ******************
    /// * Access Control *
    /// ******************

    function test_onIncreaseDebt_FailsWhenNotMarket() external {
        vm.expectRevert(RewardDistributor.OnlyMarket.selector);
        vm.prank(mallory);
        distributor.onIncreaseDebt(borrower, 1 ether);
    }

    function test_onReduceDebt_FailsWhenNotMarket() external {
        vm.expectRevert(RewardDistributor.OnlyMarket.selector);
        vm.prank(mallory);
        distributor.onReduceDebt(borrower, 1 ether);
    }

    function test_setRewardRate_FailsWhenNotGov() external {
        vm.expectRevert(Governable.OnlyGov.selector);
        vm.prank(mallory);
        distributor.setRewardRate(address(0), address(0), 1);
    }

    function test_setMaxRatePerDebt_FailsWhenNotGov() external {
        vm.expectRevert(Governable.OnlyGov.selector);
        vm.prank(mallory);
        distributor.setMaxRatePerDebt(address(0), address(0), 1);   
    }

    function test_activateReward_FailsWhenNotGov() external {
        vm.expectRevert(Governable.OnlyGov.selector);
        vm.prank(mallory);
        distributor.activateReward(address(0), address(0), 1, 1, 1);
    }

    function test_deactivateReward_FailsWhenNotGov() external {
        vm.expectRevert(Governable.OnlyGov.selector);
        vm.prank(mallory);
        distributor.deactivateReward(address(0), address(0));
    }
    
}
