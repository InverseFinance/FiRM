// SPDX-License-Identifier: UNLICENSED 
pragma solidity ^0.8.13; 

import "forge-std/Test.sol"; 
import "forge-std/console2.sol"; 
//import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SimpleERC20Escrow} from "src/escrows/SimpleERC20Escrow.sol"; 
import {CurveHelper} from "src/util/CurveHelper.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";
import {IChainlinkFeed} from "src/interfaces/IChainlinkFeed.sol";
import {DolaBorrowingRights} from "src/DBR.sol";
import "src/Market.sol";
import {IMarket} from "src/interfaces/IMarket.sol";
import {BorrowController} from "src/BorrowController.sol";
interface IWeth is IERC20 {
    function withdraw(uint wad) external;
    function deposit() payable external;
}
interface IDOLA {
    function mint(address to, uint256 amount) external;
}
//This test must be run as a mainnet fork, to work correctly
contract LatestOffchainHelperTest is Test, ConfigAddr {

    CurveHelper helper;
    bytes32 borrowHash;
    address userPk;
    uint maxBorrowAmount;
    IWeth weth = IWeth(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IChainlinkFeed ethFeed = IChainlinkFeed(0x22390B88C53D1631f673b8Dcd91860267137b2c8);
    IERC20 DOLA = IERC20(dolaAddr);
    DolaBorrowingRights dbr = DolaBorrowingRights(dbrAddr);
    Market market = Market(0x63Df5e23Db45a2066508318f172bA45B9CD37035);
     uint256 wethTestAmount = 10 ether;
    BorrowController borrowController = BorrowController(0x01ECA33e20a4c379Bd8A5361f896A7dd2bAE4ce8);
    uint256 privKey = 0x989944;
    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url); 
        vm.label(address(DOLA),"DOLA");
        vm.label(address(dbr),"DBR");
   
        address newTriDBRAddr =
        address(0x66da369fC5dBBa0774Da70546Bd20F2B242Cd34d);
        helper = new CurveHelper{salt: bytes32(uint256(1))}(newTriDBRAddr, gov);
        
        userPk = vm.addr(privKey);
     
        vm.startPrank(gov);
        borrowController.allow(address(helper));
        vm.stopPrank();
        deal(address(weth), address(userPk), wethTestAmount);
        vm.prank(gov);
        borrowController.setMinDebt(address(market), 1 ether);
        
        maxBorrowAmount = getMaxBorrowAmount(wethTestAmount);
        vm.startPrank(userPk, userPk);
        weth.approve(address(helper), type(uint).max);
        weth.approve(address(market), type(uint).max);
        DOLA.approve(address(helper), type(uint).max);
        dbr.approve(address(helper), type(uint).max);
        vm.stopPrank();
        
    }

   
    function testDepositAndBorrowOnBehalf() public {
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, getBorrowHash(borrowAmount + dolaForDbr, 0));

        vm.startPrank(userPk, userPk);
        assertEq(borrowController.isPriceStale(address(market)), false);
        helper.depositBuyDbrAndBorrowOnBehalf(IMarket(address(market)), wethTestAmount, borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);
        vm.stopPrank();

        assertLt(dbr.balanceOf(userPk), dbrNeeded * 1001 / 1000);
        assertGt(dbr.balanceOf(userPk), dbrNeeded * 999 / 1000);
        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        assertEq(DOLA.balanceOf(userPk), borrowAmount, "failed to borrow DOLA");
    }

    function testDepositNativeEthBuyDbrAndBorrowOnBehalf() public {
        uint duration = 365 days;
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, duration, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, getBorrowHash(borrowAmount + dolaForDbr, 0));
        uint prevBal = weth.balanceOf(userPk);
        vm.deal(userPk, wethTestAmount);
        
        vm.startPrank(userPk, userPk);
        helper.depositNativeEthBuyDbrAndBorrowOnBehalf{value:wethTestAmount}(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);
        vm.stopPrank();

        assertLt(dbr.balanceOf(userPk), dbrNeeded * 101 / 100);
        assertGt(dbr.balanceOf(userPk), dbrNeeded * 99 / 100);
        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk)-prevBal, 0, "failed to deposit weth");
        assertGt(duration, market.debts(userPk) * duration / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), borrowAmount, "failed to borrow DOLA");
    }

    function testBorrowOnBehalf() public {
        uint duration = 365 days;

        vm.startPrank(userPk, userPk);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, getBorrowHash(borrowAmount + dolaForDbr, 0));

        deposit(wethTestAmount);
        vm.stopPrank();
        vm.prank(userPk, userPk);

        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        
        assertGt(duration, market.debts(userPk) * 365 days / dbr.balanceOf(userPk) - 1 days); 
        assertEq(DOLA.balanceOf(userPk), borrowAmount, "failed to borrow DOLA");
    }

    function testSellDbrAndRepayOnBehalf() public {
        vm.startPrank(userPk, userPk);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, getBorrowHash(borrowAmount + dolaForDbr, 0));

        gibDOLA(userPk, 10000 ether);

        deposit(wethTestAmount);

        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);
        helper.sellDbrAndRepayOnBehalf(IMarket(address(market)), market.debts(userPk), dbr.balanceOf(userPk) / 100,dbr.balanceOf(userPk));
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testSellDbrAndRepayOnBehalf_HigherDBRAmountThanOwned() public {
        vm.startPrank(userPk, userPk);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, getBorrowHash(borrowAmount + dolaForDbr, 0));

        gibDOLA(userPk, 10000 ether);

        deposit(wethTestAmount);

        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);
        helper.sellDbrAndRepayOnBehalf(IMarket(address(market)), market.debts(userPk), dbr.balanceOf(userPk) / 100,dbr.balanceOf(userPk)+1);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

  function testSellDbrAndRepayOnBehalf_EarnMoreFromDBRSellThanRepay() public {
        vm.startPrank(userPk, userPk);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, getBorrowHash(borrowAmount + dolaForDbr, 0));

        gibDOLA(userPk, 10000 ether);

        deposit(wethTestAmount);
        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);
        //Reduce debt to 1
        DOLA.approve(address(market), type(uint256).max);
        market.repay(userPk, market.debts(userPk) - 1 ether);
        uint dolaBalanceBefore = DOLA.balanceOf(userPk);
        helper.sellDbrAndRepayOnBehalf(IMarket(address(market)), market.debts(userPk), dbr.balanceOf(userPk) / 100,dbr.balanceOf(userPk));
        vm.stopPrank();

        assertGt(DOLA.balanceOf(userPk), dolaBalanceBefore, "DOLA balance did not increase");
        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");
        assertEq(weth.balanceOf(userPk), 0, "failed to deposit weth");
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testSellDbrRepayAndWithdrawOnBehalf() public {
        gibDOLA(userPk, 10000 ether);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, getBorrowHash(borrowAmount + dolaForDbr, 0));

        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);
        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);

        bytes32 withdrawHash = getWithdrawHash(wethTestAmount, 1);
        (v, r, s) = vm.sign(privKey, withdrawHash);
        uint pkBalanceBefore = weth.balanceOf(userPk);

        helper.sellDbrRepayAndWithdrawOnBehalf(
            IMarket(address(market)),
            market.debts(userPk),
            dbr.balanceOf(userPk) / 100,
            dbr.balanceOf(userPk), 
            wethTestAmount,
            block.timestamp,
            v, r, s);
        vm.stopPrank();
        
        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 0, "failed to withdraw weth");
        assertEq(weth.balanceOf(userPk) - pkBalanceBefore, wethTestAmount, "failed to withdraw weth");
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testSellDbrRepayAndWithdrawNativeEthOnBehalf() public {
        gibDOLA(userPk, 10000 ether);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, getBorrowHash(borrowAmount + dolaForDbr, 0));

        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);
        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);

        bytes32 withdrawHash = getWithdrawHash(wethTestAmount, 1);
        (v, r, s) = vm.sign(privKey, withdrawHash);
        
        uint pkBalanceBefore = userPk.balance;
        helper.sellDbrRepayAndWithdrawNativeEthOnBehalf(
            IMarket(address(market)),
            market.debts(userPk),
            dbr.balanceOf(userPk) / 100,
            dbr.balanceOf(userPk), 
            wethTestAmount,
            block.timestamp,
            v, r, s);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 0, "failed to withdraw weth");
        assertEq(userPk.balance - pkBalanceBefore, wethTestAmount, "failed to withdraw weth");
        assertEq(market.debts(userPk), 0, "Did not repay debt"); 
        assertEq(dbr.balanceOf(userPk), 0, "Did not sell DBR"); 
    }

    function testWithdrawNativeEthOnBehalf() public {
        bytes32 withdrawHash = getWithdrawHash(wethTestAmount, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, withdrawHash);

        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);
        uint pkBalanceBefore = userPk.balance;
        helper.withdrawNativeEthOnBehalf(IMarket(address(market)), wethTestAmount, block.timestamp, v, r, s);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 0, "failed to withdraw weth");
        assertEq(payable(userPk).balance - pkBalanceBefore, wethTestAmount, "failed to withdraw weth");
    }

    function testDepositNativeEthOnBehalf() public {
        uint prevBal = weth.balanceOf(address(market.predictEscrow(userPk)));
        vm.deal(userPk, wethTestAmount);

        vm.startPrank(userPk, userPk);
        helper.depositNativeEthOnBehalf{value:wethTestAmount}(IMarket(address(market)));
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount+prevBal, "failed to deposit weth");       
    }

    function testRepayAndWithdrawNativeEthOnBehalf() public {
        gibDOLA(userPk, 10000 ether);
        uint borrowAmount = maxBorrowAmount / 2;
        (uint dolaForDbr, uint dbrNeeded) = helper.approximateDolaAndDbrNeeded(borrowAmount, 365 days, 18);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, getBorrowHash(borrowAmount + dolaForDbr, 0));


        vm.startPrank(userPk, userPk);
        deposit(wethTestAmount);
        helper.buyDbrAndBorrowOnBehalf(IMarket(address(market)), borrowAmount, dolaForDbr, dbrNeeded * 99 / 100, block.timestamp, v, r, s);

        bytes32 withdrawHash = getWithdrawHash(wethTestAmount, 1);
        (v, r, s) = vm.sign(privKey, withdrawHash);

        uint pkBalanceBefore = userPk.balance;
   
        helper.repayAndWithdrawNativeEthOnBehalf(
            IMarket(address(market)),
            market.debts(userPk),
            wethTestAmount,
            block.timestamp,
            v, r, s);
        
        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 0, "failed to withdraw weth");
        assertEq(userPk.balance - pkBalanceBefore, wethTestAmount, "failed to withdraw weth");
        assertEq(market.debts(userPk), 0, "Did not repay debt");     
        vm.stopPrank();   
    }

    function testDepositNativeEthAndBorrowOnBehalf() public {
        uint borrowAmount = maxBorrowAmount / 2;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, getBorrowHash(borrowAmount, 0));

        vm.startPrank(userPk, userPk);
        weth.approve(address(weth), type(uint).max);
        weth.withdraw(wethTestAmount);

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), 0);
        assertEq(DOLA.balanceOf(userPk), 0);
        helper.depositNativeEthAndBorrowOnBehalf{value:wethTestAmount}(IMarket(address(market)), borrowAmount, block.timestamp, v, r, s);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(market.predictEscrow(userPk))), wethTestAmount, "failed to deposit weth");       
        assertEq(DOLA.balanceOf(userPk), borrowAmount, "failed to borrow");
        assertEq(market.debts(userPk), DOLA.balanceOf(userPk), "Debt not equal borrow"); 
    }

    function getWithdrawHash(uint amount, uint nonce) public view returns(bytes32){
         bytes32 withdrawHash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                address(helper),
                                userPk,
                                amount,
                                nonce,
                                block.timestamp
                            )
                        )
                    )
                );
        return withdrawHash;
    }

    function getBorrowHash(uint amount, uint nonce) public view returns(bytes32){
        bytes32 hash = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        market.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                address(helper),
                                userPk,
                                amount,
                                nonce,
                                block.timestamp
                            )
                        )
                    )
                );
        return hash;
    }

    function deposit(uint amount) internal {
        weth.approve(address(market), amount);
        market.deposit(amount);
    }

    function convertWethToDola(uint amount) public view returns (uint) {
        return (amount * uint(ethFeed.latestAnswer())) / 1e18;
    }

    function convertDolaToWeth(uint amount) public view returns (uint) {
        return (amount * 1e18) / uint(ethFeed.latestAnswer());
    }

    function getMaxBorrowAmount(uint amountWeth) public view returns (uint) {
        return
            (convertWethToDola(amountWeth) * market.collateralFactorBps()) /
            10_000;
    }

    // function gibWeth(address _address, uint _amount) internal {
    //     vm.deal(_address, _amount);
    //     vm.startPrank(_address);
    //     WETH.deposit{value: _amount}();
    //     vm.stopPrank();
    // }

    // function gibDBR(address _address, uint _amount) internal {
    //     vm.startPrank(gov);
    //     dbr.mint(_address, _amount);
    //     vm.stopPrank();
    // }

    function gibDOLA(address _address, uint _amount) internal {
        bytes32 slot;
        assembly {
            mstore(0, _address)
            mstore(0x20, 0x6)
            slot := keccak256(0, 0x40)
        }

        vm.store(address(DOLA), slot, bytes32(_amount));
    }

    receive() external payable {}
}
