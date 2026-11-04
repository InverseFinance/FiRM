// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20, ERC20Wrapper, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {Market, IDolaBorrowingRights, IOracle} from "src/Market.sol";
import {IERC20 as MarketIERC20} from "src/interfaces/IERC20.sol";
import {StakingRewardsEscrow} from "src/escrows/StakingRewardsEscrow.sol";
import {IStakedGovToken, StakingRewardsClaimAndStakeHelper} from "src/util/StakingRewardsClaimAndStakeHelper.sol";
import {EscrowTestToken} from "test/StakingRewardsEscrow.t.sol";
import {StakingRewardsFixture} from "test/mocks/StakingRewardsFixture.sol";

contract StakedGovTokenFixture is ERC20Wrapper {
    constructor(IERC20 rewardToken) ERC20("Staked GOV", "sGOV") ERC20Wrapper(rewardToken) {}
}

contract StakingRewardsClaimAndStakeHelperTest is Test {
    uint256 constant COLLATERAL = 2 ether;
    uint256 constant FUNDING = 1000 ether;
    uint256 constant DURATION = 1000;

    address borrower = makeAddr("borrower");
    address other = makeAddr("other");
    EscrowTestToken reward;
    StakingRewardsFixture pool;
    Market market;
    StakingRewardsEscrow escrow;
    StakedGovTokenFixture stakedGovToken;
    StakingRewardsClaimAndStakeHelper helper;

    function setUp() public {
        EscrowTestToken collateral = new EscrowTestToken();
        reward = new EscrowTestToken();
        pool = new StakingRewardsFixture(address(collateral), address(reward), address(this), DURATION);
        StakingRewardsEscrow implementation = new StakingRewardsEscrow(address(pool));
        market = new Market(
            address(this),
            address(0),
            address(0),
            address(implementation),
            IDolaBorrowingRights(address(0)),
            MarketIERC20(address(collateral)),
            IOracle(address(0)),
            0,
            0,
            1,
            true
        );
        collateral.mint(address(this), COLLATERAL);
        collateral.approve(address(market), COLLATERAL);
        market.deposit(borrower, COLLATERAL);
        escrow = StakingRewardsEscrow(address(market.escrows(borrower)));

        stakedGovToken = new StakedGovTokenFixture(IERC20(address(reward)));
        helper = new StakingRewardsClaimAndStakeHelper(market, IStakedGovToken(address(stakedGovToken)));
        vm.prank(borrower);
        escrow.allowClaimOnBehalf(address(helper));
    }

    function testClaimsAndStakesOnlyNewRewardsForBorrower() public {
        _accrueRewards();
        reward.mint(address(escrow), 1 ether);
        reward.mint(address(helper), 3 ether);
        uint256 claimable = escrow.claimable();

        vm.prank(borrower);
        assertEq(helper.claimAndStake(), claimable);

        assertEq(stakedGovToken.balanceOf(borrower), claimable);
        assertEq(stakedGovToken.balanceOf(address(helper)), 0);
        assertEq(reward.balanceOf(borrower), 0);
        assertEq(reward.balanceOf(address(helper)), 3 ether);
        assertEq(reward.allowance(address(helper), address(stakedGovToken)), 0);
        assertEq(escrow.claimable(), 0);
        assertEq(escrow.balance(), COLLATERAL);
    }

    function testRequiresEscrowAuthorization() public {
        _accrueRewards();
        vm.startPrank(borrower);
        escrow.disallowClaimOnBehalf(address(helper));
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiaryOrAllowlist.selector);
        helper.claimAndStake();
        vm.stopPrank();
        assertEq(escrow.claimable(), FUNDING);
    }

    function testCallerCannotClaimFromAnotherBorrowersEscrow() public {
        _accrueRewards();
        vm.prank(other);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.NoEscrow.selector);
        helper.claimAndStake();
        assertEq(escrow.claimable(), FUNDING);
    }

    function testReturnsZeroWithNoRewards() public {
        vm.prank(borrower);
        assertEq(helper.claimAndStake(), 0);
        assertEq(stakedGovToken.balanceOf(borrower), 0);
    }

    function testClaimRevertsWhenStakeFails() public {
        _accrueRewards();
        vm.mockCall(
            address(stakedGovToken), abi.encodeCall(IStakedGovToken.depositFor, (borrower, FUNDING)), abi.encode(false)
        );

        vm.prank(borrower);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.StakeFailed.selector);
        helper.claimAndStake();

        assertEq(escrow.claimable(), FUNDING);
        assertEq(reward.balanceOf(address(pool)), FUNDING);
        assertEq(reward.balanceOf(address(helper)), 0);
        assertEq(reward.allowance(address(helper), address(stakedGovToken)), 0);
    }

    function testRejectsStakingTokenWithDifferentUnderlying() public {
        EscrowTestToken otherToken = new EscrowTestToken();
        StakedGovTokenFixture wrongToken = new StakedGovTokenFixture(IERC20(address(otherToken)));
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.RewardTokenMismatch.selector);
        new StakingRewardsClaimAndStakeHelper(market, IStakedGovToken(address(wrongToken)));
    }

    function _accrueRewards() private {
        reward.mint(address(pool), FUNDING);
        pool.notifyRewardAmount(FUNDING);
        vm.warp(block.timestamp + DURATION);
    }
}
