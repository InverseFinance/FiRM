// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20, ERC20Wrapper, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {Market, IDolaBorrowingRights, IOracle} from "src/Market.sol";
import {IERC20 as MarketIERC20} from "src/interfaces/IERC20.sol";
import {StakingRewardsEscrow} from "src/escrows/StakingRewardsEscrow.sol";
import {
    ICoinDAOFactory,
    IStakedGovToken,
    StakingRewardsClaimAndStakeHelper
} from "src/util/StakingRewardsClaimAndStakeHelper.sol";
import {EscrowTestToken} from "test/StakingRewardsEscrow.t.sol";
import {StakingRewardsFixture} from "test/mocks/StakingRewardsFixture.sol";

contract StakedGovTokenFixture is ERC20Wrapper {
    constructor(IERC20 rewardToken) ERC20("Staked GOV", "sGOV") ERC20Wrapper(rewardToken) {}
}

contract CoinDAOFactoryFixture {
    ICoinDAOFactory.Deployment[] private records;

    function deployments(uint256 id) external view returns (ICoinDAOFactory.Deployment memory) {
        return records[id];
    }

    function addDeployment(IERC20 govToken, StakedGovTokenFixture staker) external returns (uint256 daoId) {
        daoId = records.length;
        ICoinDAOFactory.Deployment storage deployment = records.push();
        deployment.govToken = govToken;
        deployment.staker = IStakedGovToken(address(staker));
    }
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
    CoinDAOFactoryFixture factory;
    uint256 daoId;
    StakingRewardsClaimAndStakeHelper helper;

    function setUp() public {
        reward = new EscrowTestToken();
        (market, pool) = _createMarket(reward);
        escrow = StakingRewardsEscrow(address(market.escrows(borrower)));

        stakedGovToken = new StakedGovTokenFixture(reward);
        factory = new CoinDAOFactoryFixture();
        daoId = factory.addDeployment(reward, stakedGovToken);
        helper = new StakingRewardsClaimAndStakeHelper(ICoinDAOFactory(address(factory)));
        helper.registerMarket(market, daoId);
        vm.prank(borrower);
        escrow.allowClaimOnBehalf(address(helper));
    }

    function _createMarket(EscrowTestToken rewardToken)
        private
        returns (Market newMarket, StakingRewardsFixture newPool)
    {
        EscrowTestToken collateral = new EscrowTestToken();
        newPool = new StakingRewardsFixture(address(collateral), address(rewardToken), address(this), DURATION);
        StakingRewardsEscrow implementation = new StakingRewardsEscrow(address(newPool));
        newMarket = new Market(
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
        collateral.approve(address(newMarket), COLLATERAL);
        newMarket.deposit(borrower, COLLATERAL);
    }

    function testClaimsAndStakesOnlyNewRewardsForBorrower() public {
        _accrueRewards();
        reward.mint(address(escrow), 1 ether);
        reward.mint(address(helper), 3 ether);
        uint256 claimable = escrow.claimable();

        vm.prank(borrower);
        assertEq(helper.claimAndStake(market), claimable);

        assertEq(stakedGovToken.balanceOf(borrower), claimable);
        assertEq(stakedGovToken.balanceOf(address(helper)), 0);
        assertEq(reward.balanceOf(borrower), 0);
        assertEq(reward.balanceOf(address(helper)), 3 ether);
        assertEq(reward.allowance(address(helper), address(stakedGovToken)), 0);
        assertEq(escrow.claimable(), 0);
        assertEq(escrow.balance(), COLLATERAL);
    }

    function testSharedHelperRoutesEachMarketToItsRegisteredStakingToken() public {
        EscrowTestToken secondReward = new EscrowTestToken();
        (Market secondMarket,) = _createMarket(secondReward);
        StakedGovTokenFixture secondStakedGovToken = new StakedGovTokenFixture(secondReward);
        uint256 secondDaoId = factory.addDeployment(secondReward, secondStakedGovToken);
        helper.registerMarket(secondMarket, secondDaoId);
        StakingRewardsEscrow secondEscrow = StakingRewardsEscrow(address(secondMarket.escrows(borrower)));
        _accrueRewards();
        secondReward.mint(address(secondEscrow), 2 ether);

        vm.startPrank(borrower);
        assertEq(helper.claimAndStake(market), FUNDING);
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiaryOrAllowlist.selector);
        helper.claimAndStake(secondMarket);
        secondEscrow.allowClaimOnBehalf(address(helper));
        assertEq(helper.claimAndStake(secondMarket), 2 ether);
        vm.stopPrank();

        assertEq(stakedGovToken.balanceOf(borrower), FUNDING);
        assertEq(secondStakedGovToken.balanceOf(borrower), 2 ether);
    }

    function testRejectsUnregisteredMarket() public {
        (Market unregisteredMarket,) = _createMarket(reward);
        vm.prank(borrower);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.MarketNotRegistered.selector);
        helper.claimAndStake(unregisteredMarket);
    }

    function testAnyoneCanRegisterMarketWithMatchingFactoryDeployment() public {
        (Market unregisteredMarket,) = _createMarket(reward);
        vm.prank(other);
        helper.registerMarket(unregisteredMarket, daoId);

        (IERC20 registeredReward, IStakedGovToken registeredToken) = helper.markets(unregisteredMarket);
        assertEq(address(registeredReward), address(reward));
        assertEq(address(registeredToken), address(stakedGovToken));
    }

    function testCannotReplaceRegisteredStakingToken() public {
        StakedGovTokenFixture replacement = new StakedGovTokenFixture(reward);
        uint256 replacementId = factory.addDeployment(reward, replacement);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.MarketAlreadyRegistered.selector);
        helper.registerMarket(market, replacementId);
        (, IStakedGovToken registeredToken) = helper.markets(market);
        assertEq(address(registeredToken), address(stakedGovToken));
    }

    function testRequiresEscrowAuthorization() public {
        _accrueRewards();
        vm.startPrank(borrower);
        escrow.disallowClaimOnBehalf(address(helper));
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiaryOrAllowlist.selector);
        helper.claimAndStake(market);
        vm.stopPrank();
        assertEq(escrow.claimable(), FUNDING);
    }

    function testCallerWithoutAnEscrowCannotClaim() public {
        _accrueRewards();
        vm.prank(other);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.NoEscrow.selector);
        helper.claimAndStake(market);
        assertEq(escrow.claimable(), FUNDING);
    }

    function testRejectsAnEscrowWithADifferentBeneficiary() public {
        _accrueRewards();
        vm.mockCall(address(market), abi.encodeWithSignature("escrows(address)", other), abi.encode(address(escrow)));
        vm.prank(other);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.InvalidEscrow.selector);
        helper.claimAndStake(market);
        assertEq(escrow.claimable(), FUNDING);
    }

    function testRejectsAnEscrowFromAnotherMarket() public {
        (Market secondMarket,) = _createMarket(reward);
        helper.registerMarket(secondMarket, daoId);
        _accrueRewards();
        vm.mockCall(
            address(secondMarket), abi.encodeWithSignature("escrows(address)", borrower), abi.encode(address(escrow))
        );
        vm.prank(borrower);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.InvalidEscrow.selector);
        helper.claimAndStake(secondMarket);
        assertEq(escrow.claimable(), FUNDING);
    }

    function testReturnsZeroWithNoRewards() public {
        vm.prank(borrower);
        assertEq(helper.claimAndStake(market), 0);
        assertEq(stakedGovToken.balanceOf(borrower), 0);
    }

    function testClaimRevertsWhenStakeFails() public {
        _accrueRewards();
        vm.mockCall(
            address(stakedGovToken), abi.encodeCall(IStakedGovToken.depositFor, (borrower, FUNDING)), abi.encode(false)
        );

        vm.prank(borrower);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.StakeFailed.selector);
        helper.claimAndStake(market);

        assertEq(escrow.claimable(), FUNDING);
        assertEq(reward.balanceOf(address(pool)), FUNDING);
        assertEq(reward.balanceOf(address(helper)), 0);
        assertEq(reward.allowance(address(helper), address(stakedGovToken)), 0);
    }

    function testRejectsFactoryDeploymentWithDifferentGovToken() public {
        (Market unregisteredMarket,) = _createMarket(reward);
        EscrowTestToken otherToken = new EscrowTestToken();
        StakedGovTokenFixture otherStaker = new StakedGovTokenFixture(otherToken);
        uint256 otherDaoId = factory.addDeployment(otherToken, otherStaker);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.RewardTokenMismatch.selector);
        helper.registerMarket(unregisteredMarket, otherDaoId);
    }

    function testRejectsFactoryStakerWithDifferentUnderlying() public {
        (Market unregisteredMarket,) = _createMarket(reward);
        EscrowTestToken otherToken = new EscrowTestToken();
        StakedGovTokenFixture wrongStaker = new StakedGovTokenFixture(otherToken);
        uint256 invalidDaoId = factory.addDeployment(reward, wrongStaker);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.RewardTokenMismatch.selector);
        helper.registerMarket(unregisteredMarket, invalidDaoId);
    }

    function _accrueRewards() private {
        reward.mint(address(pool), FUNDING);
        pool.notifyRewardAmount(FUNDING);
        vm.warp(block.timestamp + DURATION);
    }
}
