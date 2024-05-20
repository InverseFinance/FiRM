// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../BorrowController.sol";
import "../DBR.sol";
import "../Fed.sol";
import "../Market.sol";
import "../Oracle.sol";
import {ALE} from "../util/ALE.sol";
import {ERC4626Helper} from "src/util/ERC4626Helper.sol";
import {ITransformHelper} from "src/interfaces/ITransformHelper.sol";
import {console} from "forge-std/console.sol";
import {BaseHelperForkTest, IERC4626, MockExchangeProxy} from "src/test/BaseHelperForkTest.t.sol";

interface IErc20 is IERC20 {
    function approve(address beneficiary, uint amount) external;
}

interface IMintable is IErc20 {
    function mint(address receiver, uint amount) external;

    function addMinter(address minter) external;
}

interface IBC {
    function setMinDebt(address market, uint256 minDebt) external;

    function setStalenessThreshold(address market, uint256 threshold) external;
}

contract ALEsFrax4626HelperForkTest is BaseHelperForkTest {
    using stdStorage for StdStorage;

    //Market deployment:
    Market market;
    IChainlinkFeed feed;
    BorrowController borrowController;

    address sFraxHolder = 0x440888714A6afeD60ff44e9975A96E6a36f7Fac4;
    address fraxHolder = 0x5E583B6a1686f7Bc09A6bBa66E852A7C80d36F00;

    //ERC-20s
    IMintable DOLA;
    IErc20 collateral;

    //FiRM
    Oracle oracle;
    IEscrow escrowImplementation;
    DolaBorrowingRights dbr;
    Fed fed;

    MockExchangeProxy exchangeProxy;
    ALE ale;

    ERC4626Helper helper;
    //Variables
    uint collateralFactorBps;

    function getBlockNumber() public view override returns (uint256) {
        return 19884238;
    }

    function setUp() public override {
        super.setUp();

        DOLA = IMintable(dolaAddr);
        market = Market(sFraxMarketAddr);
        feed = IChainlinkFeed(sFraxFeedAddr);
        borrowController = BorrowController(borrowControllerAddr);
        dbr = DolaBorrowingRights(dbrAddr);
        helper = new ERC4626Helper(gov, pauseGuardian);
        initBase(address(helper));

        exchangeProxy = new MockExchangeProxy(
            address(market.oracle()),
            address(DOLA)
        );

        vm.startPrank(gov);
        helper.setMarket(address(market), fraxAddr, sFraxAddr);
        dbr.addMarket(address(market));
        DOLA.mint(address(market), 1000000e18);

        ale = new ALE(address(exchangeProxy), triDBRAddr);
        ale.setMarket(
            address(market),
            fraxAddr,
            address(market.collateral()),
            address(helper)
        );
        vm.stopPrank();
        //FiRM
        oracle = Oracle(address(market.oracle()));
        escrowImplementation = IEscrow(market.escrowImplementation());
        fed = Fed(market.lender());
        collateral = IErc20(address(market.collateral()));

        vm.startPrank(gov, gov);
        market.setBorrowController(
            IBorrowController(address(borrowController))
        );
        market.setCollateralFactorBps(8000);
        borrowController.setDailyLimit(address(market), 250_000 * 1e18);
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
        vm.stopPrank();

        collateralFactorBps = market.collateralFactorBps();
    }

    function checkEq(
        uint sFraxDeposit,
        uint collateralToSwap,
        address userPk
    ) internal {
        assertApproxEqAbs(
            IErc20(sFraxAddr).balanceOf(address(market.predictEscrow(userPk))),
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
        uint256 fraxAmount = helper.collateralToAsset(
            address(market),
            _convertDolaToCollat(maxBorrowAmount)
        );
        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.prank(fraxHolder);
        IERC20(fraxAddr).transfer(address(exchangeProxy), fraxAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        IErc20(sFraxAddr).approve(address(market), sFraxAmount);
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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            fraxAddr,
            maxBorrowAmount
        );

        ALE.DBRHelper memory dbrData;

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
            IErc20(sFraxAddr).balanceOf(address(market.predictEscrow(userPk))),
            sFraxAmount +
                helper.assetToCollateral(
                    address(market),
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

        uint256 fraxAmount = helper.collateralToAsset(
            address(market),
            _convertDolaToCollat(maxBorrowAmount)
        );

        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.prank(fraxHolder);
        IERC20(fraxAddr).transfer(address(exchangeProxy), fraxAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial st-frax deposit
        IErc20(sFraxAddr).approve(address(market), sFraxAmount);
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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            fraxAddr,
            maxBorrowAmount
        );

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
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
        IErc20(sFraxAddr).approve(address(market), sFraxAmount);
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
            helper.collateralToAsset(address(market), amountToWithdraw)
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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
            dbr.balanceOf(userPk),
            0,
            0
        ); // sell all DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            fraxAddr,
            helper.collateralToAsset(address(market), amountToWithdraw)
        );

        vm.startPrank(userPk, userPk);
        dbr.approve(address(ale), type(uint).max);

        ale.deleveragePosition(
            _convertCollatToDola(amountToWithdraw),
            address(market),
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            abi.encode(address(market)),
            dbrData
        );

        // Some collateral has been withdrawn
        assertEq(
            IERC20(sFraxAddr).balanceOf(address(market.predictEscrow(userPk))),
            sFraxAmount - amountToWithdraw
        );

        // User still has dola and actually he has more bc he sold his DBRs
        assertGt(DOLA.balanceOf(userPk), borrowAmount);

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
        IErc20(sFraxAddr).approve(address(market), sFraxAmount);
        market.deposit(sFraxAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        address userEscrow = address(market.predictEscrow(userPk));
        assertEq(IERC20(sFraxAddr).balanceOf(userEscrow), sFraxAmount);
        assertEq(DOLA.balanceOf(userPk), borrowAmount);

        // We are going to withdraw only 1/10 of the collateral to deleverage
        uint256 amountToWithdraw = IERC20(sFraxAddr).balanceOf(userEscrow) / 10;
        uint256 dolaAmountForSwap = _convertUnderlyingToDola(
            helper.collateralToAsset(address(market), amountToWithdraw)
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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(0, 0, borrowAmount / 2); // repay partially debt with DOLA in the wallet

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            fraxAddr,
            helper.collateralToAsset(address(market), amountToWithdraw)
        );

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(ale), borrowAmount / 2);

        ale.deleveragePosition(
            _convertCollatToDola(amountToWithdraw),
            address(market),
            amountToWithdraw,
            address(exchangeProxy),
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

    function test_transformToCollateralAndDeposit(uint256 fraxAmount) public {
        //vm.assume(fraxAmount < 1 ether);

        uint256 fraxAmount = 1 ether;
        address userPk = vm.addr(1);
        vm.prank(fraxHolder);
        IERC20(fraxAddr).transfer(userPk, fraxAmount);

        vm.startPrank(userPk, userPk);
        IErc20(fraxAddr).approve(address(helper), fraxAmount);
        helper.transformToCollateralAndDeposit(
            fraxAmount,
            userPk,
            abi.encode(address(market))
        );

        assertEq(IERC20(fraxAddr).balanceOf(userPk), 0);

        assertEq(
            IErc20(sFraxAddr).balanceOf(address(market.predictEscrow(userPk))),
            helper.assetToCollateral(address(market), fraxAmount)
        );
    }

    function test_withdrawAndTransformFromCollateral(
        uint256 fraxAmount
    ) public {
        // vm.assume(fraxAmount < IsFrax(sFrax).availableDepositLimit());

        uint256 fraxAmount = 1 ether;
        address userPk = vm.addr(1);
        vm.prank(fraxHolder);
        IERC20(fraxAddr).transfer(userPk, fraxAmount);

        vm.startPrank(userPk, userPk);
        IErc20(fraxAddr).approve(address(helper), fraxAmount);
        helper.transformToCollateralAndDeposit(
            fraxAmount,
            userPk,
            abi.encode(address(market))
        );

        //Market market = Market(address(helper.market())); // actual Mainnet market for helper contract
        uint256 amountToWithdraw = IErc20(sFraxAddr).balanceOf(
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

        ITransformHelper.Permit memory permit = ITransformHelper.Permit(
            block.timestamp,
            v,
            r,
            s
        );

        assertEq(IERC20(fraxAddr).balanceOf(userPk), 0);

        helper.withdrawAndTransformFromCollateral(
            amountToWithdraw,
            userPk,
            permit,
            abi.encode(address(market))
        );

        assertApproxEqAbs(
            IERC20(fraxAddr).balanceOf(userPk),
            helper.collateralToAsset(address(market), amountToWithdraw),
            1
        );
    }

    function test_fail_setMarket_NoMarket() public {
        address fakeMarket = address(0x69);

        vm.expectRevert(
            abi.encodeWithSelector(ALE.NoMarket.selector, fakeMarket)
        );
        vm.prank(gov);
        ale.setMarket(fakeMarket, address(0), address(0), address(0));
    }

    function test_fail_setMarket_WrongCollateral_WithHelper() public {
        address fakeCollateral = address(0x69);

        vm.expectRevert(
            abi.encodeWithSelector(
                ALE.WrongCollateral.selector,
                address(market),
                fakeCollateral,
                address(0),
                address(helper)
            )
        );
        vm.prank(gov);
        ale.setMarket(
            address(market),
            fakeCollateral,
            address(0),
            address(helper)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ALE.WrongCollateral.selector,
                address(market),
                address(0),
                fakeCollateral,
                address(helper)
            )
        );
        vm.prank(gov);
        ale.setMarket(
            address(market),
            address(0),
            fakeCollateral,
            address(helper)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ALE.WrongCollateral.selector,
                address(market),
                fakeCollateral,
                fakeCollateral,
                address(helper)
            )
        );
        vm.prank(gov);
        ale.setMarket(
            address(market),
            fakeCollateral,
            fakeCollateral,
            address(helper)
        );
    }

    function test_fail_updateMarketHelper_NoMarket() public {
        address wrongMarket = address(0x69);
        address newHelper = address(0x70);

        vm.expectRevert(
            abi.encodeWithSelector(ALE.MarketNotSet.selector, wrongMarket)
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
        assertEq(
            assetAmount,
            helper.assetToCollateral(address(market), assetAmount)
        );
    }

    function test_fail_collateral_is_zero_leveragePosition() public {
        // We are going to deposit some CRV, then leverage the position
        uint sFraxAmount = 10000 ether;
        address userPk = vm.addr(1);
        vm.prank(sFraxHolder);
        IERC20(sFraxAddr).transfer(userPk, sFraxAmount);

        gibDBR(userPk, sFraxAmount);

        uint maxBorrowAmount = _getMaxBorrowAmount(sFraxAmount);

        uint256 fraxAmount = helper.collateralToAsset(
            address(market),
            _convertDolaToCollat(maxBorrowAmount)
        );
        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.prank(fraxHolder);
        IERC20(fraxAddr).transfer(address(exchangeProxy), fraxAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        IErc20(sFraxAddr).approve(address(market), sFraxAmount);
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

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            fraxAddr,
            maxBorrowAmount
        );

        ALE.DBRHelper memory dbrData;

        // Mock call to return 0 buySellToken balance for the ALE
        vm.mockCall(
            fraxAddr,
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(ale)),
            abi.encode(uint256(0))
        );

        vm.expectRevert(ALE.CollateralIsZero.selector);
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

    function _convertCollatToDola(uint amount) internal view returns (uint) {
        uint256 underlying = helper.collateralToAsset(address(market), amount);
        return _convertUnderlyingToDola(underlying);
    }

    function _convertDolaToCollat(uint amount) internal view returns (uint) {
        uint256 underlying = _convertDolaToUnderlying(amount);
        console.log(underlying, "underlying");
        return helper.assetToCollateral(address(market), underlying);
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
