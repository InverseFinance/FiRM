// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/RewardDistributor.sol";
import "src/test/mocks/DBR.sol";

contract RewardDistributorTest is Test {
    DBRMock dbr;
    RewardDistributor rewardDistributor;
    address borrower = address(0xA);
    address gov = address(0xB);
    address operator = address(0xC);
    address market = address(0xD);
    address mallory = address(0x1337);

    function setUp() public {
        dbr = new DBRMock();
        dbr.allowMarket(address(market));
        rewardDistributor = new RewardDistributor(address(dbr), gov);
        vm.prank(operator);
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
