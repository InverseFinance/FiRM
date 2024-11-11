// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {BorrowController} from "src/BorrowController.sol";
import "src/DBR.sol";
import {Market, IBorrowController} from "src/Market.sol";
import {Oracle, IChainlinkFeed} from "src/Oracle.sol";
import {YVYCRVHelper, YearnVaultV2Helper, IYearnVaultV2} from "src/util/YVYCRVHelper.sol";
import {YCRVFeed} from "test/mocks/YCRVFeed.sol";
import {Fed, IMarket} from "src/Fed.sol";
import {ALE} from "src/util/ALE.sol";
import {YCRVFeed} from "test/mocks/YCRVFeed.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {BaseHelperForkTest, MockExchangeProxy} from "test/util/aleTests/BaseHelperForkTest.t.sol";
import {Fed, IMarket} from "src/Fed.sol";

interface IMintable is IERC20 {
    function mint(address receiver, uint amount) external;

    function addMinter(address minter) external;
}

interface IFlashMinter {
    function setMaxFlashLimit(uint256 limit) external;
}

interface IBC {
    function setMinDebt(address market, uint256 minDebt) external;

    function setStalenessThreshold(address market, uint256 threshold) external;
}

interface ISimpleERC20Escrow {
    function balance() external view returns (uint256);
}

interface IYCRV {
    function mint(uint256 amount) external returns (uint256);
}

