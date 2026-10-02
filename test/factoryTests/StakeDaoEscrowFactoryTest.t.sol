// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Market, IOracle, IDolaBorrowingRights} from "src/Market.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {StakeDaoEscrow, IRewardVault} from "src/escrows/StakeDaoEscrow.sol";
import {StakeDaoEscrowFactory} from "src/factory/StakeDaoEscrowFactory.sol";

contract StakeDaoEscrowFactoryTest is Test {
    uint256 internal constant FORK_BLOCK = 25_076_112;

    address internal constant GOV = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address internal constant LENDER = address(0xA11CE);
    address internal constant PAUSE_GUARDIAN = address(0xB0B);
    address internal constant TREASURY = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address internal constant USER = address(0xBEEF);

    address internal constant DBR = 0xAD038Eb671c44b853887A7E32528FaB35dC5D710;
    address internal constant REWARD_VAULT = 0xCA137e3853Eab95541290B372223e7F2ee4c0cFa;
    address internal constant CRV_FRX_USD_LP = 0x13e12BB0E6A2f1A3d6901a59a9d585e89A6243e1;
    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    uint256 internal constant DEPOSIT_AMOUNT = 10_000 ether;

    IERC20 internal lpToken;
    IRewardVault internal rewardVault;
    StakeDaoEscrowFactory internal factory;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, FORK_BLOCK);

        lpToken = IERC20(CRV_FRX_USD_LP);
        rewardVault = IRewardVault(REWARD_VAULT);
        factory = new StakeDaoEscrowFactory();
    }

    function testDeployEscrowImplementation() public {
        address implementationAddress = factory.deployEscrow(REWARD_VAULT, TREASURY);
        StakeDaoEscrow implementation = StakeDaoEscrow(implementationAddress);

        assertTrue(factory.isFromFactory(implementationAddress));
        assertEq(address(implementation.rewardVault()), REWARD_VAULT);
        assertEq(address(implementation.accountant()), rewardVault.ACCOUNTANT());
        assertEq(implementation.gauge(), rewardVault.gauge());
        assertEq(implementation.baseRewardToken(), CRV);
        assertEq(implementation.treasury(), TREASURY);
    }

    function testFactoryEscrowImplementationWorksWithMarket() public {
        address implementationAddress = factory.deployEscrow(REWARD_VAULT, TREASURY);
        Market market = _deployMarket(implementationAddress);
        StakeDaoEscrow escrow = StakeDaoEscrow(address(market.predictEscrow(USER)));

        deal(CRV_FRX_USD_LP, USER, DEPOSIT_AMOUNT, false);

        vm.startPrank(USER, USER);
        lpToken.approve(address(market), DEPOSIT_AMOUNT);
        market.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();

        assertEq(address(escrow.market()), address(market));
        assertEq(escrow.beneficiary(), USER);
        assertEq(address(escrow.token()), CRV_FRX_USD_LP);
        assertEq(address(escrow.rewardVault()), REWARD_VAULT);
        assertEq(lpToken.balanceOf(address(escrow)), 0);
        assertEq(rewardVault.balanceOf(address(escrow)), DEPOSIT_AMOUNT);
        assertEq(escrow.balance(), DEPOSIT_AMOUNT);
    }

    function _deployMarket(address implementationAddress) internal returns (Market market) {
        market = new Market(
            GOV,
            LENDER,
            PAUSE_GUARDIAN,
            implementationAddress,
            IDolaBorrowingRights(DBR),
            IERC20(CRV_FRX_USD_LP),
            IOracle(address(0)),
            5000,
            5000,
            1000,
            true
        );
    }
}
