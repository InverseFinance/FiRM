// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/escrows/FXNConvexEscrow.sol";

contract FXNConvexEscrowForkTest is Test {
    address market = address(0xA);
    address beneficiary = address(0xB);
    address friend = address(0xC);
    address holder = address(0xD);
    IERC20 cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    FXNConvexEscrow escrow;
    IERC20 curveLP = IERC20(0x1062FD8eD633c1f080754c19317cb3912810B5e5); // Pool with FXN, CRV and CVX rewards
    address fxnGauge = address(0xfEFafB9446d84A9e58a3A2f2DDDd7219E8c94FbB);
    
    address booster = address(0xAffe966B27ba3E4Ebb8A0eC124C7b7019CC762f8);
    IERC20 fxn = IERC20(0x365AccFCa291e7D3914637ABf1F7635dB165Bb09);
    uint256 pid = 7;
    IVault vault;

    // DOLA/fxSAVE
    // gauge address / stakingAddress for fxSave/DOLA 0x7d4674b837429c44914961cb9F21dD6dEFd0eee0 (this is the token minted to the vault after deposit)
    // pid 43
    // curve LP token 0x2b854e225d7282854819327D0CA5b8D8AA8CAaED

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        
        escrow = new FXNConvexEscrow(booster, address(fxn), pid);
        vm.startPrank(market, market);
        escrow.initialize(curveLP, beneficiary);
        vm.stopPrank();
        deal(address(curveLP), holder, 1000 ether);
        vault = escrow.vault();
    }

    function test_initialization() public view {
        assertEq(address(escrow.token()), address(curveLP));
        assertEq(address(escrow.fxn()), address(fxn));
        assertEq(escrow.pid(), pid);
        assertEq(address(escrow.market()), market);
        assertEq(address(escrow.beneficiary()), beneficiary);
        assertEq(address(escrow.gauge()), fxnGauge);
        assertNotEq(address(vault), address(0));
        assertEq(address(escrow.vault().stakingToken()), address(curveLP));
    }

    function test_deposit() public {
        assertEq(escrow.balance(), 0);
       
        uint256 depositAmount = 100 ether;
        vm.prank(holder, holder);
        curveLP.transfer(address(escrow), depositAmount);
        escrow.onDeposit();

        assertEq(escrow.balance(), depositAmount, "Incorrect balance in escrow");
        assertEq(
            IERC20(fxnGauge).balanceOf(address(vault)),
            depositAmount,
            "Incorrect staked balance in vault"
        );
    }
    
    function test_pay_if_enough_escrow_balance() public {
        test_deposit();
        uint256 payAmount = 50 ether;
        uint256 beneficiaryBalanceBefore = curveLP.balanceOf(beneficiary);

        vm.prank(market, market);
        escrow.pay(beneficiary, payAmount);

        assertEq(curveLP.balanceOf(beneficiary), beneficiaryBalanceBefore + payAmount, "Incorrect beneficiary balance");

        vm.prank(market, market);
        escrow.pay(beneficiary, payAmount);
        assertEq(curveLP.balanceOf(beneficiary), beneficiaryBalanceBefore + 2 * payAmount, "Incorrect beneficiary balance after second pay");
        assertEq(escrow.balance(), 0, "Incorrect escrow balance after two pays");
        assertEq(IERC20(fxnGauge).balanceOf(address(vault)), 0, "Incorrect staked balance in vault after two pays");
    }

    function test_claim_if_rewards_accumulated() public {
        test_deposit();
        //move time forward 30 days to accumulate rewards
        vm.warp(block.timestamp + 30 days);
        vm.prank(beneficiary);
        escrow.claim();
        assertGt(fxn.balanceOf(beneficiary), 0, "Fxn balance did not increase");
        assertGt(cvx.balanceOf(beneficiary), 0, "Cvx balance did not increase");
        assertGt(crv.balanceOf(beneficiary), 0, "Crv balance did not increase");
    }
    
      function test_transferTokens_if_earned_called() public {
        test_deposit();
        //move time forward 30 days to accumulate rewards
        vm.warp(block.timestamp + 30 days);
        // No balance in vault before earned is called
        assertEq(cvx.balanceOf(address(vault)), 0, "Cvx balance in vault should be zero before earned is called");
        assertEq(crv.balanceOf(address(vault)), 0, "Crv balance in vault should be zero before earned is called");
        // Permissionless call to earned to update rewards
       (address[] memory rewardTokens, uint256 [] memory rewards) = vault.earned();
        // Token are now in the vault and not in the escrow contract
        assertGt(cvx.balanceOf(address(vault)), 0, "Cvx balance in vault not be zero after earned is called");
        assertGt(crv.balanceOf(address(vault)), 0, "Crv balance in vault not be zero after earned is called");
     
        vm.startPrank(beneficiary);
        escrow.claim();
        // Claim only claims fxn
        assertGt(fxn.balanceOf(beneficiary), 0, "Fxn balance did not increase");
        assertEq(cvx.balanceOf(beneficiary), 0, "Cvx balance did increased");
        assertEq(crv.balanceOf(beneficiary), 0, "Crv balance did increased");
        // Transfer tokens to beneficiary (transfer from Vault to escrow to beneficiary)
        escrow.transferTokens(rewardTokens, beneficiary);
        vm.stopPrank();
        assertEq(cvx.balanceOf(address(vault)), 0, "Cvx balance in vault should be zero after transferTokens is called");
        assertEq(crv.balanceOf(address(vault)), 0, "Crv balance in vault should be zero after transferTokens is called");
        assertGt(cvx.balanceOf(beneficiary), 0, "Cvx balance did not increase");
        assertGt(crv.balanceOf(beneficiary), 0, "Crv balance did not increase");

    }

       function test_transferTokens_does_not_transfer_collateral() public {
        test_deposit();
        vm.prank(holder);
        curveLP.transfer(address(escrow), 100 ether);
        //move time forward 30 days to accumulate rewards
        vm.warp(block.timestamp + 30 days);
        assertEq(escrow.balance(), 200 ether, "Incorrect escrow balance after direct token transfer");
        address[] memory tokenList = new address[](1);
        tokenList[0] = address(curveLP);

        uint256 curveLPBalanceBefore = curveLP.balanceOf(beneficiary);
        vm.prank(beneficiary);
        escrow.transferTokens(tokenList, beneficiary);
        vm.stopPrank();
        assertEq(curveLP.balanceOf(beneficiary), curveLPBalanceBefore, "Collateral token should not be transferred");

    }

    function test_claimTo_if_rewards_accumulated() public {
        test_deposit();
        //move time forward 30 days to accumulate rewards
        vm.warp(block.timestamp + 30 days);

        vm.prank(beneficiary);
        escrow.claimTo(friend);

        assertGt(fxn.balanceOf(friend), 0, "Fxn balance did not increase");
        assertGt(cvx.balanceOf(friend), 0, "Cvx balance did not increase");
        assertGt(crv.balanceOf(friend), 0, "Crv balance did not increase");
    }

    function test_claim_after_pay() public {
        test_deposit();

        //move time forward 30 days to accumulate rewards
        vm.warp(block.timestamp + 30 days);

        // withdraw collateral but keep rewards
        vm.startPrank(market, market);
        escrow.pay(beneficiary, escrow.balance());
        vm.stopPrank();

        assertEq(cvx.balanceOf(beneficiary), 0, "Cvx balance should be zero before claim");
        assertEq(crv.balanceOf(beneficiary), 0, "Crv balance should be zero before claim");
        assertEq(fxn.balanceOf(beneficiary), 0, "Fxn balance should be zero before claim");

        
        vm.prank(beneficiary);
        escrow.claim();

        assertGt(fxn.balanceOf(beneficiary), 0, "Fxn balance did not increase");
        assertGt(cvx.balanceOf(beneficiary), 0, "Cvx balance did not increase");
        assertGt(crv.balanceOf(beneficiary), 0, "Crv balance did not increase");
    }

    function test_pay_with_token_if_enough_balance() public {
        test_deposit();
        assertEq(IERC20(fxnGauge).balanceOf(address(vault)), 100 ether); 
        vm.prank(holder);
        curveLP.transfer(address(escrow), 100 ether);
        assertEq(escrow.balance(), 200 ether, "Incorrect escrow balance after direct token transfer");
        assertEq(IERC20(fxnGauge).balanceOf(address(vault)), 100 ether); 
        uint256 payAmount = 50 ether;
        uint256 beneficiaryBalanceBefore = curveLP.balanceOf(beneficiary);
        
        vm.prank(market, market);
        escrow.pay(beneficiary, payAmount);
        assertEq(curveLP.balanceOf(beneficiary), beneficiaryBalanceBefore + payAmount, "Incorrect beneficiary balance");

        vm.prank(market, market);
        escrow.pay(beneficiary, payAmount);
        assertEq(curveLP.balanceOf(beneficiary), beneficiaryBalanceBefore + 2 * payAmount, "Incorrect beneficiary balance after second pay");
        assertEq(escrow.balance(), 100 ether, "Incorrect escrow balance after two pays");
        assertEq(IERC20(fxnGauge).balanceOf(address(vault)), 100 ether, "Incorrect staked balance in vault after two pays");
    }

    function test_pay_with_token_first_and_then_vault() public {
        test_deposit();
        assertEq(IERC20(fxnGauge).balanceOf(address(vault)), 100 ether); 
        vm.prank(holder);
        curveLP.transfer(address(escrow), 100 ether);
        assertEq(IERC20(fxnGauge).balanceOf(address(vault)), 100 ether); 
        uint256 payAmount = 150 ether;
        uint256 beneficiaryBalanceBefore = curveLP.balanceOf(beneficiary);
        
        vm.prank(market, market);
        escrow.pay(beneficiary, payAmount);
        assertEq(curveLP.balanceOf(beneficiary), beneficiaryBalanceBefore + payAmount, "Incorrect beneficiary balance");

        assertEq(escrow.balance(), 50 ether, "Incorrect escrow balance after pay");
        assertEq(IERC20(fxnGauge).balanceOf(address(vault)), 50 ether, "Incorrect staked balance in vault after pay");
    }

    function test_pay_fail_with_token_first_and_then_vault_if_not_enough_balance() public {
        test_deposit();
        assertEq(IERC20(fxnGauge).balanceOf(address(vault)), 100 ether); 
        vm.prank(holder);
        curveLP.transfer(address(escrow), 100 ether);
        assertEq(IERC20(fxnGauge).balanceOf(address(vault)), 100 ether); 
        uint256 payAmount = 150 ether;
        uint256 beneficiaryBalanceBefore = curveLP.balanceOf(beneficiary);
        
        vm.prank(market, market);
        escrow.pay(beneficiary, payAmount);
        assertEq(curveLP.balanceOf(beneficiary), beneficiaryBalanceBefore + payAmount, "Incorrect beneficiary balance");

        assertEq(escrow.balance(), 50 ether, "Incorrect escrow balance after pay");
        assertEq(IERC20(fxnGauge).balanceOf(address(vault)), 50 ether, "Incorrect staked balance in vault after pay");

        vm.prank(market, market);
        vm.expectRevert();
        escrow.pay(beneficiary, 200 ether);
    }

    function test_pay_fail_when_not_Market() public {
        test_deposit();

        vm.expectRevert(FXNConvexEscrow.OnlyMarket.selector);
        escrow.pay(beneficiary, 1 ether);
    }

    function test_pay_fail_if_not_enough_balance() public {
        test_deposit();
        uint256 payAmount = 150 ether;

        vm.prank(market, market);
        vm.expectRevert();
        escrow.pay(beneficiary, payAmount);
    }

    function test_claimTo_when_in_allowlist() public {
        test_deposit();
        //move time forward 30 days to accumulate rewards
        vm.warp(block.timestamp + 30 days);
        vm.prank(beneficiary);
        escrow.allowClaimOnBehalf(friend);
        vm.prank(friend);
        escrow.claimTo(friend);

        assertGt(fxn.balanceOf(friend), 0, "Fxn balance did not increase");
        assertGt(cvx.balanceOf(friend), 0, "Cvx balance did not increase");
        assertGt(crv.balanceOf(friend), 0, "Crv balance did not increase");
    }

    function test_claimTo_fails_when_allowlisted_address_is_disallowed() public {
        test_deposit();
        //move time forward 30 days to accumulate rewards
        vm.warp(block.timestamp + 30 days);

        vm.prank(beneficiary);
        escrow.allowClaimOnBehalf(friend);
        vm.prank(friend);
        escrow.claimTo(beneficiary);
        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.disallowClaimOnBehalf(friend);
        vm.prank(friend);
        vm.expectRevert(FXNConvexEscrow.OnlyBeneficiaryOrAllowlist.selector);
        escrow.claimTo(beneficiary);
    }

    function test_claimTo_fails_when_not_in_allowlist() public {
        vm.prank(friend);
        vm.expectRevert(FXNConvexEscrow.OnlyBeneficiaryOrAllowlist.selector);
        escrow.claimTo(beneficiary);
    }

    function test_allowClaimOnBehalf_fails_when_not_beneficiary() public {
        vm.prank(friend);
        vm.expectRevert(FXNConvexEscrow.OnlyBeneficiary.selector);
        escrow.allowClaimOnBehalf(friend);
    }

    function test_disallowClaimOnBehalf_fails_when_not_beneficiary()
        public
    {
        vm.prank(friend);
        vm.expectRevert(FXNConvexEscrow.OnlyBeneficiary.selector);
        escrow.disallowClaimOnBehalf(friend);
    }
}
