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
import {BaseHelperForkTest, IERC4626} from "src/test/BaseHelperForkTest.t.sol";

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

contract MockExchangeProxy {
    IOracle oracle;
    IERC20 dola;

    constructor(address _oracle, address _dola) {
        oracle = IOracle(_oracle);
        dola = IERC20(_dola);
    }

    function swapDolaIn(
        IERC20 collateral,
        uint256 dolaAmount
    ) external returns (bool success, bytes memory ret) {
        dola.transferFrom(msg.sender, address(this), dolaAmount);
        uint256 collateralAmount = (dolaAmount * 1e18) /
            oracle.viewPrice(address(collateral), 0);
        collateral.transfer(msg.sender, collateralAmount);
        success = true;
    }

    function swapDolaOut(
        IERC20 collateral,
        uint256 collateralAmount
    ) external returns (bool success, bytes memory ret) {
        collateral.transferFrom(msg.sender, address(this), collateralAmount);
        uint256 dolaAmount = (collateralAmount *
            oracle.viewPrice(address(collateral), 0)) / 1e18;
        dola.transfer(msg.sender, dolaAmount);
        success = true;
    }
}

contract ALEsFrax4626HelperForkTest is BaseHelperForkTest {
    using stdStorage for StdStorage;

    //Market deployment:
    Market market;
    IChainlinkFeed feed;
    BorrowController borrowController;

    //EOAs & Multisigs
    address user = address(0x69);
    address user2 = address(0x70);
    address replenisher = address(0x71);
    address collatHolder = address(0x577eBC5De943e35cdf9ECb5BbE1f7D7CB6c7C647); // sty CRV
    //address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    // address chair = address(0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8);
    // address pauseGuardian = address(0xE3eD95e130ad9E15643f5A5f232a3daE980784cd);
    address curvePool = address(0x056ef502C1Fc5335172bc95EC4cAE16C2eB9b5b6); // DBR/DOLA pool

    address sFraxHolder = 0x440888714A6afeD60ff44e9975A96E6a36f7Fac4;
    address fraxHolder = 0x5E583B6a1686f7Bc09A6bBa66E852A7C80d36F00;

    address sFrax = 0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32; // sFrax
    address frax = 0x853d955aCEf822Db058eb8505911ED77F175b99e; //frax
    address triDBR = address(0xC7DE47b9Ca2Fc753D6a2F167D8b3e19c6D18b19a);

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
    uint replenishmentIncentiveBps;
    uint liquidationBonusBps;
    uint replenishmentPriceBps;

    function getBlockNumber() public view override returns (uint256) {
        return 19884238;
    }

    function setUp() public override {
        super.setUp();

        DOLA = IMintable(dolaAddr);
        market = Market(sFraxMarketAddr); // sFrax
        feed = IChainlinkFeed(sFraxFeedAddr); // sFraxFeed
        borrowController = BorrowController(borrowControllerAddr);
        dbr = DolaBorrowingRights(dbrAddr);

        replenishmentIncentiveBps = market.replenishmentIncentiveBps();
        liquidationBonusBps = market.liquidationIncentiveBps();
        replenishmentPriceBps = dbr.replenishmentPriceBps();

        helper = new ERC4626Helper(gov, pauseGuardian);
        initBase(address(helper));

        exchangeProxy = new MockExchangeProxy(
            address(market.oracle()),
            address(DOLA)
        );

        vm.startPrank(gov);
        helper.setMarket(address(market), address(frax), address(sFrax));
        dbr.addMarket(address(market));
        DOLA.mint(address(market), 1000000e18);
        vm.stopPrank();

        ale = new ALE(address(exchangeProxy), triDBR);
        ale.setMarket(
            address(market),
            fraxAddr,
            address(market.collateral()),
            address(helper)
        );

        //FiRM
        oracle = Oracle(address(market.oracle()));
        escrowImplementation = IEscrow(market.escrowImplementation());
        fed = Fed(market.lender());
        collateral = IErc20(address(market.collateral()));

        vm.label(user, "user");
        vm.label(user2, "user2");

        //Warp forward 7 days since local chain timestamp is 0, will cause revert when calculating `days` in oracle.
        //vm.warp(block.timestamp + 7 days);

        vm.startPrank(gov, gov);
        market.setBorrowController(
            IBorrowController(address(borrowController))
        );
        market.setCollateralFactorBps(8000);
        borrowController.setDailyLimit(address(market), 250_000 * 1e18);
        IBC(address(borrowController)).setStalenessThreshold(
            address(market),
            1 days
        );

        market.setLiquidationFactorBps(5000);
        market.setLiquidationIncentiveBps(500);
        IBC(address(borrowController)).setMinDebt(address(market), 0);
        fed.changeMarketCeiling(IMarket(address(market)), type(uint).max);
        fed.changeSupplyCeiling(type(uint).max);
        oracle.setFeed(address(collateral), feed, 18);

        oracle.setFeed(frax, IChainlinkFeed(address(fraxUsdFeedAddr)), 18);
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
            IErc20(sFrax).balanceOf(address(market.predictEscrow(userPk))),
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
        IERC20(sFrax).transfer(userPk, sFraxAmount);

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
        IERC20(frax).transfer(address(exchangeProxy), fraxAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        IErc20(sFrax).approve(address(market), sFraxAmount);
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
            frax,
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
            IErc20(sFrax).balanceOf(address(market.predictEscrow(userPk))),
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
        IERC20(sFrax).transfer(userPk, sFraxAmount);

        uint maxBorrowAmount = _getMaxBorrowAmount(sFraxAmount);

        uint256 fraxAmount = helper.collateralToAsset(
            address(market),
            _convertDolaToCollat(maxBorrowAmount)
        );

        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.prank(fraxHolder);
        IERC20(frax).transfer(address(exchangeProxy), fraxAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial st-frax deposit
        IErc20(sFrax).approve(address(market), sFraxAmount);
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
            frax,
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
        IERC20(sFrax).transfer(userPk, sFraxAmount);

        gibDBR(userPk, sFraxAmount);

        uint borrowAmount = (_getMaxBorrowAmount(sFraxAmount) * 97) / 100;

        vm.startPrank(userPk, userPk);
        // Initial sFrax deposit
        IErc20(sFrax).approve(address(market), sFraxAmount);
        market.deposit(sFraxAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        assertEq(
            IERC20(sFrax).balanceOf(address(market.predictEscrow(userPk))),
            sFraxAmount
        );
        assertEq(DOLA.balanceOf(userPk), borrowAmount);

        // We are going to withdraw only 1/10 of the collateral to deleverage
        uint256 amountToWithdraw = IERC20(sFrax).balanceOf(
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
            frax,
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
            IERC20(sFrax).balanceOf(address(market.predictEscrow(userPk))),
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
        IERC20(sFrax).transfer(userPk, sFraxAmount);

        gibDBR(userPk, sFraxAmount);

        uint borrowAmount = (_getMaxBorrowAmount(sFraxAmount) * 97) / 100;

        vm.startPrank(userPk, userPk);
        // Initial sFrax deposit
        IErc20(sFrax).approve(address(market), sFraxAmount);
        market.deposit(sFraxAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        address userEscrow = address(market.predictEscrow(userPk));
        assertEq(IERC20(sFrax).balanceOf(userEscrow), sFraxAmount);
        assertEq(DOLA.balanceOf(userPk), borrowAmount);

        // We are going to withdraw only 1/10 of the collateral to deleverage
        uint256 amountToWithdraw = IERC20(sFrax).balanceOf(userEscrow) / 10;
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
            frax,
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
            IERC20(sFrax).balanceOf(userEscrow),
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
        IERC20(frax).transfer(userPk, fraxAmount);

        vm.startPrank(userPk, userPk);
        IErc20(frax).approve(address(helper), fraxAmount);
        helper.transformToCollateralAndDeposit(
            fraxAmount,
            userPk,
            abi.encode(address(market))
        );

        assertEq(IERC20(frax).balanceOf(userPk), 0);

        assertEq(
            IErc20(sFrax).balanceOf(address(market.predictEscrow(userPk))),
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
        IERC20(frax).transfer(userPk, fraxAmount);

        vm.startPrank(userPk, userPk);
        IErc20(frax).approve(address(helper), fraxAmount);
        helper.transformToCollateralAndDeposit(
            fraxAmount,
            userPk,
            abi.encode(address(market))
        );

        //Market market = Market(address(helper.market())); // actual Mainnet market for helper contract
        uint256 amountToWithdraw = IErc20(sFrax).balanceOf(
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

        assertEq(IERC20(frax).balanceOf(userPk), 0);

        helper.withdrawAndTransformFromCollateral(
            amountToWithdraw,
            userPk,
            permit,
            abi.encode(address(market))
        );

        assertApproxEqAbs(
            IERC20(frax).balanceOf(userPk),
            helper.collateralToAsset(address(market), amountToWithdraw),
            1
        );
    }

    function test_fail_setMarket_NoMarket() public {
        address fakeMarket = address(0x69);

        vm.expectRevert(
            abi.encodeWithSelector(ALE.NoMarket.selector, fakeMarket)
        );
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
        ale.updateMarketHelper(wrongMarket, newHelper);
    }

    function test_return_assetAmount_when_TotalSupply_is_Zero() public {
        stdstore
            .target(address(sFrax))
            .sig(IERC4626(sFrax).totalSupply.selector)
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
        IERC20(sFrax).transfer(userPk, sFraxAmount);

        gibDBR(userPk, sFraxAmount);

        uint maxBorrowAmount = _getMaxBorrowAmount(sFraxAmount);

        uint256 fraxAmount = helper.collateralToAsset(
            address(market),
            _convertDolaToCollat(maxBorrowAmount)
        );
        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.prank(fraxHolder);
        IERC20(frax).transfer(address(exchangeProxy), fraxAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        IErc20(sFrax).approve(address(market), sFraxAmount);
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
            frax,
            maxBorrowAmount
        );

        ALE.DBRHelper memory dbrData;

        // Mock call to return 0 buySellToken balance for the ALE
        vm.mockCall(
            frax,
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
        return (amount * 1e18) / oracle.viewPrice(frax, 0);
    }

    function _convertUnderlyingToDola(
        uint amount
    ) internal view returns (uint) {
        return (amount * oracle.viewPrice(frax, 0)) / 1e18;
    }

    function _getMaxBorrowAmount(
        uint amountCollat
    ) internal view returns (uint) {
        return
            (_convertCollatToDola(amountCollat) *
                market.collateralFactorBps()) / 10_000;
    }

    function gibWeth(address _address, uint _amount) internal {
        vm.startPrank(collatHolder, collatHolder);
        collateral.transfer(_address, _amount);
        vm.stopPrank();
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