contract ALEyvyCRVHelperForkTest is BaseHelperForkTest {
    using stdStorage for StdStorage;

    //Market deployment:
    Market market;
    IChainlinkFeed feed;
    BorrowController borrowController;

    address yCRV = address(0xFCc5c47bE19d06BF83eB04298b026F81069ff65b);
    address CRV = address(0xD533a949740bb3306d119CC777fa900bA034cd52);

    // User
    address userPk;

    //ERC-20s
    IMintable DOLA;
    IERC20 collateral;

    //FiRM
    address escrow;
    Oracle oracle;
    DolaBorrowingRights dbr;

    // ALE
    ALE ale;
    YVYCRVHelper helper;
    IFlashMinter flash;

    // Mocks
    YCRVFeed feedYCRV;
    MockExchangeProxy exchangeProxy;

    //Variables
    uint collateralFactorBps;

    function setUp() public override {
        super.setUp();

        DOLA = IMintable(dolaAddr);
        market = Market(yvyCRVMarketAddr); // yvyCRV Market
        feed = IChainlinkFeed(yvyCRVFeedAddr);
        borrowController = BorrowController(borrowControllerAddr);
        dbr = DolaBorrowingRights(dbrAddr);

        helper = new YVYCRVHelper(gov, pauseGuardian);
        initBase(address(helper));
        feedYCRV = new YCRVFeed();

        exchangeProxy = new MockExchangeProxy(
            address(market.oracle()),
            address(DOLA)
        );

        Fed fed = Fed(market.lender());
        vm.startPrank(gov);
        market.pauseBorrows(false);
        borrowController.setDailyLimit(address(market), 5000000 ether);
        fed.changeMarketCeiling(IMarket(address(market)), 100000000 ether);
        vm.stopPrank();

        vm.prank(chair);
        fed.expansion(IMarket(address(market)), 5000000 ether);

        ale = new ALE(address(exchangeProxy), triDBRAddr);
        ale.setMarket(address(market), yCRV, address(helper), true);

        //FiRM
        oracle = Oracle(address(market.oracle()));
        collateral = IERC20(address(market.collateral()));

        vm.startPrank(gov, gov);

        IBC(address(borrowController)).setMinDebt(address(market), 0);
        oracle.setFeed(address(collateral), feed, 18);
        oracle.setFeed(yCRV, IChainlinkFeed(address(feedYCRV)), 18);
        borrowController.allow(address(ale));

        flash = IFlashMinter(address(ale.flash()));
        DOLA.addMinter(address(flash));
        flash.setMaxFlashLimit(5000000e18); // 5M DOLA
        vm.stopPrank();

        collateralFactorBps = market.collateralFactorBps();
        userPk = vm.addr(1);

        escrow = address(market.predictEscrow(userPk));
        // For Recharging proxy
        deal(CRV, address(this), 15_000_000 ether);
        IERC20(CRV).approve(address(yCRV), 15_000_000 ether);
        IYCRV(yCRV).mint(15_000_000 ether);

        // Fill userPk with some yvyCRV
        deal(CRV, userPk, 30_000_000 ether); // 30M CRV => roughly 7.5M USD
        vm.startPrank(userPk);
        IERC20(CRV).approve(address(yCRV), 30_000_000 ether);
        uint256 yCRVAmount = IYCRV(yCRV).mint(30_000_000 ether);
        assertEq(yCRVAmount, IERC20(yCRV).balanceOf(userPk));
        IERC20(yCRV).approve(yvyCRVAddr, yCRVAmount);
        uint256 yvyCRVAmount = IYearnVaultV2(yvyCRVAddr).deposit(
            yCRVAmount,
            userPk
        ); // 16.94M yvyCRV
        assertEq(yvyCRVAmount, IERC20(yvyCRVAddr).balanceOf(userPk));
        assertEq(0, IERC20(yCRV).balanceOf(userPk));
        vm.stopPrank();
    }

    function getBlockNumber() public view override returns (uint256) {
        return 20590050;
    }

    function checkEq(
        uint stYCRVDeposit,
        uint collateralToSwap,
        address userPk
    ) internal {
        assertApproxEqAbs(
            IERC20(yvyCRVAddr).balanceOf(address(market.predictEscrow(userPk))),
            stYCRVDeposit + collateralToSwap,
            1
        );
    }

    function test_leveragePosition(uint256 styCRVAmount) public {
        vm.assume(styCRVAmount < IERC20(yvyCRVAddr).balanceOf(userPk)); // 16.94M yvyCRV
        vm.assume(styCRVAmount > 0.00000001 ether);
        // We are going to deposit some yvyCRV, then leverage the position

        gibDBR(userPk, styCRVAmount);

        uint maxBorrowAmount = _getMaxBorrowAmount(styCRVAmount);

        uint256 yCRVAmount = YearnVaultV2Helper.collateralToAsset(
            IYearnVaultV2(yvyCRVAddr),
            _convertDolaToCollat(maxBorrowAmount)
        );
        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        IERC20(yCRV).transfer(address(exchangeProxy), yCRVAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial yvyCRV deposit
        IERC20(yvyCRVAddr).approve(address(market), styCRVAmount);
        market.deposit(styCRVAmount);

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
            yCRV,
            maxBorrowAmount
        );

        ALE.DBRHelper memory dbrData;

        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        uint256 expectedCollateral = styCRVAmount +
            YearnVaultV2Helper.assetToCollateral(
                IYearnVaultV2(yvyCRVAddr),
                _convertDolaToUnderlying(maxBorrowAmount)
            );
        assertApproxEqAbs(
            IERC20(yvyCRVAddr).balanceOf(address(market.predictEscrow(userPk))),
            expectedCollateral,
            1
        );
        assertApproxEqAbs(
            ISimpleERC20Escrow(escrow).balance(),
            expectedCollateral,
            1
        );
        assertEq(DOLA.balanceOf(userPk), 0);
    }

    function test_depositAndLeveragePosition(uint256 styCRVAmount) public {
        vm.assume(styCRVAmount < IERC20(yvyCRVAddr).balanceOf(userPk));
        vm.assume(styCRVAmount > 0.00000001 ether);
        // We are going to deposit some CRV, then leverage the position

        gibDBR(userPk, styCRVAmount);

        uint maxBorrowAmount = _getMaxBorrowAmount(styCRVAmount);

        uint256 yCRVAmount = YearnVaultV2Helper.collateralToAsset(
            IYearnVaultV2(yvyCRVAddr),
            _convertDolaToCollat(maxBorrowAmount)
        );
        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        IERC20(yCRV).transfer(address(exchangeProxy), yCRVAmount + 2);

        vm.startPrank(userPk, userPk);
        // yvyCRV deposit to be leveraged
        IERC20(yvyCRVAddr).approve(address(ale), styCRVAmount);

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
            yCRV,
            maxBorrowAmount
        );

        ALE.DBRHelper memory dbrData;

        ale.depositAndLeveragePosition(
            styCRVAmount,
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData,
            true
        );

        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        uint256 expectedCollateral = styCRVAmount +
            YearnVaultV2Helper.assetToCollateral(
                IYearnVaultV2(yvyCRVAddr),
                _convertDolaToUnderlying(maxBorrowAmount)
            );
        assertApproxEqAbs(
            IERC20(yvyCRVAddr).balanceOf(address(market.predictEscrow(userPk))),
            expectedCollateral,
            1
        );
        assertApproxEqAbs(
            ISimpleERC20Escrow(escrow).balance(),
            expectedCollateral,
            1
        );
        assertEq(DOLA.balanceOf(userPk), 0);
    }

    function test_leveragePosition_buyDBR(uint256 styCRVAmount) public {
        // We are going to deposit some st-yCRV, then leverage the position
        vm.assume(styCRVAmount < IERC20(yvyCRVAddr).balanceOf(userPk));
        vm.assume(styCRVAmount > 0.1 ether);

        uint maxBorrowAmount = _getMaxBorrowAmount(styCRVAmount);

        uint256 yCRVAmount = YearnVaultV2Helper.collateralToAsset(
            IYearnVaultV2(yvyCRVAddr),
            _convertDolaToCollat(maxBorrowAmount)
        );

        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        IERC20(yCRV).transfer(address(exchangeProxy), yCRVAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial yvyCRV deposit
        IERC20(yvyCRVAddr).approve(address(market), styCRVAmount);
        market.deposit(styCRVAmount);

        // Calculate the amount of DOLA needed to borrow to buy the DBR needed to cover for the borrowing period
        (uint256 dolaForDBR, uint256 dbrAmount) = ale
            .approximateDolaAndDbrNeeded(maxBorrowAmount, 10 days, 8);

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
            yCRV,
            maxBorrowAmount
        );

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
            dolaForDBR,
            (dbrAmount * 89) / 100,
            0
        );

        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        checkEq(styCRVAmount, _convertDolaToCollat(maxBorrowAmount), userPk);
        assertApproxEqAbs(
            ISimpleERC20Escrow(escrow).balance(),
            styCRVAmount +
                YearnVaultV2Helper.assetToCollateral(
                    IYearnVaultV2(yvyCRVAddr),
                    _convertDolaToUnderlying(maxBorrowAmount)
                ),
            1
        );
        assertEq(DOLA.balanceOf(userPk), 0);

        assertGt(dbr.balanceOf(userPk), (dbrAmount * 89) / 100);
    }

    function test_deleveragePosition_sellDBR(uint256 styCRVAmount) public {
        vm.assume(styCRVAmount < IERC20(yvyCRVAddr).balanceOf(userPk)); // 16.94M yvyCRV
        vm.assume(styCRVAmount > 0.00000001 ether);
        // We are going to deposit some st-yCRV, then borrow and then deleverage the position

        gibDBR(userPk, styCRVAmount);

        uint borrowAmount = (_getMaxBorrowAmount(styCRVAmount) * 97) / 100;

        vm.startPrank(userPk, userPk);
        // Initial styCRV deposit
        IERC20(yvyCRVAddr).approve(address(market), styCRVAmount);
        market.deposit(styCRVAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        assertEq(
            IERC20(yvyCRVAddr).balanceOf(address(market.predictEscrow(userPk))),
            styCRVAmount
        );
        assertEq(DOLA.balanceOf(userPk), borrowAmount);

        // We are going to withdraw only 1/10 of the collateral to deleverage
        uint256 amountToWithdraw = IERC20(yvyCRVAddr).balanceOf(
            address(market.predictEscrow(userPk))
        ) / 10;

        uint256 dolaAmountForSwap = _convertUnderlyingToDola(
            YearnVaultV2Helper.collateralToAsset(
                IYearnVaultV2(yvyCRVAddr),
                amountToWithdraw
            )
        );

        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), dolaAmountForSwap + 1);
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
            yCRV,
            YearnVaultV2Helper.collateralToAsset(
                IYearnVaultV2(yvyCRVAddr),
                amountToWithdraw
            ) - 1
        );

        vm.startPrank(userPk, userPk);
        dbr.approve(address(ale), type(uint).max);

        ale.deleveragePosition(
            _convertCollatToDola(amountToWithdraw) - 1, // repay little less bc of yearn 1 wei conversion loss
            address(market),
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // Some collateral has been withdrawn
        assertEq(
            IERC20(yvyCRVAddr).balanceOf(address(market.predictEscrow(userPk))),
            styCRVAmount - amountToWithdraw
        );
        assertEq(
            ISimpleERC20Escrow(escrow).balance(),
            styCRVAmount - amountToWithdraw
        );
        // User still has dola and actually he has more bc he sold his DBRs
        assertGt(DOLA.balanceOf(userPk), borrowAmount);

        assertEq(dbr.balanceOf(userPk), 0);
    }

    function test_deleveragePosition(uint256 styCRVAmount) public {
        vm.assume(styCRVAmount < IERC20(yvyCRVAddr).balanceOf(userPk)); // 16.94M yvyCRV
        vm.assume(styCRVAmount > 0.00000001 ether);

        // We are going to deposit some yvyCRV, then borrow and then deleverage the position

        gibDBR(userPk, styCRVAmount);

        uint borrowAmount = (_getMaxBorrowAmount(styCRVAmount) * 97) / 100;

        vm.startPrank(userPk, userPk);
        // Initial styCRV deposit
        IERC20(yvyCRVAddr).approve(address(market), styCRVAmount);
        market.deposit(styCRVAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        address userEscrow = address(market.predictEscrow(userPk));
        assertEq(IERC20(yvyCRVAddr).balanceOf(userEscrow), styCRVAmount);
        assertEq(DOLA.balanceOf(userPk), borrowAmount);

        // We are going to withdraw only 1/10 of the collateral to deleverage
        uint256 amountToWithdraw = IERC20(yvyCRVAddr).balanceOf(userEscrow) /
            10;
        uint256 dolaAmountForSwap = _convertUnderlyingToDola(
            YearnVaultV2Helper.collateralToAsset(
                IYearnVaultV2(yvyCRVAddr),
                amountToWithdraw
            )
        );

        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), dolaAmountForSwap + 2);
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
            yCRV,
            YearnVaultV2Helper.collateralToAsset(
                IYearnVaultV2(yvyCRVAddr),
                amountToWithdraw
            ) - 1 // swap little less because of yearn 1 wei conversion loss if withdrawing from strategy
        );

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(ale), borrowAmount / 2);

        ale.deleveragePosition(
            _convertCollatToDola(amountToWithdraw) - 1,
            address(market),
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // Some collateral has been withdrawn
        assertEq(
            IERC20(yvyCRVAddr).balanceOf(userEscrow),
            styCRVAmount - amountToWithdraw
        );
        assertEq(
            ISimpleERC20Escrow(userEscrow).balance(),
            styCRVAmount - amountToWithdraw
        );
        // User still has dola but has some debt repaid
        assertApproxEqAbs(DOLA.balanceOf(userPk), borrowAmount / 2, 2);
    }

    function test_depositAndLeveragePosition_buyDBR_with_yCRV(
        uint256 amount
    ) public {
        // Fill userPk with some yCRV
        deal(CRV, userPk, 15_000_000 ether);
        vm.startPrank(userPk);
        IERC20(CRV).approve(address(yCRV), 15_000_000 ether);
        IYCRV(yCRV).mint(15_000_000 ether);
        vm.stopPrank();

        // We are going to deposit and convert some yCRV and leverage the position
        vm.assume(amount < IERC20(yCRV).balanceOf(userPk));
        vm.assume(amount > 0.00001 ether);

        uint stYCRVDeposit = YearnVaultV2Helper.assetToCollateral(
            IYearnVaultV2(yvyCRVAddr),
            amount
        );
        uint maxBorrowAmount = _getMaxBorrowAmount(stYCRVDeposit);

        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        uint collateralToSwap = _convertDolaToCollat(maxBorrowAmount);

        uint underlyingAmountToSwap = YearnVaultV2Helper.collateralToAsset(
            IYearnVaultV2(yvyCRVAddr),
            collateralToSwap
        );

        IERC20(yCRV).transfer(
            address(exchangeProxy),
            underlyingAmountToSwap + 2
        ); // 2 rounding when calculating it

        vm.startPrank(userPk, userPk);
        // Approve for initial yCRV deposit
        IERC20(yCRV).approve(address(ale), amount);

        // Calculate the amount of DOLA needed to borrow to buy the DBR needed to cover for the borrowing period
        (uint256 dolaForDBR, uint256 dbrAmount) = ale
            .approximateDolaAndDbrNeeded(maxBorrowAmount, 10 days, 8);

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
            yCRV,
            maxBorrowAmount
        );

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
            dolaForDBR,
            (dbrAmount * 90) / 100,
            0
        );

        ale.depositAndLeveragePosition(
            amount,
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData,
            false
        );
        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        checkEq(stYCRVDeposit, collateralToSwap, userPk);
        assertApproxEqAbs(
            ISimpleERC20Escrow(escrow).balance(),
            stYCRVDeposit + collateralToSwap,
            1
        );
    }

    function test_transformToCollateralAndDeposit(uint256 yCRVAmount) public {
        // Fill userPk with max available deposit yCRV
        uint256 maxDeposit = IYearnVaultV2(yvyCRVAddr).availableDepositLimit(); // minting is 1:1
        deal(CRV, userPk, maxDeposit);
        vm.startPrank(userPk);
        IERC20(CRV).approve(address(yCRV), maxDeposit);
        IYCRV(yCRV).mint(maxDeposit);
        assertEq(IERC20(yCRV).balanceOf(userPk), maxDeposit);

        vm.assume(
            yCRVAmount < IYearnVaultV2(yvyCRVAddr).availableDepositLimit()
        );
        vm.assume(yCRVAmount > 0.00000001 ether);

        uint256 yCRVBalBefore = IERC20(yCRV).balanceOf(userPk);
        IERC20(yCRV).approve(address(helper), yCRVAmount);
        helper.transformToCollateralAndDeposit(yCRVAmount, "");

        assertEq(yCRVBalBefore - yCRVAmount, IERC20(yCRV).balanceOf(userPk));

        assertEq(
            IERC20(yvyCRVAddr).balanceOf(address(market.predictEscrow(userPk))),
            YearnVaultV2Helper.assetToCollateral(
                IYearnVaultV2(yvyCRVAddr),
                yCRVAmount
            )
        );
    }

    function test_withdrawAndTransformFromCollateral(
        uint256 yCRVAmount
    ) public {
        // Fill userPk with max available deposit yCRV
        uint256 maxDeposit = IYearnVaultV2(yvyCRVAddr).availableDepositLimit(); // minting is 1:1
        deal(CRV, userPk, maxDeposit);
        vm.startPrank(userPk);
        IERC20(CRV).approve(address(yCRV), maxDeposit);
        IYCRV(yCRV).mint(maxDeposit);
        assertEq(IERC20(yCRV).balanceOf(userPk), maxDeposit);

        vm.assume(
            yCRVAmount < IYearnVaultV2(yvyCRVAddr).availableDepositLimit()
        );
        vm.assume(yCRVAmount > 0.00000001 ether);

        uint256 yCRVBalBefore = IERC20(yCRV).balanceOf(userPk);
        IERC20(yCRV).approve(address(helper), yCRVAmount);
        helper.transformToCollateralAndDeposit(yCRVAmount, "");

        uint256 yCRVBalAfter = IERC20(yCRV).balanceOf(userPk);
        assertEq(yCRVBalBefore - yCRVAmount, yCRVBalAfter);

        uint256 amountToWithdraw = IERC20(yvyCRVAddr).balanceOf(
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

        YVYCRVHelper.Permit memory permit = YVYCRVHelper.Permit(
            block.timestamp,
            v,
            r,
            s
        );

        helper.withdrawAndTransformFromCollateral(amountToWithdraw, permit, "");

        assertApproxEqAbs(
            IERC20(yCRV).balanceOf(userPk) - yCRVBalAfter,
            YearnVaultV2Helper.collateralToAsset(
                IYearnVaultV2(yvyCRVAddr),
                amountToWithdraw
            ),
            1
        );
    }

    function test_fail_setMarket_NoMarket() public {
        address fakeMarket = address(0x69);

        vm.expectRevert(
            abi.encodeWithSelector(ALE.NoMarket.selector, fakeMarket)
        );
        ale.setMarket(fakeMarket, address(0), address(0), true);
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
            .target(address(helper.vault()))
            .sig(helper.vault().totalSupply.selector)
            .checked_write(uint256(0));

        uint256 assetAmount = 1 ether;
        assertEq(
            assetAmount,
            YearnVaultV2Helper.assetToCollateral(
                IYearnVaultV2(yvyCRVAddr),
                assetAmount
            )
        );
    }

    function test_fail_collateral_is_zero_leveragePosition() public {
        // We are going to deposit some CRV, then leverage the position
        uint styCRVAmount = 1 ether;

        gibDBR(userPk, styCRVAmount);

        uint maxBorrowAmount = _getMaxBorrowAmount(styCRVAmount);

        uint256 yCRVAmount = YearnVaultV2Helper.collateralToAsset(
            IYearnVaultV2(yvyCRVAddr),
            _convertDolaToCollat(maxBorrowAmount)
        );
        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        IERC20(yCRV).transfer(address(exchangeProxy), yCRVAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        IERC20(yvyCRVAddr).approve(address(market), styCRVAmount);
        market.deposit(styCRVAmount);

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
            yCRV,
            maxBorrowAmount
        );

        ALE.DBRHelper memory dbrData;

        // Mock call to return 0 buySellToken balance for the ALE
        vm.mockCall(
            yCRV,
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
            bytes(""),
            dbrData
        );
    }

    function _convertCollatToDola(uint amount) internal view returns (uint) {
        uint256 underlying = YearnVaultV2Helper.collateralToAsset(
            IYearnVaultV2(yvyCRVAddr),
            amount
        );
        return _convertUnderlyingToDola(underlying);
    }

    function _convertDolaToCollat(uint amount) internal view returns (uint) {
        uint256 underlying = _convertDolaToUnderlying(amount);
        return
            YearnVaultV2Helper.assetToCollateral(
                IYearnVaultV2(yvyCRVAddr),
                underlying
            );
    }

    function _convertDolaToUnderlying(
        uint amount
    ) internal view returns (uint) {
        return (amount * 1e18) / oracle.viewPrice(yCRV, 0);
    }

    function _convertUnderlyingToDola(
        uint amount
    ) internal view returns (uint) {
        return (amount * oracle.viewPrice(yCRV, 0)) / 1e18;
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
