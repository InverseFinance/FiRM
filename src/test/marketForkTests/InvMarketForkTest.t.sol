// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketForkTest.sol";
import "../../BorrowController.sol";
import "../../DBR.sol";
import {Fed} from "../../Fed.sol";
import "../../Market.sol";
import "../../Oracle.sol";
import {DbrDistributor, IDBR} from "../../DbrDistributor.sol";
import {INVEscrow, IXINV, IDbrDistributor} from "../../escrows/INVEscrow.sol";

import "../mocks/ERC20.sol";
import "../mocks/BorrowContract.sol";

contract InvMarketForkTest is MarketForkTest {
    bytes onlyGovUnpause = "Only governance can unpause";
    bytes onlyPauseGuardianOrGov = "Only pause guardian or governance can pause";
    address lender = 0x2b34548b865ad66A2B046cb82e59eE43F75B90fd;
    IERC20 INV =  IERC20(0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68);
    IXINV xINV = IXINV(0x1637e4e9941D55703a7A5E7807d6aDA3f7DCD61B);
    DbrDistributor distributor;

    BorrowContract borrowContract;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        distributor = new DbrDistributor(IDBR(address(dbr)), gov, chair);
        INVEscrow escrow = new INVEscrow(xINV, IDbrDistributor(address(distributor)));
        Market market = new Market(gov, lender, pauseGuardian, address(escrow), IDolaBorrowingRights(address(dbr)), INV, IOracle(address(oracle)), 0, 0, 1, true);
        init(address(market), address(0));
        vm.startPrank(chair, chair);
        fed.expansion(IMarket(address(market)), 100_000e18);
        vm.stopPrank();

        borrowContract = new BorrowContract(address(market), payable(address(collateral)));
    }

    function testDeposit() public {
        gibCollateral(user, testAmount);
        uint balanceUserBefore = collateral.balanceOf(user); 

        vm.startPrank(user, user);
        deposit(testAmount);
        assertEq(market.predictEscrow(user).balance(), testAmount, "Escrow balance did not increase");
        assertEq(collateral.balanceOf(user), balanceUserBefore - testAmount, "User balance did not decrease");
    }

    function testDeposit2() public {
        gibCollateral(user, testAmount);
        uint balanceUserBefore = collateral.balanceOf(user); 

        vm.startPrank(user, user);
        collateral.approve(address(market), testAmount);
        market.deposit(user2, testAmount);
        assertEq(market.predictEscrow(user2).balance(), testAmount, "User2 escrow balance did not increase ");
        assertEq(collateral.balanceOf(user), balanceUserBefore - testAmount, "User balance did not decrease");
        assertEq(collateral.balanceOf(user2), 0, "User2 not 0");
    }

    function testBorrow_Fails() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);
        uint initialDolaBalance = DOLA.balanceOf(user);
        deposit(testAmount);

        vm.expectRevert();
        market.borrow(1);
        
    }

    function testDepositAndBorrow_Fails() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);

        uint initialDolaBalance = DOLA.balanceOf(user);
        uint borrowAmount = 1;
        uint balanceUserBefore = collateral.balanceOf(user); 
        collateral.approve(address(market), testAmount);
        vm.expectRevert();
        market.depositAndBorrow(testAmount, borrowAmount);
    }

    function testBorrowOnBehalf() public {
        address userPk = vm.addr(1);
        gibCollateral(userPk, testAmount);
        gibDBR(userPk, testAmount);
        
        vm.startPrank(userPk, userPk);
        uint maxBorrowAmount = 1;
        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                user2,
                                userPk,
                                maxBorrowAmount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(testAmount);
        vm.stopPrank();

        assertEq(market.predictEscrow(userPk).balance(), testAmount, "failed to deposit collateral");
        assertEq(collateral.balanceOf(userPk), 0, "failed to deposit collateral");

        vm.startPrank(user2, user2);
        vm.expectRevert();
        market.borrowOnBehalf(userPk, maxBorrowAmount, block.timestamp, v, r, s);
    }


    function testRepay_Fails_WhenAmountGtThanDebt() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        gibDOLA(user, 500e18);

        vm.startPrank(user, user);

        deposit(testAmount);
        
        vm.expectRevert("Repayment greater than debt");
        market.repay(user, 1);
    }

    function testGetWithdrawalLimit_Returns_CollateralBalance() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);

        vm.startPrank(user, user);
        deposit(testAmount);

        uint collateralBalance = market.escrows(user).balance();
        assertEq(collateralBalance, testAmount);
        assertEq(market.getWithdrawalLimit(user), collateralBalance, "Should return collateralBalance when user's escrow balance > 0 & debts = 0");
    }

    function testGetWithdrawalLimit_Returns_0_WhenEscrowBalanceIs0() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);

        vm.startPrank(user, user);
        deposit(testAmount);

        uint collateralBalance = market.escrows(user).balance();
        assertEq(collateralBalance, testAmount);

        market.withdraw(market.getWithdrawalLimit(user));
        assertEq(market.getWithdrawalLimit(user), 0, "Should return 0 when user's escrow balance is 0");
    }

    function testPauseBorrows() public {
        vm.startPrank(gov);

        market.pauseBorrows(true);
        assertEq(market.borrowPaused(), true, "Market wasn't paused");
        market.pauseBorrows(false);
        assertEq(market.borrowPaused(), false, "Market wasn't unpaused");

        vm.stopPrank();
        vm.startPrank(pauseGuardian);
        market.pauseBorrows(true);
        assertEq(market.borrowPaused(), true, "Market wasn't paused");
        vm.expectRevert(onlyGovUnpause);
        market.pauseBorrows(false);
        vm.stopPrank();

        vm.startPrank(user, user);
        vm.expectRevert(onlyPauseGuardianOrGov);
        market.pauseBorrows(true);

        vm.expectRevert(onlyGovUnpause);
        market.pauseBorrows(false);
    }

    function testWithdraw() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);

        deposit(testAmount);

        assertEq(market.predictEscrow(user).balance(), testAmount, "failed to deposit collateral");
        assertEq(collateral.balanceOf(user), 0, "failed to deposit collateral");

        market.withdraw(market.getWithdrawalLimit(user));

        assertEq(market.predictEscrow(user).balance(), 0, "failed to withdraw collateral");
        assertEq(collateral.balanceOf(user), testAmount, "failed to withdraw collateral");
    }

    function testWithdraw_When_TimePassed() public {
        gibCollateral(user, testAmount);
        gibDBR(user, testAmount);
        vm.startPrank(user, user);

        deposit(testAmount);

        assertEq(market.predictEscrow(user).balance(), testAmount, "failed to deposit collateral");
        assertEq(collateral.balanceOf(user), 0, "failed to deposit collateral");
        
        emit log_uint(market.getWithdrawalLimit(user));
        vm.roll(block.number+10);
        vm.warp(block.timestamp+110);
        market.withdraw(1000);
        emit log_uint(market.getWithdrawalLimit(user));
        market.withdraw(testAmount);

        assertGt(market.predictEscrow(user).balance(), 0, "failed to withdraw collateral");
        assertEq(collateral.balanceOf(user), testAmount, "failed to withdraw collateral");
    }

    function testWithdrawOnBehalf() public {
        address userPk = vm.addr(1);
        gibCollateral(userPk, testAmount);
        gibDBR(userPk, testAmount);
        
        vm.startPrank(userPk);
        deposit(testAmount);
        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                user2,
                                userPk,
                                market.getWithdrawalLimit(userPk),
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);
        vm.stopPrank();

        assertEq(market.predictEscrow(userPk).balance(), testAmount, "failed to deposit collateral");
        assertEq(collateral.balanceOf(userPk), 0, "failed to deposit collateral");

        vm.startPrank(user2);
        market.withdrawOnBehalf(userPk, market.getWithdrawalLimit(userPk), block.timestamp, v, r, s);

        assertEq(distributor.balanceOf(address(market.predictEscrow(userPk))), 0, "failed to withdraw collateral");
        assertEq(collateral.balanceOf(user2), testAmount, "failed to withdraw collateral");
    }

    function testWithdrawOnBehalf_When_InvalidateNonceCalledPrior() public {
        address userPk = vm.addr(1);
        gibCollateral(userPk, testAmount);
        gibDBR(userPk, testAmount);
        
        vm.startPrank(userPk);
        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                user2,
                                userPk,
                                testAmount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(testAmount);
        market.invalidateNonce();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert("INVALID_SIGNER");
        market.withdrawOnBehalf(userPk, testAmount, block.timestamp, v, r, s);
    }

    function testWithdrawOnBehalf_When_DeadlineHasPassed() public {
        address userPk = vm.addr(1);
        gibCollateral(userPk, testAmount);
        gibDBR(userPk, testAmount);

        uint timestamp = block.timestamp;
        
        vm.startPrank(userPk);
        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                user2,
                                userPk,
                                testAmount,
                                0,
                                timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        deposit(testAmount);
        market.invalidateNonce();
        vm.stopPrank();

        vm.startPrank(user2);
        vm.warp(block.timestamp + 1);
        vm.expectRevert("DEADLINE_EXPIRED");
        market.withdrawOnBehalf(userPk, testAmount, timestamp, v, r, s);
    }

    //Access Control Tests

    function test_accessControl_setOracle() public {
        vm.startPrank(gov);
        market.setOracle(IOracle(address(0)));
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setOracle(IOracle(address(0)));
    }

    function test_accessControl_setBorrowController() public {
        vm.startPrank(gov);
        market.setBorrowController(IBorrowController(address(0)));
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setBorrowController(IBorrowController(address(0)));
    }

    function test_accessControl_setGov() public {
        vm.startPrank(gov);
        market.setGov(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setGov(address(0));
    }

    function test_accessControl_setLender() public {
        vm.startPrank(gov);
        market.setLender(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setLender(address(0));
    }

    function test_accessControl_setPauseGuardian() public {
        vm.startPrank(gov);
        market.setPauseGuardian(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setPauseGuardian(address(0));
    }

    function test_accessControl_setCollateralFactorBps() public {
        vm.startPrank(gov);
        market.setCollateralFactorBps(100);

        vm.expectRevert("Invalid collateral factor");
        market.setCollateralFactorBps(10001);
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setCollateralFactorBps(100);
    }

    function test_accessControl_setReplenismentIncentiveBps() public {
        vm.startPrank(gov);
        market.setReplenismentIncentiveBps(100);

        vm.expectRevert("Invalid replenishment incentive");
        market.setReplenismentIncentiveBps(10001);
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setReplenismentIncentiveBps(100);
    }

    function test_accessControl_setLiquidationIncentiveBps() public {
        vm.startPrank(gov);
        market.setLiquidationIncentiveBps(100);

        vm.expectRevert("Invalid liquidation incentive");
        market.setLiquidationIncentiveBps(0);
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setLiquidationIncentiveBps(100);
    }

    function test_accessControl_setLiquidationFactorBps() public {
        vm.startPrank(gov);
        market.setLiquidationFactorBps(100);

        vm.expectRevert("Invalid liquidation factor");
        market.setLiquidationFactorBps(0);
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setLiquidationFactorBps(100);
    }

    function test_accessControl_setLiquidationFeeBps() public {
        vm.startPrank(gov);
        market.setLiquidationFeeBps(100);

        vm.expectRevert("Invalid liquidation fee");
        market.setLiquidationFeeBps(0);
        vm.stopPrank();

        vm.expectRevert(onlyGov);
        market.setLiquidationFeeBps(100);
    }

    function test_accessControl_recall() public {
        vm.startPrank(address(fed));
        market.recall(100e18);
        vm.stopPrank();

        vm.expectRevert(onlyLender);
        market.recall(100e18);
    }
}
