// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../DbrDistributor.sol";

contract INVEscrowMock is IINVEscrow {
    address public market;
    address public beneficiary;
    
    constructor(address _market, address _beneficiary) {
        market = _market;
        beneficiary = _beneficiary;
    }
}

contract DBRMock is IDBR {
    address market;
    mapping (address => uint) balances;

    constructor(address _market){
        market = _market;
    }
    
    function markets(address _market) external view returns(bool){
        return _market == market;
    }

    function balanceOf(address holder) external view returns(uint){
        return balances[holder];
    }

    function mint(address user, uint amount) external {
        balances[user] += amount;
    }
}

contract MarketMock is IMarket {
    mapping(address => address) public escrows;
    
    function createEscrow(address beneficiary) external returns(INVEscrowMock){
        INVEscrowMock escrow = new INVEscrowMock(address(this), beneficiary);
        escrows[beneficiary] = address(escrow);
        return escrow;
    }
}

contract DbrDistributorTest is Test {
    MarketMock market;
    DBRMock dbr;
    INVEscrowMock escrow;
    DbrDistributor distributor;
    address user = address(0xA);
    address gov = address(0xB);
    address operator = address(0xC);

    function setUp() public {
        market = new MarketMock();
        dbr = new DBRMock(address(market));
        escrow = market.createEscrow(user);
        distributor = new DbrDistributor(IDBR(dbr), gov, operator);
        vm.prank(operator);
        distributor.setRewardRate(10**18);
    }

    function testStake() external {
        vm.prank(address(escrow));
        uint stakeAmount = 10**18;
        distributor.stake(stakeAmount);

        assertEq(distributor.balanceOf(address(escrow)), stakeAmount);
        vm.warp(block.timestamp + 12);
        assertEq(distributor.claimable(address(escrow)), 12 * distributor.rewardRate());
    }

    function testMultiStake() external {
        address user2 = address(0x1);
        INVEscrowMock escrow2 = market.createEscrow(user2);

        vm.prank(address(escrow));
        uint stakeAmount = 10**18;
        distributor.stake(stakeAmount);

        vm.prank(address(escrow2));
        distributor.stake(stakeAmount);

        vm.warp(block.timestamp + 12);
        assertEq(distributor.claimable(address(escrow)), 12 * distributor.rewardRate() / 2);
    }

    function testUnstake() external {
        vm.startPrank(address(escrow));
        uint stakeAmount = 10**18;
        distributor.stake(stakeAmount);
        distributor.unstake(stakeAmount / 2);
        vm.stopPrank();

        assertEq(distributor.balanceOf(address(escrow)), stakeAmount / 2);
    }

    function testClaim() external {
        vm.startPrank(address(escrow));
        uint stakeAmount = 10**18;
        distributor.stake(stakeAmount);
        vm.warp(block.timestamp + 12);

        distributor.claim(user);
        vm.stopPrank();
        assertEq(dbr.balanceOf(user), 12 * distributor.rewardRate());
        assertEq(distributor.claimable(address(escrow)), 0);
    }

    function testClaimAfterUnstake() external {
        vm.startPrank(address(escrow));
        uint stakeAmount = 10**18;
        distributor.stake(stakeAmount);
        vm.warp(block.timestamp + 12);
        distributor.unstake(stakeAmount);

        distributor.claim(user);
        vm.stopPrank();
        assertEq(dbr.balanceOf(user), 12 * distributor.rewardRate());
        assertEq(distributor.claimable(address(escrow)), 0);
    }
}
