// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {BorrowController} from "src/BorrowController.sol";
import "src/DBR.sol";
import {Market, IBorrowController} from "src/Market.sol";
import {Oracle, IChainlinkFeed} from "src/Oracle.sol";
import {Fed, IMarket} from "src/Fed.sol";
import {ALEV2} from "src/util/ALEV2.sol";
import {ERC4626Helper, IERC4626} from "src/util/ERC4626Helper.sol";
import {IMultiMarketConvertHelper} from "src/interfaces/IMultiMarketConvertHelper.sol";
import {console} from "forge-std/console.sol";
import {BaseHelperForkTest, IERC4626, MockExchangeProxy} from "test/util/aleTests/BaseHelperForkTest.t.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

interface IMintable is IERC20 {
    function mint(address receiver, uint amount) external;

    function addMinter(address minter) external;
}

interface IBC {
    function setMinDebt(address market, uint256 minDebt) external;

    function setStalenessThreshold(address market, uint256 threshold) external;
}

interface IFlashMinter {
    function setMaxFlashLimit(uint256 limit) external;

    function flashFee(
        address token,
        uint256 amount
    ) external view returns (uint256);
}

contract ALEsFrax4626HelperForkTest is BaseHelperForkTest {
    using stdStorage for StdStorage;

    //Market deployment:
    Market market;
    IChainlinkFeed feed;
    BorrowController borrowController;

    address sFraxHolder = 0xBc2F0Ebc412647C7d4EC8FFD88Ca84Bc5b32C8cC;
    address fraxHolder = 0x5E583B6a1686f7Bc09A6bBa66E852A7C80d36F00;

    //ERC-20s
    IMintable DOLA;
    IERC20 collateral;

    //FiRM
    Oracle oracle;
    DolaBorrowingRights dbr;
    Fed fed;

    MockExchangeProxy exchangeProxy;
    ALEV2 ale;
    IFlashMinter flash;
    ERC4626Helper helper;
    //Variables
    uint collateralFactorBps;

    function getBlockNumber() public view override returns (uint256) {
        return 22241605;
    }

    function setUp() public override {
        super.setUp();

        DOLA = IMintable(dolaAddr);
        market = Market(sFraxMarketAddr);
        feed = IChainlinkFeed(sFraxFeedAddr);
        borrowController = BorrowController(borrowControllerAddr);
        dbr = DolaBorrowingRights(dbrAddr);
        helper = ERC4626Helper(erc4626HelperAddr);
        initBase(address(helper));

        exchangeProxy = new MockExchangeProxy(
            address(market.oracle()),
            address(DOLA)
        );

        vm.startPrank(gov);
        helper.setMarket(address(market), fraxAddr, sFraxAddr);
        dbr.addMarket(address(market));
        DOLA.mint(address(market), 1000000e18);

        ale = ALEV2(payable(aleV2Addr));
        ale.allowProxy(address(exchangeProxy));
        ale.setMarket(address(market), fraxAddr, address(helper), true);
        vm.stopPrank();
        //FiRM
        oracle = Oracle(address(market.oracle()));
        fed = Fed(market.lender());
        collateral = IERC20(address(market.collateral()));

        vm.startPrank(gov, gov);
        market.setBorrowController(
            IBorrowController(address(borrowController))
        );
        market.setCollateralFactorBps(8000);
        borrowController.setDailyLimit(address(market), 1_000_000 * 1e18);
        IBC(address(borrowController)).setStalenessThreshold(
            address(market),
            3660
        );

        market.setLiquidationFactorBps(5000);
        market.setLiquidationIncentiveBps(500);
        IBC(address(borrowController)).setMinDebt(address(market), 0);
        fed.changeMarketCeiling(IMarket(address(market)), type(uint).max);
        fed.changeSupplyCeiling(type(uint).max);
        oracle.setFeed(address(collateral), feed, 18);
        oracle.setFeed(fraxAddr, IChainlinkFeed(fraxUsdFeedAddr), 18);
        borrowController.allow(address(ale));
        DOLA.addMinter(address(ale));

        flash = IFlashMinter(address(ale.flash()));
        DOLA.addMinter(address(flash));
        flash.setMaxFlashLimit(1000000e18);
        vm.stopPrank();

        collateralFactorBps = market.collateralFactorBps();
    }

    function checkEq(
        uint sFraxDeposit,
        uint collateralToSwap,
        address userPk
    ) internal {
        assertApproxEqAbs(
            IERC20(sFraxAddr).balanceOf(address(market.predictEscrow(userPk))),
            sFraxDeposit + collateralToSwap,
            1
        );
    }

    function test_leveragePosition() public {
        // vm.assume(sFraxAmount < 7900 ether);
        // vm.assume(sFraxAmount > 0.00000001 ether);
        // We are going to deposit some CRV, then leverage the position
        uint sFraxAmount = 10000 ether;
        address userPk = vm.addr(1);
        vm.prank(sFraxHolder);
        IERC20(sFraxAddr).transfer(userPk, sFraxAmount);

        gibDBR(userPk, 20000 ether);

        uint maxBorrowAmount = _getMaxBorrowAmount(sFraxAmount);
        console.log(sFraxAmount, "sFraxAmount");
        console.log(maxBorrowAmount, "maxBorrowAmount");
        console.log(_convertCollatToDola(sFraxAmount), "maxBorrowAmount");
        console.log(market.collateralFactorBps(), "collateralFactorBps");

        uint256 fraxAmount = IERC4626(sFraxAddr).convertToAssets(
            _convertDolaToCollat(maxBorrowAmount)
        );
        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.prank(fraxHolder);
        IERC20(fraxAddr).transfer(address(exchangeProxy), fraxAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        IERC20(sFraxAddr).approve(address(market), sFraxAmount);
        market.deposit(sFraxAmount);

        // Sign Message for borrow on behalf
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        maxBorrowAmount,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            fraxAddr,
            maxBorrowAmount
        );

        ALEV2.DBRHelper memory dbrData;

        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            abi.encode(address(market)),
            dbrData
        );
        console.log(market.getCollateralValue(userPk));
        console.log(market.getCreditLimit(userPk));
        // market.borrow(10 ether);
        // // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        assertApproxEqAbs(
            IERC20(sFraxAddr).balanceOf(address(market.predictEscrow(userPk))),
            sFraxAmount +
                IERC4626(sFraxAddr).convertToShares(
                    _convertDolaToUnderlying(maxBorrowAmount)
                ),
            1
        );

        assertEq(DOLA.balanceOf(userPk), 0);
    }

    function test_leveragePosition_buyDBR() public {
        // We are going to deposit some st-frax, then leverage the position
        uint sFraxAmount = 10000 ether;
        address userPk = vm.addr(1);
        vm.prank(sFraxHolder);
        IERC20(sFraxAddr).transfer(userPk, sFraxAmount);

        uint maxBorrowAmount = _getMaxBorrowAmount(sFraxAmount);

        uint256 fraxAmount = IERC4626(sFraxAddr).convertToAssets(
            _convertDolaToCollat(maxBorrowAmount)
        );

        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.prank(fraxHolder);
        IERC20(fraxAddr).transfer(address(exchangeProxy), fraxAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial st-frax deposit
        IERC20(sFraxAddr).approve(address(market), sFraxAmount);
        market.deposit(sFraxAmount);

        // Calculate the amount of DOLA needed to borrow to buy the DBR needed to cover for the borrowing period
        (uint256 dolaForDBR, uint256 dbrAmount) = ale
            .approximateDolaAndDbrNeeded(maxBorrowAmount, 365 days, 8);

        // Sign Message for borrow on behalf
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        maxBorrowAmount + dolaForDBR,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            fraxAddr,
            maxBorrowAmount
        );

        ALEV2.DBRHelper memory dbrData = ALEV2.DBRHelper(
            dolaForDBR,
            (dbrAmount * 98) / 100,
            0
        );

        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            abi.encode(address(market)),
            dbrData
        );

        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        checkEq(sFraxAmount, _convertDolaToCollat(maxBorrowAmount), userPk);

        assertEq(DOLA.balanceOf(userPk), 0);

        assertGt(dbr.balanceOf(userPk), (dbrAmount * 98) / 100);
    }

    function test_deleveragePosition_sellDBR(uint256 sFraxAmount) public {
        vm.assume(sFraxAmount < 15000 ether);
        vm.assume(sFraxAmount > 0.0001 ether);
        // We are going to deposit some st-frax, then borrow and then deleverage the position
        //uint sFraxAmount = 10000 ether;
        address userPk = vm.addr(1);
        vm.prank(sFraxHolder);
        IERC20(sFraxAddr).transfer(userPk, sFraxAmount);

        gibDBR(userPk, sFraxAmount);

        uint borrowAmount = (_getMaxBorrowAmount(sFraxAmount) * 97) / 100;

        vm.startPrank(userPk, userPk);
        // Initial sFrax deposit
        IERC20(sFraxAddr).approve(address(market), sFraxAmount);
        market.deposit(sFraxAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        assertEq(
            IERC20(sFraxAddr).balanceOf(address(market.predictEscrow(userPk))),
            sFraxAmount
        );
        assertEq(DOLA.balanceOf(userPk), borrowAmount);

        // We are going to withdraw only 1/10 of the collateral to deleverage
        uint256 amountToWithdraw = IERC20(sFraxAddr).balanceOf(
            address(market.predictEscrow(userPk))
        ) / 10;

        uint256 dolaAmountForSwap = _convertUnderlyingToDola(
            IERC4626(sFraxAddr).convertToAssets(amountToWithdraw)
        );

        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), dolaAmountForSwap);
        vm.stopPrank();

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        amountToWithdraw,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        ALEV2.DBRHelper memory dbrData = ALEV2.DBRHelper(
            dbr.balanceOf(userPk),
            1,
            0
        ); // sell all DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            fraxAddr,
            IERC4626(sFraxAddr).convertToAssets(amountToWithdraw)
        );

        vm.startPrank(userPk, userPk);
        dbr.approve(address(ale), type(uint).max);

        ale.deleveragePosition(
            _convertCollatToDola(amountToWithdraw),
            address(market),
            address(exchangeProxy),
            amountToWithdraw,
            swapData,
            permit,
            abi.encode(address(market)),
            dbrData
        );

        // Some collateral has been withdrawn
        assertEq(
            IERC20(sFraxAddr).balanceOf(address(market.predictEscrow(userPk))),
            sFraxAmount - amountToWithdraw, 'COLLATERAL'
        );

        // User still has dola and actually he has more bc he sold his DBRs
       assertGt(DOLA.balanceOf(userPk), borrowAmount, 'DOLA');

        assertEq(dbr.balanceOf(userPk), 0);
    }

    function test_deleveragePosition(uint256 sFraxAmount) public {
        vm.assume(sFraxAmount < 10000 ether);
        vm.assume(sFraxAmount > 0.00000001 ether);
        // We are going to deposit some st-frax, then borrow and then deleverage the position
        // uint sFraxAmount = 10000 ether;
        address userPk = vm.addr(1);
        vm.prank(sFraxHolder);
        IERC20(sFraxAddr).transfer(userPk, sFraxAmount);

        gibDBR(userPk, sFraxAmount);

        uint borrowAmount = (_getMaxBorrowAmount(sFraxAmount) * 97) / 100;

        vm.startPrank(userPk, userPk);
        // Initial sFrax deposit
        IERC20(sFraxAddr).approve(address(market), sFraxAmount);
        market.deposit(sFraxAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        address userEscrow = address(market.predictEscrow(userPk));
        assertEq(IERC20(sFraxAddr).balanceOf(userEscrow), sFraxAmount);
        assertEq(DOLA.balanceOf(userPk), borrowAmount);

        // We are going to withdraw only 1/10 of the collateral to deleverage
        uint256 amountToWithdraw = IERC20(sFraxAddr).balanceOf(userEscrow) / 10;
        uint256 dolaAmountForSwap = _convertUnderlyingToDola(
            IERC4626(sFraxAddr).convertToAssets(amountToWithdraw)
        );

        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), dolaAmountForSwap);
        vm.stopPrank();

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        amountToWithdraw,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        ALEV2.DBRHelper memory dbrData = ALEV2.DBRHelper(0, 0, borrowAmount / 2); // repay partially debt with DOLA in the wallet

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            fraxAddr,
            IERC4626(sFraxAddr).convertToAssets(amountToWithdraw)
        );

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(ale), borrowAmount / 2);

        ale.deleveragePosition(
            _convertCollatToDola(amountToWithdraw),
            address(market),
            address(exchangeProxy),
            amountToWithdraw,
            swapData,
            permit,
            abi.encode(address(market)),
            dbrData
        );

        // Some collateral has been withdrawn
        assertEq(
            IERC20(sFraxAddr).balanceOf(userEscrow),
            sFraxAmount - amountToWithdraw
        );
        // User still has dola but has some debt repaid
        assertApproxEqAbs(DOLA.balanceOf(userPk), borrowAmount / 2, 1);
    }

    function test_convertToCollateralAndDeposit(uint256 fraxAmount) public {
        //vm.assume(fraxAmount < 1 ether);

        uint256 fraxAmount = 1 ether;
        address userPk = vm.addr(1);
        vm.prank(fraxHolder);
        IERC20(fraxAddr).transfer(userPk, fraxAmount);

        vm.startPrank(userPk, userPk);
        IERC20(fraxAddr).approve(address(helper), fraxAmount);
        helper.convertToCollateralAndDeposit(
            fraxAmount,
            userPk,
            abi.encode(address(market))
        );

        assertEq(IERC20(fraxAddr).balanceOf(userPk), 0);

        assertEq(
            IERC20(sFraxAddr).balanceOf(address(market.predictEscrow(userPk))),
            IERC4626(sFraxAddr).convertToShares(fraxAmount)
        );
    }

    function test_withdrawAndConvertFromCollateral(
        uint256 fraxAmount
    ) public {
        // vm.assume(fraxAmount < IsFrax(sFrax).availableDepositLimit());

        uint256 fraxAmount = 1 ether;
        address userPk = vm.addr(1);
        vm.prank(fraxHolder);
        IERC20(fraxAddr).transfer(userPk, fraxAmount);

        vm.startPrank(userPk, userPk);
        IERC20(fraxAddr).approve(address(helper), fraxAmount);
        helper.convertToCollateralAndDeposit(
            fraxAmount,
            userPk,
            abi.encode(address(market))
        );

        //Market market = Market(address(helper.market())); // actual Mainnet market for helper contract
        uint256 amountToWithdraw = IERC20(sFraxAddr).balanceOf(
            address(market.predictEscrow(userPk))
        ) / 10;

        bytes32 hash = keccak256(
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
                        amountToWithdraw,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        IMultiMarketConvertHelper.Permit
            memory permit = IMultiMarketConvertHelper.Permit(
                block.timestamp,
                v,
                r,
                s
            );

        assertEq(IERC20(fraxAddr).balanceOf(userPk), 0);

        helper.withdrawAndConvertFromCollateral(
            amountToWithdraw,
            userPk,
            permit,
            abi.encode(address(market))
        );

        assertApproxEqAbs(
            IERC20(fraxAddr).balanceOf(userPk),
            IERC4626(sFraxAddr).convertToAssets(amountToWithdraw),
            1
        );
    }

    function test_fail_setMarket_NoMarket() public {
        address fakeMarket = address(0x69);

        vm.expectRevert(
            abi.encodeWithSelector(ALEV2.NoMarket.selector, fakeMarket)
        );
        vm.prank(gov);
        ale.setMarket(fakeMarket, address(0), address(0), true);
    }

    function test_fail_setMarket_Wrong_BuySellToken_Without_Helper() public {
        address fakeBuySellToken = address(0x69);

        vm.expectRevert(
            abi.encodeWithSelector(
                ALEV2.MarketSetupFailed.selector,
                address(market),
                fakeBuySellToken,
                address(collateral),
                address(0)
            )
        );
        vm.prank(gov);
        ale.setMarket(address(market), fakeBuySellToken, address(0), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                ALEV2.MarketSetupFailed.selector,
                address(market),
                address(0),
                address(collateral),
                address(0)
            )
        );
        vm.prank(gov);
        ale.setMarket(address(market), address(0), address(0), true);

        vm.expectRevert();
        vm.prank(gov);
        ale.setMarket(address(market), fakeBuySellToken, address(0), true);
    }

    function test_fail_updateMarketHelper_NoMarket() public {
        address wrongMarket = address(0x69);
        address newHelper = address(0x70);

        vm.expectRevert(
            abi.encodeWithSelector(ALEV2.MarketNotSet.selector, wrongMarket)
        );
        vm.prank(gov);
        ale.updateMarketHelper(wrongMarket, newHelper);
    }

    function test_return_assetAmount_when_TotalSupply_is_Zero() public {
        stdstore
            .target(sFraxAddr)
            .sig(IERC4626(sFraxAddr).totalSupply.selector)
            .checked_write(uint256(0));

        uint256 assetAmount = 1 ether;
        assertEq(assetAmount, IERC4626(sFraxAddr).convertToShares(assetAmount));
    }

    function test_fail_collateral_is_zero_leveragePosition() public {
        // We are going to deposit some CRV, then leverage the position
        uint sFraxAmount = 10000 ether;
        address userPk = vm.addr(1);
        vm.prank(sFraxHolder);
        IERC20(sFraxAddr).transfer(userPk, sFraxAmount);

        gibDBR(userPk, sFraxAmount);

        uint maxBorrowAmount = _getMaxBorrowAmount(sFraxAmount);

        uint256 fraxAmount = IERC4626(sFraxAddr).convertToAssets(
            _convertDolaToCollat(maxBorrowAmount)
        );
        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.prank(fraxHolder);
        IERC20(fraxAddr).transfer(address(exchangeProxy), fraxAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        IERC20(sFraxAddr).approve(address(market), sFraxAmount);
        market.deposit(sFraxAmount);

        // Sign Message for borrow on behalf
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        maxBorrowAmount,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            fraxAddr,
            maxBorrowAmount
        );

        ALEV2.DBRHelper memory dbrData;

        // Mock call to return 0 buySellToken balance for the ALE
        vm.mockCall(
            fraxAddr,
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(ale)),
            abi.encode(uint256(0))
        );

        vm.expectRevert(ALEV2.CollateralIsZero.selector);
        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            abi.encode(address(market)),
            dbrData
        );
    }

    // function test_Frax_Odos_leverage_and_deleverage() public {
    //     address odos = address(0xCf5540fFFCdC3d510B18bFcA6d2b9987b0772559);
    //     vm.makePersistent(address(helper));
    //     vm.makePersistent(address(oracle));
    //     vm.rollFork(22074631);
    //     sFraxHolder = 0x56398b89d53e8731bca8C1B06886CFB14BD6b654;

    //     vm.startPrank(gov);
    //     ale = new ALEV2(triDBRAddr, gov);
    //     ale.allowProxy(odos);
    //     helper.setMarket(address(market), fraxAddr, sFraxAddr);
    //     ale.setMarket(address(market), fraxAddr, address(helper), true);
    //     borrowController.allow(address(ale));
    //     vm.stopPrank();
    //     console.log("ALE address", address(ale));
    //     uint sFraxAmount = 100000 ether;
    //     address userPk = vm.addr(1);
    //     vm.prank(sFraxHolder);
    //     IERC20(sFraxAddr).transfer(userPk, sFraxAmount);

    //     gibDBR(userPk, 20000 ether);

    //     uint borrowAmount = 100000 ether;
    //     vm.startPrank(userPk, userPk);
    //     // Initial sFrax deposit
    //     IERC20(sFraxAddr).approve(address(market), sFraxAmount);
    //     market.deposit(sFraxAmount);

    //     // Sign Message for borrow on behalf
    //     bytes32 hash = keccak256(
    //         abi.encodePacked(
    //             "\x19\x01",
    //             market.DOMAIN_SEPARATOR(),
    //             keccak256(
    //                 abi.encode(
    //                     keccak256(
    //                         "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
    //                     ),
    //                     address(ale),
    //                     userPk,
    //                     borrowAmount,
    //                     0,
    //                     block.timestamp
    //                 )
    //             )
    //         )
    //     );
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

    //     ALEV2.Permit memory permit = ALEV2.Permit(block.timestamp, v, r, s);

    //     bytes memory swapData = hex"3b635ce4000000000000000000000000865377367054516e17014ccded1e7d814edc9ce400000000000000000000000000000000000000000000152d02c7e14af6800000000000000000000000000000744793b5110f6ca9cc7cdfe1ce16677c3eb192ef000000000000000000000000853d955acef822db058eb8505911ed77f175b99e00000000000000000000000000000000000000000000152075f09d69360000000000000000000000000000000000000000000000000014ea6047cf09710000000000000000000000000000009123ef9b7db2e3d968b01c6ff99839acb242da130000000000000000000000000000000000000000000000000000000000000140000000000000000000000000d768d1fe6ef1449a54f9409400fe9d0e4954ea3f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000013c03030c006701000001020001020e00000304010000c800000400016cd2f9d06701000105040100000d0207070400046700000006080100025600090a0b010000020bff0000000000000000000000000000000000000000000000000000000000744793b5110f6ca9cc7cdfe1ce16677c3eb192ef865377367054516e17014ccded1e7d814edc9ce49d39a5de30e57443bff2a8307a4256c8797a3497dac17f958d2ee523a2206206994597c13d831ec74f493b7de8aac7d55f71853688b1f7c8f0243c855dc1bf6f1e983c0b21efb003c105133736fa0743435664008f38b0650fbc1c9fc971d0a3bc2f1e474c9edd5852cd905f086c759e8383e09bff1e68b3dcef968d416a41cdac0ed8702fac8128a64241a2a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48853d955acef822db058eb8505911ed77f175b99e00000000";

    //     ALEV2.DBRHelper memory dbrData;

    //     ale.leveragePosition(
    //         borrowAmount,
    //         address(market),
    //         odos,
    //         swapData,
    //         permit,
    //         abi.encode(address(market)),
    //         dbrData
    //     );
    //     assertApproxEqAbs(
    //         IERC20(sFraxAddr).balanceOf(address(market.predictEscrow(userPk))),
    //         sFraxAmount +
    //             IERC4626(sFraxAddr).convertToShares(
    //                 99768490416193306361856 // expected FRAX out from ODOS
    //             ),
    //         1
    //     );

    //     assertEq(DOLA.balanceOf(userPk), 0);

    //     uint256 amountToWithdraw = IERC20(sFraxAddr).balanceOf(
    //         address(market.predictEscrow(userPk)));
    //     console.log("fraxAmount", IERC4626(sFraxAddr).convertToAssets(amountToWithdraw));
    //     hash = keccak256(
    //         abi.encodePacked(
    //             "\x19\x01",
    //             market.DOMAIN_SEPARATOR(),
    //             keccak256(
    //                 abi.encode(
    //                     keccak256(
    //                         "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
    //                     ),
    //                     address(ale),
    //                     userPk,
    //                     amountToWithdraw,
    //                     1,
    //                     block.timestamp
    //                 )
    //             )
    //         )
    //     );
    //     (v, r, s) = vm.sign(1, hash);

    //     permit = ALEV2.Permit(block.timestamp, v, r, s);

    //     dbrData = ALEV2.DBRHelper(
    //         dbr.balanceOf(userPk),
    //         1,
    //         0
    //     ); // sell all DBR

    //     swapData = hex"83bd37f90001853d955acef822db058eb8505911ed77f175b99e0001865377367054516e17014ccded1e7d814edc9ce40a2cd6b5a59e02b5bb76440a2ce28d9c48d54a000000028f5c0001d768d1Fe6Ef1449A54F9409400fe9d0E4954ea3F000000019123ef9b7dB2e3D968B01C6FF99839aCb242dA13000000001d070723010879335a4601020203040101283834826702060106030001012020c36067030001070300010067040001080300010913c3130046000a0a0b0c0109239cc2dd67050e010e0b000108670600010f0b000106560410111200010467031400051401000267020000010401000c000104460616161718010667021a00131a00010067061600090c00010a670000000d1800010856051b12170001004604011c1d1e000467040100191f01000c67040100151801000a4a040120170100026704010121220100ff00000000000000000000000000000000000000000000000073a0cba58c19ed5f27c6590bd792ec38de4815eaa663b02cf0a4b149d2ad41910cb81e23e1c41c32853d955acef822db058eb8505911ed77f175b99ea663b02cf0a4b149d2ad41910cb81e23e1c41c32670a72e6d22b0956c0d2573288f82dcc5d6e3a615dc1bf6f1e983c0b21efb003c105133736fa0743ce6431d21e3fb1036ce9973a3312368ed96f5ce7bbaf8b2837cbbc7146f5bc978d6f84db0be1cacc15e4ff94b70a8f146b4e4afd069014d126035752cf62f905562626cfcdd2261162a51fd02fc9c5b6cacd6fd266af91b8aed52accc382b4e165586e29cf62f905562626cfcdd2261162a51fd02fc9c5b676a962ba6770068bcf454d34dde17175611e66374d968a5db8da0822a2f08840f553de4129aae5f381a2612f6dea269a6dd1f6deab45c5424ee2c4b7425bfb93370f14ff525adb6eaeacfe1f4e3b580283f20f44975d03b1b09e64809b757c47f942beea59d9356e565ab3a36dd77763fc0d87feaf85508c4628f13651ead6793f8d838b34b8f8522fb0cc524c9edd5852cd905f086c759e8383e09bff1e68b3ff17dab22f1e61078aba2623c89ce6110e878b3c0655977feb2f289a4ab78af67bab0d17aab84367f939e0a03fb07f59a73314e73794be0e57ac1b4e0655977feb2f289a4ab78af67bab0d17aab8436738de22a3175708d45e7c7c64cd78479c8b56f76e40d16fc0246ad3160ccc09b8d0d3a2cd28ae6c2f30ce6e5a75586f0e83bcac77c9135e980e6bc7a8b45ad160634c528cc3d2926d9807104fa3157305b45ad160634c528cc3d2926d9807104fa3157305865377367054516e17014ccded1e7d814edc9ce466a1e37c9b0eaddca17d3662d6c05f4decf3e1108272e1a3dbef607c04aa6e5bd3a1a134c8ac063b8b83c4aa949254895507d09365229bc3a8c7f710a3931d71877c0e7a3148cb7eb4463524fec27fbd000000000000000000000000000000000000000000000000";

    //     console.log("amountToWithdraw", amountToWithdraw);
    //     dbr.approve(address(ale), type(uint).max);
    //     ale.deleveragePosition(
    //         market.debts(userPk),
    //         address(market),
    //         odos,
    //         amountToWithdraw,
    //         swapData,
    //         permit,
    //         abi.encode(address(market)),
    //         dbrData
    //     );

    //     // All collateral withdrawn and zero debt
    //     assertEq(
    //         IERC20(sFraxAddr).balanceOf(address(market.predictEscrow(userPk))),
    //         0, 'COLLATERAL'
    //     );
    //     assertEq(market.debts(userPk), 0);
    //     // User receives Dola from selling his collateral and actually he has more bc he sold all his DBR
    //     uint256 amountDolaOut = 211963293517859369517056; // Odos output swap
    //     assertGt(DOLA.balanceOf(userPk), 211963293517859369517056 - borrowAmount, 'DOLA');
    //     assertEq(IERC20(fraxAddr).balanceOf(userPk), 0, 'FRAX');
    //     assertEq(dbr.balanceOf(userPk), 0);
    // }
  

    function _convertCollatToDola(uint amount) internal view returns (uint) {
        uint256 underlying = IERC4626(sFraxAddr).convertToAssets(amount);
        return _convertUnderlyingToDola(underlying);
    }

    function _convertDolaToCollat(uint amount) internal view returns (uint) {
        uint256 underlying = _convertDolaToUnderlying(amount);
        console.log(underlying, "underlying");
        return IERC4626(sFraxAddr).convertToShares(underlying);
    }

    function _convertDolaToUnderlying(
        uint amount
    ) internal view returns (uint) {
        console.log(amount, "amount");
        return (amount * 1e18) / oracle.viewPrice(fraxAddr, 0);
    }

    function _convertUnderlyingToDola(
        uint amount
    ) internal view returns (uint) {
        return (amount * oracle.viewPrice(fraxAddr, 0)) / 1e18;
    }

    function _getMaxBorrowAmount(
        uint amountCollat
    ) internal view returns (uint) {
        return
            (_convertCollatToDola(amountCollat) *
                market.collateralFactorBps()) / 10_000;
    }

    function gibDBR(address _address, uint _amount) internal {
        vm.startPrank(gov);
        dbr.mint(_address, _amount);
        vm.stopPrank();
    }

    function gibDOLA(address _address, uint _amount) internal {
        vm.startPrank(gov);
        DOLA.mint(_address, _amount);
        vm.stopPrank();
    }

    function codeAt(address _addr) public view returns (bytes memory o_code) {
        assembly {
            // retrieve the size of the code, this needs assembly
            let size := extcodesize(_addr)
            // allocate output byte array - this could also be done without assembly
            // by using o_code = new bytes(size)
            o_code := mload(0x40)
            // new "memory end" including padding
            mstore(
                0x40,
                add(o_code, and(add(add(size, 0x20), 0x1f), not(0x1f)))
            )
            // store length in memory
            mstore(o_code, size)
            // actually retrieve the code, this needs assembly
            extcodecopy(_addr, add(o_code, 0x20), 0, size)
        }
    }
}
