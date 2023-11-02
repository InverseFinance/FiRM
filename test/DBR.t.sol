// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./FiRMBaseTest.sol";

contract DBRTest is FiRMBaseTest {
    address operator;

    bytes onlyPendingOperator = "ONLY PENDING OPERATOR";
    bytes onlyMinterOperator = "ONLY MINTERS OR OPERATOR";
    bytes onBorrowError = "Only markets can call onBorrow";
    bytes onRepayError = "Only markets can call onRepay";
    bytes onForceReplenishError = "Only markets can call onForceReplenish";

    function setUp() public {
        vm.label(gov, "operator");
        operator = gov;

        initialize(replenishmentPriceBps, collateralFactorBps, replenishmentIncentiveBps, liquidationBonusBps, callOnDepositCallback);

        vm.startPrank(chair);
        fed.expansion(IMarket(address(market)), 1_000_000e18);
        vm.stopPrank();
    }

    function testOnBorrow_Reverts_When_AccrueDueTokensBringsUserDbrBelow0() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount);

        vm.startPrank(user, user);

        deposit(wethTestAmount);
        uint borrowAmount = wethTestAmount * ethFeed.latestAnswer() * collateralFactorBps / 1e18 / 10_000;
        market.borrow(borrowAmount / 2);

        vm.warp(block.timestamp + 7 days);
        ethFeed.changeUpdatedAt(block.timestamp);

        vm.expectRevert("DBR Deficit");
        market.borrow(borrowAmount / 2);
    }

    function test_BalanceFunctions_ReturnCorrectBalance_WhenAddressHasDeficit() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount / 20);

        vm.startPrank(user, user);
        deposit(wethTestAmount);
        uint borrowAmount = 1 ether;
        market.borrow(borrowAmount);

        vm.warp(block.timestamp + 365 days);

        assertEq(dbr.balanceOf(user), 0, "balanceOf should be 0 when user has deficit");
        //We give user 0.05 DBR. Borrow 1 DOLA for 1 year, expect to pay 1 DBR. -0.95 DBR should be the deficit.
        assertEq(dbr.deficitOf(user), borrowAmount * 19 / 20, "incorrect deficitOf");
        assertEq(dbr.signedBalanceOf(user), int(0) - int(dbr.deficitOf(user)), "signedBalanceOf should equal negative deficitOf when there is a deficit");

        //ensure balances are the same after accrueDueTokens is called
        dbr.accrueDueTokens(user);
        assertEq(dbr.balanceOf(user), 0, "balanceOf should be 0 when user has deficit");
        assertEq(dbr.deficitOf(user), borrowAmount * 19 / 20, "incorrect deficitOf");
        assertEq(dbr.signedBalanceOf(user), int(0) - int(dbr.deficitOf(user)), "signedBalanceOf should equal negative deficitOf when there is a deficit");
    }

    function test_BalanceFunctions_ReturnCorrectBalance_WhenAddressHasPositiveBalance() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, wethTestAmount * 2);

        vm.startPrank(user, user);
        deposit(wethTestAmount);

        uint borrowAmount = wethTestAmount;
        market.borrow(borrowAmount);

        vm.warp(block.timestamp + 365 days);

        assertEq(dbr.deficitOf(user), 0, "deficitOf should be 0 when user has deficit");
        //We give user 2 DBR. Borrow 1 DOLA for 1 year, expect to pay 1 DBR. 1 DBR should be left as the balance.
        assertEq(dbr.balanceOf(user), borrowAmount, "incorrect dbr balance");
        assertEq(dbr.signedBalanceOf(user), int(dbr.balanceOf(user)), "signedBalanceOf should equal balanceOf when there is a positive balance");

         //ensure balances are the same after accrueDueTokens is called
        dbr.accrueDueTokens(user);
        assertEq(dbr.deficitOf(user), 0, "deficitOf should be 0 when user has deficit");
        assertEq(dbr.balanceOf(user), borrowAmount, "incorrect dbr balance");
        assertEq(dbr.signedBalanceOf(user), int(dbr.balanceOf(user)), "signedBalanceOf should equal balanceOf when there is a positive balance");
    }

    function test_BalanceFunctions_ReturnCorrectBalance_WhenAddressHasZeroBalance() public {
        assertEq(dbr.deficitOf(user), 0, "deficitOf should be 0 when user has no balance");
        assertEq(dbr.balanceOf(user), 0, "balanceOf should be 0 when user has no balance");
        assertEq(dbr.signedBalanceOf(user), 0, "signedBalanceOf should be 0 when user has no balance");

         //ensure balances are the same after accrueDueTokens is called
        dbr.accrueDueTokens(user);
        assertEq(dbr.deficitOf(user), 0, "deficitOf should be 0 when user has no balance");
        assertEq(dbr.balanceOf(user), 0, "balanceOf should be 0 when user has no balance");
        assertEq(dbr.signedBalanceOf(user), 0, "signedBalanceOf should be 0 when user has no balance");
    }

    function test_burn() public {
        vm.startPrank(operator);
        dbr.mint(user, 1e18);
        vm.stopPrank();

        assertEq(dbr.totalSupply(), 1e18, "dbr mint failed");
        assertEq(dbr.balanceOf(user), 1e18, "dbr mint failed");

        vm.startPrank(user, user);
        dbr.burn(1e18);

        assertEq(dbr.totalSupply(), 0, "dbr burn failed");
        assertEq(dbr.balanceOf(user), 0, "dbr burn failed");
    }

    function test_burn_reverts_whenAmountGtCallerBalance() public {
        gibDBR(user, 1e18);

        vm.startPrank(user, user);
        vm.expectRevert("Insufficient balance");
        dbr.burn(2e18);
    }

    function test_totalSupply() public {
        vm.startPrank(operator);
        dbr.mint(user, 100e18);

        assertEq(dbr.totalSupply(), 100e18, "Incorrect total supply");
    }

    function test_totalSupply_returns0_whenTotalDueTokensAccruedGtSupply() public {
        gibWeth(user, wethTestAmount);
        gibDBR(user, 1);

        vm.startPrank(user, user);    
        deposit(wethTestAmount);

        market.borrow(getMaxBorrowAmount(wethTestAmount));
        vm.warp(block.timestamp + 365 days);

        dbr.accrueDueTokens(user);        
        assertEq(dbr.totalSupply(), 0, "Incorrect total supply");
    }

    function test_invalidateNonce() public {
        assertEq(dbr.nonces(user), 0, "User nonce should be uninitialized");

        vm.startPrank(user, user);
        dbr.invalidateNonce();

        assertEq(dbr.nonces(user), 1, "User nonce was not invalidated");
    }

    function test_approve_increasesAllowanceByAmount() public {
        uint amount = 100e18;

        assertEq(dbr.allowance(user, gov), 0, "Allowance should not be set yet");

        vm.startPrank(user, user);
        dbr.approve(gov, amount);

        assertEq(dbr.allowance(user, gov), amount, "Allowance was not set properly");
    }

    function test_permit_increasesAllowanceByAmount() public {
        uint amount = 100e18;
        address userPk = vm.addr(1);

        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        dbr.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                userPk,
                                gov,
                                amount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        assertEq(dbr.allowance(userPk, gov), 0, "Allowance should not be set yet");

        vm.startPrank(gov);
        dbr.permit(userPk, gov, amount, block.timestamp, v, r, s);

        assertEq(dbr.allowance(userPk, gov), amount, "Allowance was not set properly");
    }

    function test_permit_reverts_whenDeadlinesHasPassed() public {
        uint amount = 100e18;
        address userPk = vm.addr(1);

        uint timestamp = block.timestamp;

        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        dbr.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                userPk,
                                gov,
                                amount,
                                0,
                                timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        assertEq(dbr.allowance(userPk, gov), 0, "Allowance should not be set yet");

        vm.startPrank(gov);
        vm.warp(block.timestamp + 1);
        vm.expectRevert("PERMIT_DEADLINE_EXPIRED");
        dbr.permit(userPk, gov, amount, timestamp, v, r, s);
    }

    function test_permit_reverts_whenNonceInvaidated() public {
        uint amount = 100e18;
        address userPk = vm.addr(1);

        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        dbr.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                userPk,
                                gov,
                                amount,
                                0,
                                block.timestamp
                            )
                        )
                    )
                );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        vm.startPrank(userPk);
        dbr.invalidateNonce();
        vm.stopPrank();

        assertEq(dbr.allowance(userPk, gov), 0, "Allowance should not be set yet");

        vm.startPrank(gov);
        vm.expectRevert("INVALID_SIGNER");
        dbr.permit(userPk, gov, amount, block.timestamp, v, r, s);
    }

    function test_transfer() public {
        uint amount = 100e18;

        vm.startPrank(operator);
        dbr.mint(user, amount * 2);
        vm.stopPrank();

        assertEq(dbr.balanceOf(user), amount * 2);
        assertEq(dbr.balanceOf(gov), 0);
        vm.startPrank(user, user);
        dbr.transfer(gov, amount);
        assertEq(dbr.balanceOf(user), amount);
        assertEq(dbr.balanceOf(gov), amount);
    }

    function test_transfer_reverts_whenAmountGtCallerBalance() public {
        uint amount = 100e18;

        vm.startPrank(operator);
        dbr.mint(user, amount / 2);
        vm.stopPrank();

        vm.startPrank(user, user);
        vm.expectRevert("Insufficient balance");
        dbr.transfer(gov, amount);
    }

    function test_transferFrom() public {
        uint amount = 100e18;

        vm.startPrank(operator);
        dbr.mint(user, amount * 2);
        vm.stopPrank();

        assertEq(dbr.balanceOf(user), amount * 2);
        assertEq(dbr.balanceOf(gov), 0);

        vm.startPrank(user, user);
        dbr.approve(gov, amount);
        vm.stopPrank();

        vm.startPrank(gov);
        dbr.transferFrom(user, gov, amount);

        assertEq(dbr.balanceOf(user), amount);
        assertEq(dbr.balanceOf(gov), amount);
    }

    function test_transferFrom_reverts_whenAmountGtFromBalance() public {
        uint amount = 100e18;

        vm.startPrank(user, user);
        dbr.approve(gov, amount);
        vm.stopPrank();

        vm.startPrank(gov);
        vm.expectRevert("Insufficient balance");
        dbr.transferFrom(user, gov, amount);
    }

    function test_transferFrom_reverts_whenAmountGtAllowance() public {
        uint amount = 100e18;

        vm.startPrank(operator);
        dbr.mint(user, amount * 2);
        vm.stopPrank();

        vm.startPrank(user, user);
        dbr.approve(gov, amount);
        vm.stopPrank();

        vm.startPrank(gov);
        vm.expectRevert();
        dbr.transferFrom(user, gov, amount * 2);
    }

    //Access Control
    function test_accessControl_setPendingOperator() public {
        vm.startPrank(operator);
        dbr.setPendingOperator(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        dbr.setPendingOperator(address(0));
    }

    function test_accessControl_claimOperator() public {
        vm.startPrank(operator);
        dbr.setPendingOperator(user);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(onlyPendingOperator);
        dbr.claimOperator();
        vm.stopPrank();

        vm.startPrank(user, user);
        dbr.claimOperator();
        assertEq(dbr.operator(), user, "Call to claimOperator failed");
    }

    function test_accessControl_setReplenishmentPriceBps() public {
        vm.startPrank(operator);
        dbr.setReplenishmentPriceBps(100);

        vm.expectRevert("replenishment price must be over 0");
        dbr.setReplenishmentPriceBps(0);
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        dbr.setReplenishmentPriceBps(100);
    }

    function test_accessControl_addMinter() public {
        vm.startPrank(operator);
        dbr.addMinter(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        dbr.addMinter(address(0));
    }

    function test_accessControl_removeMinter() public {
        vm.startPrank(operator);
        dbr.removeMinter(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        dbr.removeMinter(address(0));
    }

    function test_accessControl_addMarket() public {
        vm.startPrank(operator);
        dbr.addMarket(address(market));
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        dbr.addMarket(address(market));
    }
    
    function test_accessControl_mint() public {
        vm.startPrank(operator);
        dbr.mint(user, 100);
        assertEq(dbr.balanceOf(user), 100, "mint failed");
        vm.stopPrank();

        vm.startPrank(operator);
        dbr.addMinter(user);
        vm.stopPrank();
        vm.startPrank(user, user);
        dbr.mint(user, 100);
        assertEq(dbr.balanceOf(user), 200, "mint failed");
        vm.stopPrank();

        vm.expectRevert(onlyMinterOperator);
        dbr.mint(user, 100);
    }

    function test_accessControl_onBorrow() public {
        vm.startPrank(operator);
        vm.expectRevert(onBorrowError);
        dbr.onBorrow(user, 100e18);
    }

    function test_accessControl_onRepay() public {
        vm.startPrank(operator);
        vm.expectRevert(onRepayError);
        dbr.onRepay(user, 100e18);
    }

    function test_accessControl_onForceReplenish() public {
        vm.startPrank(user, user);
        uint deficit = dbr.deficitOf(user);
        vm.expectRevert(onForceReplenishError);
        dbr.onForceReplenish(user, msg.sender, deficit, 1);
    }

    function test_domainSeparator() public {
         ExposedDBR newDBR1 = new ExposedDBR(10000, "Dola Borrowing Rights", "DBR", address(0));
         ExposedDBR newDBR2 = new ExposedDBR(10000, "Dola Borrowing Rights", "DBR", address(0));
         assertNotEq(newDBR1.exposeDomainSeparator(), newDBR2.exposeDomainSeparator());
    }

}

contract ExposedDBR is DolaBorrowingRights{

    constructor (
        uint _replenishmentPriceBps,
        string memory _name,
        string memory _symbol,
        address _operator
    ) DolaBorrowingRights (
        _replenishmentPriceBps,
        _name,
        _symbol,
        _operator
    ) {}

    function exposeDomainSeparator() external view returns(bytes32){
        return computeDomainSeparator();
    }
}

