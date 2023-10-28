// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/DbrDistributor.sol";

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
    mapping (address => bool) public markets;

    function allowMarket(address _market) external {
        markets[_market] = true;
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
    IERC20 public collateral = IERC20(0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68);
    
    function createEscrow(address beneficiary) external returns(INVEscrowMock){
        INVEscrowMock escrow = new INVEscrowMock(address(this), beneficiary);
        escrows[beneficiary] = address(escrow);
        return escrow;
    }

    function changeCollateral(address newCollateral) external {
        collateral = IERC20(newCollateral);
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
        dbr = new DBRMock();
        dbr.allowMarket(address(market));
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

    function testStakeSmallRewardRate() external {
        vm.prank(operator);
        distributor.setRewardRate(10**10);
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

    function testFailNotAllowedMarket() external {
        MarketMock evilMarket = new MarketMock(); 
        INVEscrowMock evilEscrow = market.createEscrow(user);
        vm.prank(address(evilEscrow));
        uint stakeAmount = 10**18;

        vm.expectRevert("UNSUPPORTED MARKET");
        distributor.stake(stakeAmount);
    }

    function testFailNotAllowedCollateral() external {
        MarketMock evilMarket = new MarketMock(); 
        evilMarket.changeCollateral(address(0xb));
        INVEscrowMock evilEscrow = market.createEscrow(user);
        dbr.allowMarket(address(evilMarket));
        vm.prank(address(evilEscrow));
        uint stakeAmount = 10**18;

        vm.expectRevert("UNSUPPORTED MARKET");
        distributor.stake(stakeAmount);
    }

    function testSetRewardRateConstraints() external {
        vm.startPrank(gov);
        
        //Set min
        distributor.setRewardRateConstraints(0, 0);
        assertEq(distributor.minRewardRate(), 0);
        assertEq(distributor.maxRewardRate(), 0);

        //Set max
        uint max = type(uint).max / 3652500 days - 1;
        distributor.setRewardRateConstraints(max, max);
        assertEq(distributor.minRewardRate(), max);
        assertEq(distributor.maxRewardRate(), max);
        vm.stopPrank();
    }

    function testSetRewardRateConstraints_FailWhenMinHigherThanMax() external {
        vm.prank(gov);
        
        //Set min
        vm.expectRevert();
        distributor.setRewardRateConstraints(1, 0);

    }

    function testSetOperator() external {
        vm.expectRevert("ONLY GOV");
        distributor.setOperator(address(0));
        vm.prank(gov);
        distributor.setOperator(address(0));
        assertEq(distributor.operator(), address(0));
    }

    function testSetGov() external {
        vm.expectRevert("ONLY GOV");
        distributor.setGov(address(0));
        vm.prank(gov);
        distributor.setGov(address(0));
        assertEq(distributor.gov(), address(0));
    }
}
