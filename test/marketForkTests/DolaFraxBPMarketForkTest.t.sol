// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MarketBaseForkTest, IOracle, IDolaBorrowingRights, IERC20} from "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";
import {LPCurveYearnV2Escrow} from "src/escrows/LPCurveYearnV2Escrow.sol";
import {CurveLPPessimisticFeed} from "src/feeds/CurveLPPessimisticFeed.sol";
import {ChainlinkCurve2CoinsFeed} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import "src/util/YearnVaultV2Helper.sol";
import {console} from "forge-std/console.sol";

contract DolaFraxBPMarketForkTest is MarketBaseForkTest {
    LPCurveYearnV2Escrow escrow;
    CurveLPPessimisticFeed feedDolaBP;

    ChainlinkCurveFeed usdcFallback;
    ChainlinkCurve2CoinsFeed fraxFallback;
    ChainlinkBasePriceFeed mainUsdcFeed;
    ChainlinkBasePriceFeed mainFraxFeed;
    ChainlinkBasePriceFeed baseCrvUsdToUsd;
    ChainlinkBasePriceFeed baseEthToUsd;

    ICurvePool public constant dolaFraxBP =
        ICurvePool(0xE57180685E3348589E9521aa53Af0BCD497E884d);

    IChainlinkFeed public constant fraxToUsd =
        IChainlinkFeed(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);

    uint256 public fraxHeartbeat = 1 hours;

    IChainlinkFeed public constant usdcToUsd =
        IChainlinkFeed(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6);

    uint256 public usdcHeartbeat = 24 hours;

    // For USDC fallabck
    ICurvePool public constant tricryptoETH =
        ICurvePool(0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B);

    IChainlinkFeed public constant ethToUsd =
        IChainlinkFeed(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    uint256 public ethHeartbeat = 1 hours;
    uint256 public constant ethK = 1;

    // For Frax fallback
    ICurvePool public constant crvUSDFrax =
        ICurvePool(0x0CD6f267b2086bea681E922E19D40512511BE538);

    IChainlinkFeed public constant crvUSDToUsd =
        IChainlinkFeed(0xEEf0C605546958c1f899b6fB336C20671f9cD49F);

    uint256 fraxIndex = 0;

    uint256 public crvUSDHeartbeat = 24 hours;

    // Escrow implementation
    IERC20 cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address rewardPool = address(0x0404d05F3992347d2f0dC3a97bdd147D77C85c1c);
    address booster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public yearn = address(0xe5F625e8f4D2A038AE9583Da254945285E5a77a4);
    address yearnHolder = address(0x621BcFaA87bA0B7c57ca49e1BB1a8b917C34Ed2F);
    LPCurveYearnV2Escrow userEscrow;
    uint256 pid = 115;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20020781);

        escrow = new LPCurveYearnV2Escrow(
            address(rewardPool),
            address(booster),
            address(yearn),
            address(cvx),
            address(crv),
            pid
        );

        feedDolaBP = _deployDolaFraxBPFeed();

        Market market = new Market(
            gov,
            lender,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbr)),
            IERC20(address(dolaFraxBP)),
            IOracle(address(oracle)),
            5000,
            5000,
            1000,
            true
        );

        _advancedInit(address(market), address(feedDolaBP), true);

        userEscrow = LPCurveYearnV2Escrow(address(market.predictEscrow(user)));
    }

    function test_escrow_immutables() public {
        testDeposit();
        assertEq(
            address(userEscrow.rewardPool()),
            address(rewardPool),
            "Reward pool not set"
        );
        assertEq(
            address(userEscrow.booster()),
            address(booster),
            "Booster not set"
        );
        assertEq(address(userEscrow.yearn()), address(yearn), "Yearn not set");
        assertEq(address(userEscrow.cvx()), address(cvx), "CVX not set");
        assertEq(address(userEscrow.crv()), address(crv), "CRV not set");
    }

    function test_depositToConvex() public {
        testDeposit();
        userEscrow.depositToConvex();
    }

    function test_withdrawFromConvex() public {
        testDeposit();
        userEscrow.depositToConvex();
        userEscrow.withdrawFromConvex();
    }

    function test_depositToYearn() public {
        testDeposit();
        userEscrow.depositToYearn();
    }

    function test_withdrawFromYearn() public {
        testDeposit();
        userEscrow.depositToYearn();
        userEscrow.withdrawFromYearn();
    }

    function test_withdrawMax(uint256 amount) public {
        // Test fuzz amount for yearn deposit while also having LP deposited and then max withdraw
        vm.assume(amount > 0);
        vm.assume(amount <= IERC20(yearn).balanceOf(address(yearnHolder)));
        testDeposit();

        vm.stopPrank();
        // Transfer yearn to userEscrow while been deposited into convex
        vm.prank(yearnHolder);
        IERC20(yearn).transfer(address(userEscrow), amount);

        assertGt(IERC20(yearn).balanceOf(address(userEscrow)), 0);

        vm.prank(user);
        market.withdrawMax();
        assertEq(
            IERC20(yearn).balanceOf(address(userEscrow)),
            0,
            "Yearn balance not 0"
        );
        assertEq(userEscrow.balance(), 0, "Escrow balance not 0");
        assertEq(
            IERC20(address(dolaFraxBP)).balanceOf(address(userEscrow)),
            0,
            "DolaFraxBP balance not 0"
        );
        assertEq(IERC20(yearn).balanceOf(address(userEscrow)), 0);
    }

    function test_fail_one_wei_yearn_deposit() public {
        uint256 amount = 1;
        testDeposit();

        market.withdraw(testAmount - amount);

        vm.expectRevert();
        userEscrow.depositToYearn();
    }

    function test_succeed_two_wei_yearn_deposit() public {
        uint256 amount = 2;
        testDeposit();

        market.withdraw(testAmount - amount);

        userEscrow.depositToYearn();
    }

    function test_edge_case_when_missingAmount_one_wei_lower_maxWithdraw(
        uint256 amount
    ) public {
        vm.assume(amount > 1);
        vm.assume(amount <= IERC20(yearn).balanceOf(address(yearnHolder)));

        // Test edge case where amount is 1 wei lower than maxWithdraw from Yearn
        testDeposit();
        vm.stopPrank();
        // Transfer yearn to userEscrow
        vm.prank(yearnHolder);
        IERC20(yearn).transfer(address(userEscrow), amount);
        uint256 maxWithdraw = YearnVaultV2Helper.collateralToAsset(
            IYearnVaultV2(yearn),
            amount
        );
        assertEq(testAmount + maxWithdraw, userEscrow.balance());
        assertGt(IERC20(yearn).balanceOf(address(userEscrow)), 0);

        vm.prank(user);
        market.withdraw(testAmount + maxWithdraw - 1);
        assertEq(
            IERC20(yearn).balanceOf(address(userEscrow)),
            0,
            "Yearn balance not 0"
        );
        assertApproxEqAbs(
            userEscrow.balance(),
            0,
            1,
            "Escrow balance not correct"
        );
        assertApproxEqAbs(
            IERC20(address(dolaFraxBP)).balanceOf(address(userEscrow)),
            0,
            1,
            "DolaFraxBP balance not correct"
        );
        assertEq(IERC20(yearn).balanceOf(address(userEscrow)), 0);
    }

    function test_withdraw_amount_fuzz(uint256 amount) public {
        // Test fuzz withdraw amount up to user balance with deposited LP + yearn balance
        uint256 yearnAmount = YearnVaultV2Helper.collateralToAsset(
            IYearnVaultV2(yearn),
            IERC20(yearn).balanceOf(address(yearnHolder))
        );
        uint minAssetAmount = 1; // cannot withdraw only 1 wei from yearn
        assertEq(
            0,
            YearnVaultV2Helper.assetToCollateral(
                IYearnVaultV2(yearn),
                minAssetAmount
            )
        );
        uint256 minWithdraw = testAmount + minAssetAmount; // cannot withdraw only 1 wei from yearn
        vm.assume(amount > minWithdraw);
        uint maxWithdraw = 85161774949860625361; // testAmount + yearnAmount;
        vm.assume(amount <= maxWithdraw);
        testDeposit();

        vm.stopPrank();
        // Transfer yearn to userEscrow while having LP already deposited
        uint256 yearnBalance = IERC20(yearn).balanceOf(address(yearnHolder));
        vm.prank(yearnHolder);
        IERC20(yearn).transfer(address(userEscrow), yearnBalance);

        assertEq(
            userEscrow.balance(),
            testAmount +
                YearnVaultV2Helper.collateralToAsset(
                    IYearnVaultV2(yearn),
                    yearnBalance
                )
        );

        uint escrowBalBefore = userEscrow.balance();

        vm.startPrank(user);
        market.withdraw(amount);
        assertEq(
            IERC20(address(dolaFraxBP)).balanceOf(address(user)),
            amount,
            "DolaFraxBP balance not correct"
        );
        assertApproxEqAbs(
            userEscrow.balance(),
            escrowBalBefore - amount,
            1,
            "Escrow Balance not correct"
        );
    }

    function test_withdraw_amount_expected_from_yearn(uint random) public {
        // Test fuzz withdraw amount expected from yearn
        vm.assume(random > 1);
        vm.assume(random < 100000);
        // Test withdraw amount if it's estimated from yearn
        uint256 yearnAmount = YearnVaultV2Helper.collateralToAsset(
            IYearnVaultV2(yearn),
            IERC20(yearn).balanceOf(address(yearnHolder))
        );

        testDeposit();
        vm.stopPrank();

        // Transfer yearn to userEscrow while having LP already deposited
        uint256 yearnBalance = IERC20(yearn).balanceOf(address(yearnHolder));
        vm.prank(yearnHolder);
        IERC20(yearn).transfer(address(userEscrow), yearnBalance);

        assertEq(
            userEscrow.balance(),
            testAmount +
                YearnVaultV2Helper.collateralToAsset(
                    IYearnVaultV2(yearn),
                    yearnBalance
                )
        );
        // Estimate withdraw amount from yearn
        uint withdrawYearnAmount = YearnVaultV2Helper.collateralToAsset(
            IYearnVaultV2(yearn),
            yearnAmount / random // random number
        );

        vm.startPrank(user);
        market.withdraw(testAmount + withdrawYearnAmount);
        // Withdraw exact amount expected from yearn
        assertEq(
            IERC20(address(dolaFraxBP)).balanceOf(address(user)),
            testAmount + withdrawYearnAmount,
            "DolaFraxBP balance not correct"
        );
        assertApproxEqAbs(
            userEscrow.balance(),
            YearnVaultV2Helper.collateralToAsset(
                IYearnVaultV2(yearn),
                yearnBalance
            ) - withdrawYearnAmount,
            1,
            "Escrow Balance not correct"
        );
    }

    function _deployDolaFraxBPFeed()
        internal
        returns (CurveLPPessimisticFeed feed)
    {
        // For FRAX fallback
        baseCrvUsdToUsd = new ChainlinkBasePriceFeed(
            gov,
            address(crvUSDToUsd),
            address(0),
            crvUSDHeartbeat,
            8
        );
        fraxFallback = new ChainlinkCurve2CoinsFeed(
            address(baseCrvUsdToUsd),
            address(crvUSDFrax),
            8,
            fraxIndex
        );

        // For USDC fallback
        baseEthToUsd = new ChainlinkBasePriceFeed(
            gov,
            address(ethToUsd),
            address(0),
            ethHeartbeat,
            8
        );
        usdcFallback = new ChainlinkCurveFeed(
            address(baseEthToUsd),
            address(tricryptoETH),
            ethK,
            8,
            0
        );

        // Main feeds
        mainFraxFeed = new ChainlinkBasePriceFeed(
            gov,
            address(fraxToUsd),
            address(fraxFallback),
            fraxHeartbeat,
            8
        );

        mainUsdcFeed = new ChainlinkBasePriceFeed(
            gov,
            address(usdcToUsd),
            address(usdcFallback),
            usdcHeartbeat,
            8
        );
        feed = new CurveLPPessimisticFeed(
            address(dolaFraxBP),
            address(mainFraxFeed),
            address(mainUsdcFeed)
        );
    }
}
