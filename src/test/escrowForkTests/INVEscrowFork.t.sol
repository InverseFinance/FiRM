// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IDbrDistributor.sol";
import "src/escrows/INVEscrow.sol";
import "src/DBR.sol";
import "src/DbrDistributor.sol";

contract MockMarket {
    mapping(address => IEscrow) public escrows;
    IERC20 public collateral = IERC20(0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68);
    function addEscrow(address owner, address escrow) external {
        escrows[owner] = IEscrow(escrow);
    }
}

contract INVEscrowForkTest is Test{

    address beneficiary = address(0xB);
    address claimant = address(0xC);
    address holder = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    IDelegateableERC20 INV = IDelegateableERC20(0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68);
    IXINV xINV = IXINV(0x1637e4e9941D55703a7A5E7807d6aDA3f7DCD61B);
    DolaBorrowingRights DBR = DolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
    DbrDistributor distributor;
        
    IMarket market;
    INVEscrow escrow;


    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        distributor = new DbrDistributor(IDolaBorrowingRights(address(DBR)), gov, gov);
        market = IMarket(address(new MockMarket()));
        vm.startPrank(gov);
        DBR.addMinter(address(distributor));
        DBR.addMarket(address(market));
        distributor.setRewardRateConstraints(0, 2 ether);
        distributor.setRewardRate(1 ether);
        vm.stopPrank();
        escrow = new INVEscrow(xINV, IDbrDistributor(address(distributor)));
        vm.startPrank(address(market), address(market));
        MockMarket(address(market)).addEscrow(beneficiary, address(escrow));
        escrow.initialize(INV, beneficiary);
        vm.stopPrank();
    }

    function testOnDeposit_successful_whenContractHoldsINV() public {
        uint balanceBefore = escrow.balance();
        uint stakedBalanceBefore = xINV.balanceOf(address(escrow));
        
        vm.prank(holder, holder);
        INV.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        
        uint max = balanceBefore + 1 ether;
        uint min = (balanceBefore + 1 ether) * (1 ether - 100) / 1 ether;
        withinSpan(escrow.balance(), max, min);
        assertGt(xINV.balanceOf(address(escrow)), stakedBalanceBefore);
        assertEq(xINV.balanceOf(address(escrow)), escrow.stakedXINV());
    }

    function testPay_successful_whenContractHasStakedINV() public {
        vm.prank(holder, holder);
        INV.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        uint beneficiaryBalanceBefore = INV.balanceOf(beneficiary);

        vm.prank(address(market), address(market));
        escrow.pay(beneficiary, 1 ether);


        assertEq(escrow.balance(), 0);
        assertEq(xINV.balanceOf(address(escrow)), 0);
        assertEq(INV.balanceOf(beneficiary), beneficiaryBalanceBefore + 1 ether);
        assertEq(xINV.balanceOf(address(escrow)), escrow.stakedXINV());
    }

    function testPay_successful_whenEscrowHasStakedINV_AfterRewardsRunOut() public {
        vm.prank(holder, holder);
        INV.transfer(address(escrow), 1 ether);
        escrow.onDeposit();
        uint beneficiaryBalanceBefore = INV.balanceOf(beneficiary);

        vm.startPrank(address(market), address(market));
        vm.roll(block.number + 36500 days / 12);
        escrow.pay(beneficiary, escrow.balance());
        vm.stopPrank();


        assertLt(escrow.balance(), 10);
        assertLt(xINV.balanceOf(address(escrow)), 10);
        assertLe(INV.balanceOf(beneficiary), beneficiaryBalanceBefore + 1 ether);
        assertGt(INV.balanceOf(beneficiary), beneficiaryBalanceBefore + 1 ether-10);
        assertEq(xINV.balanceOf(address(escrow)), escrow.stakedXINV());
    }

    function testPay_successful_whenContractHasStakedINVFuzz(uint walletAmount) public {
        vm.assume(walletAmount > 1000);
        vm.startPrank(holder, holder);
        uint payAmount = walletAmount % INV.balanceOf(holder);
        INV.transfer(address(escrow), payAmount);
        escrow.onDeposit();
        uint beneficiaryBalanceBefore = INV.balanceOf(beneficiary);
        vm.stopPrank();

        vm.prank(address(market), address(market));
        escrow.pay(beneficiary, payAmount);


        assertEq(escrow.balance(), 0);
        assertEq(xINV.balanceOf(address(escrow)), 0);
        assertEq(INV.balanceOf(beneficiary), beneficiaryBalanceBefore + payAmount);
        assertEq(xINV.balanceOf(address(escrow)), escrow.stakedXINV());
    }

    function testPay_failWithONLYMARKET_whenCalledByNonMarket() public {
        vm.prank(holder, holder);
        INV.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.startPrank(holder, holder);
        vm.expectRevert("ONLY MARKET");
        escrow.pay(beneficiary, 1 ether);
        vm.stopPrank();
    }

    function testClaim_successful_whenCalledByBeneficiary() public {
        uint DBRBalanceBefore = DBR.balanceOf(beneficiary);
        vm.prank(holder, holder);
        INV.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.claimDBR();
        
        uint expectedDbr = 14 days * 1 ether;
        uint max = expectedDbr * 1 ether / (1 ether - 1);
        uint min = expectedDbr * (1 ether - 1) / 1 ether;
        withinSpan(DBR.balanceOf(beneficiary) - DBRBalanceBefore, max, min);
    }

    function testClaimTo_successful_whenCalledByBeneficiary() public {
        uint DBRBalanceBefore = DBR.balanceOf(claimant);
        vm.prank(holder, holder);
        INV.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.claimDBRTo(claimant);

        uint expectedDbr = 14 days * 1 ether;
        uint max = expectedDbr * 1 ether / (1 ether - 1);
        uint min = expectedDbr * (1 ether - 1) / 1 ether;
        withinSpan(DBR.balanceOf(claimant) - DBRBalanceBefore, max, min);
    }

    function testClaimTo_successful_whenCalledByAllowlistedAddress() public {
        uint DBRBalanceBefore = DBR.balanceOf(beneficiary);
        vm.prank(holder, holder);
        INV.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.setClaimer(claimant, true);
        vm.prank(claimant);
        escrow.claimDBRTo(beneficiary);

        uint expectedDbr = 14 days * 1 ether;
        uint max = expectedDbr * 1 ether / (1 ether - 1);
        uint min = expectedDbr * (1 ether - 1) / 1 ether;
        withinSpan(DBR.balanceOf(beneficiary) - DBRBalanceBefore, max, min);
    }

    function testClaimTo_fails_whenAllowlistedAddressIsDisallowed() public {
        vm.prank(holder, holder);
        INV.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.setClaimer(claimant, true);
        vm.prank(claimant);
        escrow.claimDBRTo(beneficiary);
        vm.warp(block.timestamp + 14 days);
        vm.prank(beneficiary);
        escrow.setClaimer(claimant, false);
        vm.prank(claimant);
        vm.expectRevert("ONLY BENEFICIARY OR ALLOWED CLAIMERS");
        escrow.claimDBRTo(beneficiary);
    }

    function testClaimTo_fails_whenCalledByNonAllowlistedAddress() public {
        vm.prank(holder, holder);
        INV.transfer(address(escrow), 1 ether);
        escrow.onDeposit();

        vm.warp(block.timestamp + 14 days);
        vm.prank(claimant);
        vm.expectRevert("ONLY BENEFICIARY OR ALLOWED CLAIMERS");
        escrow.claimDBRTo(beneficiary);
    }

    function testAllowClaimOnBehalf_fails_whenCalledByNonBeneficiary() public {
        vm.prank(claimant);
        vm.expectRevert("ONLY BENEFICIARY");
        escrow.setClaimer(claimant, true);
    }

    function withinSpan(uint input, uint max, uint min) public {
        assertLe(input, max);
        assertGe(input, min);
    }
}

