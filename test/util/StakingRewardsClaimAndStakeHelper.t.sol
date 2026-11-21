// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20, ERC20Wrapper, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {ERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {Market, IDolaBorrowingRights, IOracle} from "src/Market.sol";
import {IERC20 as MarketIERC20} from "src/interfaces/IERC20.sol";
import {StakingRewardsEscrow} from "src/escrows/StakingRewardsEscrow.sol";
import {
    ICoinDAOFactory,
    IStakedGovToken,
    IYearnVaultRegistry,
    StakingRewardsClaimAndStakeHelper
} from "src/util/StakingRewardsClaimAndStakeHelper.sol";
import {EscrowTestToken} from "test/StakingRewardsEscrow.t.sol";
import {StakingRewardsFixture} from "test/mocks/StakingRewardsFixture.sol";

contract StakedGovTokenFixture is ERC20Wrapper {
    constructor(IERC20 rewardToken) ERC20("Staked GOV", "sGOV") ERC20Wrapper(rewardToken) {}
}

contract CoinDAOFactoryFixture is ICoinDAOFactory {
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

contract YearnVaultRegistryFixture is IYearnVaultRegistry {
    mapping(address => address) private assets;
    mapping(address => uint64) private types;

    function setVault(address vault, address asset, uint64 vaultType) external {
        assets[vault] = asset;
        types[vault] = vaultType;
    }

    function vaultInfo(address vault) external view returns (address, uint96, uint64, uint128, uint64, string memory) {
        return (assets[vault], 0, types[vault], 0, 0, "");
    }
}

contract CompoundVaultFixture is ERC4626 {
    uint256 public depositLimit = type(uint256).max;

    constructor(IERC20 asset_) ERC20("Yearn Vault", "yvGOV") ERC4626(asset_) {}

    function setDepositLimit(uint256 limit) external {
        depositLimit = limit;
    }

    function maxDeposit(address) public view override returns (uint256) {
        return depositLimit;
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
    YearnVaultRegistryFixture yearnRegistry;
    CompoundVaultFixture compoundVault;
    uint256 daoId;
    StakingRewardsClaimAndStakeHelper helper;

    function setUp() public {
        reward = new EscrowTestToken();
        (market, pool) = _createMarket(reward);
        escrow = StakingRewardsEscrow(address(market.escrows(borrower)));

        stakedGovToken = new StakedGovTokenFixture(reward);
        factory = new CoinDAOFactoryFixture();
        daoId = factory.addDeployment(reward, stakedGovToken);
        yearnRegistry = new YearnVaultRegistryFixture();
        compoundVault = new CompoundVaultFixture(reward);
        yearnRegistry.setVault(address(compoundVault), address(reward), 1);
        helper = new StakingRewardsClaimAndStakeHelper(factory, yearnRegistry);
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
        assertEq(helper.claimAndStake(market, daoId), claimable);

        assertEq(stakedGovToken.balanceOf(borrower), claimable);
        assertEq(stakedGovToken.balanceOf(address(helper)), 0);
        assertEq(reward.balanceOf(borrower), 0);
        assertEq(reward.balanceOf(address(helper)), 3 ether);
        assertEq(reward.allowance(address(helper), address(stakedGovToken)), 0);
        assertEq(escrow.claimable(), 0);
        assertEq(escrow.balance(), COLLATERAL);
    }

    function testClaimsAndStakesForSeparateRecipient() public {
        _accrueRewards();

        vm.prank(borrower);
        assertEq(helper.claimAndStakeTo(market, daoId, other), FUNDING);

        assertEq(stakedGovToken.balanceOf(borrower), 0);
        assertEq(stakedGovToken.balanceOf(other), FUNDING);
        assertEq(escrow.claimable(), 0);

        vm.prank(other);
        assertTrue(stakedGovToken.withdrawTo(other, FUNDING));
        assertEq(reward.balanceOf(other), FUNDING);
    }

    function testRejectsZeroAddressAndHelperAsRecipients() public {
        _accrueRewards();

        vm.startPrank(borrower);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.InvalidRecipient.selector);
        helper.claimAndStakeTo(market, daoId, address(0));
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.InvalidRecipient.selector);
        helper.claimAndStakeTo(market, daoId, address(helper));
        vm.stopPrank();

        assertEq(escrow.claimable(), FUNDING);
    }

    function testSharedHelperSupportsMultipleDAOsInConfiguredFactory() public {
        EscrowTestToken secondReward = new EscrowTestToken();
        (Market secondMarket,) = _createMarket(secondReward);
        StakedGovTokenFixture secondStakedGovToken = new StakedGovTokenFixture(secondReward);
        uint256 secondDaoId = factory.addDeployment(secondReward, secondStakedGovToken);
        assertEq(address(helper.factory()), address(factory));
        StakingRewardsEscrow secondEscrow = StakingRewardsEscrow(address(secondMarket.escrows(borrower)));
        _accrueRewards();
        secondReward.mint(address(secondEscrow), 2 ether);

        vm.startPrank(borrower);
        assertEq(helper.claimAndStake(market, daoId), FUNDING);
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiaryOrAllowlist.selector);
        helper.claimAndStake(secondMarket, secondDaoId);
        secondEscrow.allowClaimOnBehalf(address(helper));
        assertEq(helper.claimAndStake(secondMarket, secondDaoId), 2 ether);
        vm.stopPrank();

        assertEq(stakedGovToken.balanceOf(borrower), FUNDING);
        assertEq(secondStakedGovToken.balanceOf(borrower), 2 ether);
    }

    function testConstructorRejectsFactoryWithoutCode() public {
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.InvalidDAOFactory.selector);
        new StakingRewardsClaimAndStakeHelper(ICoinDAOFactory(address(0)), yearnRegistry);

        vm.expectRevert(StakingRewardsClaimAndStakeHelper.InvalidDAOFactory.selector);
        new StakingRewardsClaimAndStakeHelper(ICoinDAOFactory(other), yearnRegistry);
    }

    function testConstructorRejectsYearnRegistryWithoutCode() public {
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.InvalidYearnRegistry.selector);
        new StakingRewardsClaimAndStakeHelper(factory, IYearnVaultRegistry(other));
    }

    function testRejectsUnknownDaoId() public {
        _accrueRewards();
        vm.prank(borrower);
        vm.expectRevert();
        helper.claimAndStake(market, daoId + 1);
        assertEq(escrow.claimable(), FUNDING);
    }

    function testRequiresEscrowAuthorization() public {
        _accrueRewards();
        vm.startPrank(borrower);
        escrow.disallowClaimOnBehalf(address(helper));
        vm.expectRevert(StakingRewardsEscrow.OnlyBeneficiaryOrAllowlist.selector);
        helper.claimAndStake(market, daoId);
        vm.stopPrank();
        assertEq(escrow.claimable(), FUNDING);
    }

    function testCallerWithoutAnEscrowCannotClaim() public {
        _accrueRewards();
        vm.prank(other);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.NoEscrow.selector);
        helper.claimAndStake(market, daoId);
        assertEq(escrow.claimable(), FUNDING);
    }

    function testRejectsAnEscrowFromAnotherBeneficiary() public {
        _accrueRewards();
        vm.mockCall(address(market), abi.encodeWithSignature("escrows(address)", other), abi.encode(address(escrow)));
        vm.prank(other);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.InvalidEscrow.selector);
        helper.claimAndStakeTo(market, daoId, other);
        assertEq(escrow.claimable(), FUNDING);
    }

    function testRejectsAnEscrowFromAnotherMarket() public {
        (Market secondMarket,) = _createMarket(reward);
        _accrueRewards();
        vm.mockCall(
            address(secondMarket), abi.encodeWithSignature("escrows(address)", borrower), abi.encode(address(escrow))
        );
        vm.prank(borrower);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.InvalidEscrow.selector);
        helper.claimAndStake(secondMarket, daoId);
        assertEq(escrow.claimable(), FUNDING);
    }

    function testReturnsZeroWithNoRewards() public {
        vm.prank(borrower);
        assertEq(helper.claimAndStake(market, daoId), 0);
        assertEq(stakedGovToken.balanceOf(borrower), 0);
    }

    function testClaimRevertsWhenStakeFails() public {
        _accrueRewards();
        vm.mockCall(
            address(stakedGovToken), abi.encodeCall(IStakedGovToken.depositFor, (borrower, FUNDING)), abi.encode(false)
        );

        vm.prank(borrower);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.StakeFailed.selector);
        helper.claimAndStake(market, daoId);

        assertEq(escrow.claimable(), FUNDING);
        assertEq(reward.balanceOf(address(pool)), FUNDING);
        assertEq(reward.balanceOf(address(helper)), 0);
        assertEq(reward.allowance(address(helper), address(stakedGovToken)), 0);
    }

    function testRejectsFactoryDeploymentWithDifferentGovToken() public {
        _accrueRewards();
        EscrowTestToken otherToken = new EscrowTestToken();
        StakedGovTokenFixture otherStaker = new StakedGovTokenFixture(otherToken);
        uint256 otherDaoId = factory.addDeployment(otherToken, otherStaker);
        vm.prank(borrower);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.RewardTokenMismatch.selector);
        helper.claimAndStake(market, otherDaoId);
        assertEq(escrow.claimable(), FUNDING);
    }

    function testRejectsFactoryStakerWithDifferentUnderlying() public {
        _accrueRewards();
        EscrowTestToken otherToken = new EscrowTestToken();
        StakedGovTokenFixture wrongStaker = new StakedGovTokenFixture(otherToken);
        uint256 invalidDaoId = factory.addDeployment(reward, wrongStaker);
        vm.prank(borrower);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.RewardTokenMismatch.selector);
        helper.claimAndStake(market, invalidDaoId);
        assertEq(escrow.claimable(), FUNDING);
    }

    function testClaimAndCompoundMintsSharesForBorrowerUsingOnlyNewRewards() public {
        _accrueRewards();
        reward.mint(address(helper), 3 ether);
        assertEq(address(helper.yearnRegistry()), address(yearnRegistry));

        vm.prank(borrower);
        assertEq(helper.claimAndCompound(market, compoundVault, FUNDING), FUNDING);

        assertEq(compoundVault.balanceOf(borrower), FUNDING);
        assertEq(compoundVault.balanceOf(address(helper)), 0);
        assertEq(reward.balanceOf(address(helper)), 3 ether);
        assertEq(reward.allowance(address(helper), address(compoundVault)), 0);
        assertEq(escrow.claimable(), 0);
        assertEq(escrow.balance(), COLLATERAL);
    }

    function testClaimAndCompoundMintsSharesForSeparateRecipient() public {
        _accrueRewards();

        vm.prank(borrower);
        assertEq(helper.claimAndCompoundTo(market, compoundVault, FUNDING, other), FUNDING);

        assertEq(compoundVault.balanceOf(other), FUNDING);
        assertEq(compoundVault.balanceOf(borrower), 0);
        assertEq(escrow.claimable(), 0);
    }

    function testClaimAndCompoundRejectsUnendorsedVaultAndWrongVaultType() public {
        _accrueRewards();
        CompoundVaultFixture unendorsed = new CompoundVaultFixture(reward);

        vm.prank(borrower);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.InvalidCompoundVault.selector);
        helper.claimAndCompound(market, unendorsed, 1);

        yearnRegistry.setVault(address(unendorsed), address(reward), 2);
        vm.prank(borrower);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.InvalidCompoundVault.selector);
        helper.claimAndCompound(market, unendorsed, 1);

        assertEq(escrow.claimable(), FUNDING);
    }

    function testClaimAndCompoundRejectsDifferentAssetEvenIfRegistryRecordMatches() public {
        _accrueRewards();
        EscrowTestToken otherToken = new EscrowTestToken();
        CompoundVaultFixture wrongVault = new CompoundVaultFixture(otherToken);
        yearnRegistry.setVault(address(wrongVault), address(reward), 1);

        vm.prank(borrower);
        vm.expectRevert(StakingRewardsClaimAndStakeHelper.InvalidCompoundVault.selector);
        helper.claimAndCompound(market, wrongVault, 1);

        assertEq(escrow.claimable(), FUNDING);
    }

    function testCompoundDepositFailureLeavesFiRMRewardsClaimable() public {
        _accrueRewards();
        compoundVault.setDepositLimit(0);

        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, borrower, FUNDING, 0));
        helper.claimAndCompound(market, compoundVault, 1);

        assertEq(escrow.claimable(), FUNDING);
        assertEq(reward.balanceOf(address(pool)), FUNDING);
        assertEq(reward.allowance(address(helper), address(compoundVault)), 0);
        assertEq(compoundVault.balanceOf(borrower), 0);

        compoundVault.setDepositLimit(FUNDING);
        vm.prank(borrower);
        assertEq(helper.claimAndCompound(market, compoundVault, FUNDING), FUNDING);
        assertEq(escrow.claimable(), 0);
    }

    function testClaimAndCompoundBelowMinimumRollsBackDepositAndClaim() public {
        _accrueRewards();

        vm.prank(borrower);
        vm.expectRevert(
            abi.encodeWithSelector(StakingRewardsClaimAndStakeHelper.InsufficientShares.selector, FUNDING, FUNDING + 1)
        );
        helper.claimAndCompound(market, compoundVault, FUNDING + 1);

        assertEq(escrow.claimable(), FUNDING);
        assertEq(compoundVault.balanceOf(borrower), 0);
    }

    function _accrueRewards() private {
        reward.mint(address(pool), FUNDING);
        pool.notifyRewardAmount(FUNDING);
        vm.warp(block.timestamp + DURATION);
    }
}
