// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/RewardDistributor.sol";
import "src/test/mocks/DBR.sol";
import "src/test/mocks/ERC20.sol";

contract RewardDistributorTest is Test {
    DBRMock dbr;
    RewardDistributor rewardDistributor;
    address borrower = address(0xA);
    address gov = address(0xB);
    address operator = address(0xC);
    address market = address(0xD);
    address mallory = address(0x1337);
    ERC20 token1 = new ERC20("Token 1", "TKN1", 18);

    function setUp() public {
        dbr = new DBRMock();
        dbr.allowMarket(address(market));
        rewardDistributor = new RewardDistributor(address(dbr), gov);
        deal(address(token1), gov, 10**6 ether);
    }

    function test_activateReward_nominal() external {
        vm.startPrank(gov);
        token1.approve(address(rewardDistributor), uint(-1));
        uint rewardRate = 10000;
        uint maxRatePerDebt = 100;
        uint tokenAmount = 10**5;
        activateReward(address(token1), market, 10000, 20000, tokenAmount);
        vm.stopPrank();
        assertEq(activeMarketRewards[market].length, 1, "More than 1 active rewards");
        assertEq(rewardStates(market, address(token1)).lastUpdate, block.timestamp, "Lastupdate out of sync");
        assertEq(rewardStates(market, address(token1)).rewardRate, rewardRate, "Reward rate set imporproperly");
        assertEq(rewardStates(market, address(token1)).maxRatePerDebt, maxRatePerDebt, "Max rate per debt set imporproperly");
        assertEq(rewardStates(market, address(token1)).surplus, tokenAmount, "Surplus not equal to tokens supplied");
        assertEq(token1.balanceOf(address(rewardDistributor), tokenAmount), "Didn't receive necessary amount");
    }


    /// ******************
    /// * Access Control *
    /// ******************

    function test_onIncreaseDebt_FailsWhenNotMarket() external {
        vm.expectRevert(RewardDistributor.OnlyMarket.selector);
        vm.prank(mallory);
        rewardDistributor.onIncreaseDebt(borrower, 1 ether);
    }

    function test_onReduceDebt_FailsWhenNotMarket() external {
        vm.expectRevert(RewardDistributor.OnlyMarket.selector);
        vm.prank(mallory);
        rewardDistributor.onReduceDebt(borrower, 1 ether);
    }

    function test_setRewardRate_FailsWhenNotGov() external {
        vm.expectRevert(Governable.OnlyGov.selector);
        vm.prank(mallory);
        rewardDistributor.setRewardRate(address(0), address(0), 1);
    }

    function test_setMaxRatePerDebt_FailsWhenNotGov() external {
        vm.expectRevert(Governable.OnlyGov.selector);
        vm.prank(mallory);
        rewardDistributor.setMaxRatePerDebt(address(0), address(0), 1);   
    }

    function test_activateReward_FailsWhenNotGov() external {
        vm.expectRevert(Governable.OnlyGov.selector);
        vm.prank(mallory);
        rewardDistributor.activateReward(address(0), address(0), 1, 1);
    }

    function test_inactivateReward_FailsWhennotGov() external {
        vm.expectRevert(Governable.OnlyGov.selector);
        vm.prank(mallory);
        rewardDistributor.inactivateReward(address(0), address(0));
    }
    
}
