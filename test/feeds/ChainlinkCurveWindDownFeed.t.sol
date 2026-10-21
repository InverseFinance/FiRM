// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ChainlinkCurveWindDownFeed} from "src/feeds/ChainlinkCurveWindDownFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import {CurveLPPessimisticFeed} from "src/feeds/CurveLPPessimisticFeed.sol";
import {CurveLPYearnV2Feed} from "src/feeds/CurveLPYearnV2Feed.sol";
import {BorrowController} from "src/BorrowController.sol";
import {Oracle, IChainlinkFeed as OracleFeed} from "src/Oracle.sol";

contract WindDownMockBase {
    uint8 public decimals = 18;
    int256 public price = 1e18;
    uint256 public updatedAt = block.timestamp;
    bool public fail;

    function set(int256 p, uint256 t, bool f) external {
        price = p;
        updatedAt = t;
        fail = f;
    }

    function setDecimals(uint8 d) external {
        decimals = d;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        require(!fail, "base failure");
        return (42, price, updatedAt, updatedAt, 42);
    }
}

contract WindDownMockToken {
    string public symbol;

    constructor(string memory s) {
        symbol = s;
    }
}

contract WindDownMockPool {
    address[3] public coins;
    uint256[2] public prices;
    bool public fail;

    constructor(address token) {
        coins = [token, address(1), address(2)];
        prices = [uint256(1e18), uint256(1e18)];
    }

    function set(uint256 k, uint256 p, bool f) external {
        prices[k] = p;
        fail = f;
    }

    function price_oracle(uint256 k) external view returns (uint256) {
        require(!fail, "pool failure");
        return prices[k];
    }

    function get_virtual_price() external pure returns (uint256) {
        return 1.1e18;
    }

    function symbol() external pure returns (string memory) {
        return "TEST-LP";
    }
}

contract WindDownMockYearn {
    function symbol() external pure returns (string memory) {
        return "yvTEST-LP";
    }

    function totalSupply() external pure returns (uint256) {
        return 1e18;
    }

    function totalAssets() external pure returns (uint256) {
        return 1.2e18;
    }

    function lastReport() external view returns (uint256) {
        return block.timestamp;
    }

    function lockedProfitDegradation() external pure returns (uint256) {
        return 0;
    }

    function lockedProfit() external pure returns (uint256) {
        return 0;
    }
}

contract WindDownMockMarket {
    address public oracle;
    address public collateral;

    constructor(address o, address c) {
        oracle = o;
        collateral = c;
    }
}

contract WindDownMockDBR {
    function lastUpdated(address) external pure returns (uint256) {
        return 0;
    }

    function debts(address) external pure returns (uint256) {
        return 0;
    }
}

contract WindDownMockDola {
    mapping(address => uint256) public balanceOf;
    uint256 public transferCalls;
    bool public observedWindDownStarted;
    bool public fail;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function setFail(bool f) external {
        fail = f;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(!fail, "DOLA failure");
        observedWindDownStarted = (ChainlinkCurveWindDownFeed(msg.sender).windDownStartPrice() != 0);
        transferCalls++;
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract ChainlinkCurveWindDownFeedTest is Test {
    WindDownMockBase base;
    WindDownMockPool pool;
    ChainlinkCurveWindDownFeed feed;
    WindDownMockDola dola;
    uint32 constant DURATION = 1 days;
    address constant RWG = address(0xBEEF);
    uint256 constant BORROW_STALENESS_THRESHOLD = 1 days + 1 minutes;

    function setUp() public {
        vm.warp(10 days);
        base = new WindDownMockBase();
        pool = new WindDownMockPool(address(new WindDownMockToken("TOKEN")));
        feed = deploy(0, DURATION);
        WindDownMockDola mockDola = new WindDownMockDola();
        vm.etch(address(feed.DOLA()), address(mockDola).code);
        dola = WindDownMockDola(address(feed.DOLA()));
    }

    function deploy(uint256 k, uint32 duration) internal returns (ChainlinkCurveWindDownFeed) {
        return new ChainlinkCurveWindDownFeed(address(base), address(pool), k, duration, RWG);
    }

    function activate() internal {
        pool.set(0, 1.9e18, false);
        feed.startWindDown();
    }

    function testRewardPaidImmediatelyToActivationCaller() public {
        address caller = address(123);
        dola.mint(address(feed), 10e18);
        pool.set(0, 1.9e18, false);
        assertTrue(feed.canStartWindDown());
        assertEq(dola.balanceOf(caller), 0); // readiness reads do not pay
        uint256 price = uint256(feed.latestAnswer());
        vm.recordLogs();
        vm.prank(caller);
        feed.startWindDown();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(feed));
        assertEq(logs[0].topics[0], keccak256("WindDownStarted(address,uint256,uint256,uint256,uint256,uint256)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(caller))));
        assertEq(logs[0].data, abi.encode(block.timestamp, price, uint256(1.9e18), DURATION, uint256(10e18)));
        assertEq(dola.balanceOf(caller), 10e18);
        assertEq(dola.balanceOf(address(feed)), 0);
        assertTrue(dola.observedWindDownStarted()); // state finalized before the transfer
        assertEq(feed.windDownStartedAt(), block.timestamp);
        assertEq(feed.latestAnswer(), int256(price)); // no time needs to elapse for payout
    }

    function testZeroBalanceStillTransfersAndActivates() public {
        assertEq(dola.balanceOf(address(feed)), 0);
        activate();
        assertGt(feed.windDownStartPrice(), 0);
        assertEq(dola.transferCalls(), 1);
        assertEq(dola.balanceOf(address(this)), 0);
    }

    function testCannotClaimAgainEvenIfFundedAfterActivation() public {
        dola.mint(address(feed), 10e18);
        activate();
        dola.mint(address(feed), 5e18);
        vm.expectRevert(ChainlinkCurveWindDownFeed.WindDownAlreadyStarted.selector);
        feed.startWindDown();
        assertEq(dola.balanceOf(address(this)), 10e18);
        assertEq(dola.balanceOf(address(feed)), 5e18);
        assertEq(dola.transferCalls(), 1);
    }

    function testIneligibleCallerCannotCollectReward() public {
        dola.mint(address(feed), 10e18);
        vm.expectRevert(ChainlinkCurveWindDownFeed.TriggerNotReached.selector);
        feed.startWindDown();
        assertEq(dola.balanceOf(address(feed)), 10e18);
        assertEq(dola.transferCalls(), 0);
        assertEq(feed.windDownStartPrice(), 0);
    }

    function testRevertingTransferRollsBackActivation() public {
        dola.mint(address(feed), 10e18);
        dola.setFail(true);
        pool.set(0, 1.9e18, false);
        vm.expectRevert(bytes("DOLA failure"));
        feed.startWindDown();
        assertEq(feed.windDownStartPrice(), 0);
        assertEq(feed.windDownStartedAt(), 0);
        assertEq(dola.balanceOf(address(feed)), 10e18);
    }

    function testGenericMetadataAndFixedThreshold() public view {
        assertEq(feed.description(), "TOKEN / USD");
        assertEq(feed.TARGET_INDEX(), 0);
        assertEq(feed.decimals(), 18);
        assertEq(feed.WIND_DOWN_TRIGGER_EMA(), 1.9e18);
        assertEq(feed.TERMINAL_PRICE(), 100);
        assertEq(feed.RWG(), RWG);
    }

    function testFuzzLiveModeMatchesExistingFeedExceptThresholdTimestamp(uint256 basePrice, uint64 ema) public {
        basePrice = bound(basePrice, 1e18, uint256(type(int256).max) / 1e18);
        ema = uint64(bound(ema, 1, 2e18));
        base.set(int256(basePrice), block.timestamp, false);
        pool.set(0, ema, false);
        ChainlinkCurveFeed existing = new ChainlinkCurveFeed(address(base), address(pool), 0, 0);
        (bool ok, bytes memory actual) = address(feed).staticcall(abi.encodeWithSignature("latestRoundData()"));
        (bool oldOk, bytes memory expected) = address(existing).staticcall(abi.encodeWithSignature("latestRoundData()"));
        if (ema >= 1.9e18) {
            expected = abi.encode(uint80(42), existing.latestAnswer(), block.timestamp, uint256(0), uint80(42));
        }
        assertTrue(ok && oldOk);
        assertEq(actual, expected);
        assertEq(feed.latestAnswer(), existing.latestAnswer());
    }

    function testNonzeroOracleIndexAndDifferentAsset() public {
        pool = new WindDownMockPool(address(new WindDownMockToken("OTHER")));
        ChainlinkCurveWindDownFeed other = deploy(1, DURATION);
        pool.set(0, 2e18, false);
        pool.set(1, 1.5e18, false);
        assertEq(other.description(), "OTHER / USD");
        assertEq(other.REFERENCE_ORACLE_INDEX(), 1);
        assertEq(other.latestAnswer(), int256(uint256(1e36) / 1.5e18));
        assertFalse(other.canStartWindDown());
        (,,, uint256 updatedAt,) = other.latestRoundData();
        assertEq(updatedAt, block.timestamp); // unused oracle index 0 is already above threshold
        pool.set(1, 1.9e18, false);
        (,,, updatedAt,) = other.latestRoundData();
        assertEq(updatedAt, 0);
        assertTrue(other.canStartWindDown());
        other.startWindDown();
        assertGt(other.windDownStartPrice(), 0);
    }

    function testThresholdBoundaryAndPermissionlessActivation() public {
        pool.set(0, 1.9e18 - 1, false);
        assertFalse(feed.canStartWindDown());
        vm.expectRevert(ChainlinkCurveWindDownFeed.TriggerNotReached.selector);
        feed.startWindDown();
        pool.set(0, 1.9e18, false);
        assertTrue(feed.canStartWindDown());
        uint256 preview = uint256(feed.latestAnswer());
        assertEq(feed.windDownStartPrice(), 0); // reading cannot activate
        vm.prank(address(123));
        feed.startWindDown();
        assertEq(feed.windDownStartPrice(), preview);
        assertEq(feed.windDownStartedAt(), block.timestamp);
    }

    function testLiveThresholdTimestampAndRecoveryWithoutActivation() public {
        uint256 upstreamTime = block.timestamp - 60;
        base.set(1e18, upstreamTime, false);
        dola.mint(address(feed), 10e18);
        uint256[4] memory emas = [uint256(1.9e18 - 1), uint256(1.9e18), uint256(2e18), uint256(1.9e18 - 1)];
        for (uint256 i; i < emas.length; i++) {
            pool.set(0, emas[i], false);
            (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
                feed.latestRoundData();
            assertEq(price, int256(uint256(1e36) / emas[i]));
            assertEq(feed.latestAnswer(), price);
            assertEq(roundId, 42);
            assertEq(startedAt, upstreamTime);
            assertEq(answeredInRound, 42);
            assertEq(updatedAt, i == 1 || i == 2 ? 0 : upstreamTime);
            assertEq(feed.windDownStartPrice(), 0);
            assertEq(feed.windDownStartedAt(), 0);
            assertEq(dola.transferCalls(), 0);
            assertEq(dola.balanceOf(address(feed)), 10e18);
        }
        base.set(1e18, 0, false);
        (,,, uint256 recoveredTimestamp,) = feed.latestRoundData();
        assertEq(recoveredTimestamp, 0); // falling below the trigger does not make stale upstream data fresh
    }

    function testStopAboveThresholdKeepsBorrowingBlockedUntilRecovery() public {
        Oracle oracle = new Oracle(address(this));
        address collateral = address(0xCA11);
        oracle.setFeed(collateral, OracleFeed(address(feed)), 18);
        WindDownMockMarket market = new WindDownMockMarket(address(oracle), collateral);
        BorrowController controller = new BorrowController(address(this), address(new WindDownMockDBR()));
        controller.setDailyLimit(address(market), 100e18);
        controller.setStalenessThreshold(address(market), BORROW_STALENESS_THRESHOLD);
        controller.allow(address(this));
        activate();
        vm.warp(block.timestamp + DURATION / 2);
        base.set(1e18, block.timestamp, false);
        vm.prank(RWG);
        feed.stopWindDown();
        assertEq(feed.windDownStartPrice(), 0);
        assertEq(feed.latestAnswer(), int256(uint256(1e36) / 1.9e18));
        (,,, uint256 updatedAt,) = feed.latestRoundData();
        assertEq(updatedAt, 0);
        assertTrue(controller.isPriceStale(address(market)));
        vm.prank(address(market));
        assertFalse(controller.borrowAllowed(address(this), address(456), 1e18));
        pool.set(0, 1.9e18 - 1, false);
        (,,, updatedAt,) = feed.latestRoundData();
        assertEq(updatedAt, block.timestamp);
        assertFalse(controller.isPriceStale(address(market)));
        vm.prank(address(market));
        assertTrue(controller.borrowAllowed(address(this), address(456), 1e18));
    }

    function testCanStartRechecksAtExecution() public {
        pool.set(0, 1.9e18, false);
        assertTrue(feed.canStartWindDown());
        pool.set(0, 1.8e18, false);
        vm.expectRevert(ChainlinkCurveWindDownFeed.TriggerNotReached.selector);
        feed.startWindDown();
        assertEq(feed.windDownStartPrice(), 0);
    }

    function testActivationIgnoresBaseFeedTimestamp() public {
        pool.set(0, 1.9e18, false);
        uint256[3] memory timestamps = [uint256(0), uint256(1), block.timestamp + 1];
        for (uint256 i; i < timestamps.length; i++) {
            feed = deploy(0, DURATION);
            base.set(1e18, timestamps[i], false);
            assertTrue(feed.canStartWindDown());
            uint256 price = uint256(feed.latestAnswer());
            feed.startWindDown();
            assertGt(feed.windDownStartPrice(), 0);
            assertEq(feed.windDownStartPrice(), price);
            (,, uint256 startedAt, uint256 updatedAt,) = feed.latestRoundData();
            assertEq(startedAt, 0);
            assertEq(updatedAt, 0);
        }
    }

    function testEligibilityDoesNotReadBaseFeedAndPoolFailuresRevert() public {
        pool.set(0, 1.9e18, false);
        base.set(1e18, block.timestamp, true);
        assertTrue(feed.canStartWindDown());
        vm.expectRevert(bytes("base failure"));
        feed.startWindDown();
        assertEq(feed.windDownStartPrice(), 0);
        base.set(1e18, block.timestamp, false);
        pool.set(0, 0, false);
        assertFalse(feed.canStartWindDown());
        pool.set(0, 1.9e18, true);
        vm.expectRevert(bytes("pool failure"));
        feed.canStartWindDown();
        vm.expectRevert(bytes("pool failure"));
        feed.startWindDown();
        assertEq(feed.windDownStartPrice(), 0);
    }

    function testActivationHasNoAdditionalEmaCeiling() public {
        pool.set(0, 3e18, false);
        assertTrue(feed.canStartWindDown());
        assertEq(feed.latestAnswer(), int256(uint256(1e36) / 3e18));
        feed.startWindDown();
        assertEq(feed.windDownStartPrice(), uint256(1e36) / 3e18);
        assertFalse(feed.canStartWindDown());
    }

    function testMinimumStartingPriceLatchesAtTimestampZero() public {
        vm.warp(0);
        base.set(190, 0, false);
        activate();
        assertEq(feed.windDownStartedAt(), 0);
        assertEq(feed.windDownStartPrice(), 100);
        assertEq(feed.latestAnswer(), 100);
        assertFalse(feed.canStartWindDown());
        vm.expectRevert(ChainlinkCurveWindDownFeed.WindDownAlreadyStarted.selector);
        feed.startWindDown();
        vm.warp(DURATION);
        assertEq(feed.latestAnswer(), 100);
    }

    function testPositiveStartingPricesBelowTerminalCannotActivateOrClaimReward() public {
        pool.set(0, 1.9e18, false);
        dola.mint(address(feed), 10e18);
        int256[3] memory basePrices = [int256(2), int256(188), int256(189)];
        int256[3] memory livePrices = [int256(1), int256(98), int256(99)];
        for (uint256 i; i < basePrices.length; i++) {
            base.set(basePrices[i], block.timestamp, false);
            (, int256 price,, uint256 updatedAt,) = feed.latestRoundData();
            assertEq(price, livePrices[i]); // live pricing is not clamped or rejected
            assertEq(updatedAt, 0); // threshold blocks borrowing even when activation cannot succeed
            assertTrue(feed.canStartWindDown());
            vm.expectRevert(ChainlinkCurveWindDownFeed.InvalidBasePrice.selector);
            feed.startWindDown();
            assertEq(feed.windDownStartPrice(), 0);
            assertEq(feed.windDownStartedAt(), 0);
            assertEq(dola.balanceOf(address(feed)), 10e18);
            assertEq(dola.balanceOf(address(this)), 0);
            assertEq(dola.transferCalls(), 0);
        }
        base.set(190, block.timestamp, false); // inverted price is exactly 100
        feed.startWindDown();
        assertEq(feed.latestAnswer(), 100);
        assertEq(dola.balanceOf(address(this)), 10e18);
        vm.warp(block.timestamp + DURATION / 2);
        assertEq(feed.latestAnswer(), 100);
        vm.warp(block.timestamp + DURATION);
        assertEq(feed.latestAnswer(), 100);
    }

    function testTerminalPriceLPRoundingBoundary() public {
        WindDownMockBase otherCoin = new WindDownMockBase();
        CurveLPPessimisticFeed lp = new CurveLPPessimisticFeed(address(pool), address(feed), address(otherCoin), false);
        Oracle oracle = new Oracle(address(this));
        address collateral = address(0xCA11);
        oracle.setFeed(collateral, OracleFeed(address(lp)), 18);
        activate();
        vm.warp(block.timestamp + DURATION);
        uint256[4] memory virtualPrices = [uint256(0.99e18), uint256(0.5e18), uint256(0.01e18), uint256(0.01e18 - 1)];
        int256[4] memory expected = [int256(99), int256(50), int256(1), int256(0)];
        for (uint256 i; i < virtualPrices.length; i++) {
            vm.mockCall(address(pool), abi.encodeWithSignature("get_virtual_price()"), abi.encode(virtualPrices[i]));
            (, int256 price,, uint256 updatedAt,) = lp.latestRoundData();
            assertEq(price, expected[i]);
            assertEq(updatedAt, 0);
            if (price > 0) {
                assertEq(oracle.getPrice(collateral, 8500), uint256(price));
            } else {
                vm.expectRevert(bytes("Invalid feed price"));
                oracle.getPrice(collateral, 8500);
            }
        }
    }

    function testTerminalPriceCombinedLPAndYearnRoundingBoundary() public {
        WindDownMockBase otherCoin = new WindDownMockBase();
        CurveLPPessimisticFeed lp = new CurveLPPessimisticFeed(address(pool), address(feed), address(otherCoin), false);
        WindDownMockYearn yearn = new WindDownMockYearn();
        CurveLPYearnV2Feed yv = new CurveLPYearnV2Feed(address(yearn), address(lp));
        Oracle oracle = new Oracle(address(this));
        address collateral = address(0xCA11);
        oracle.setFeed(collateral, OracleFeed(address(yv)), 18);
        activate();
        vm.warp(block.timestamp + DURATION);
        // A second scale-down must be checked separately, after the LP's integer rounding.
        vm.mockCall(address(yearn), abi.encodeWithSignature("totalAssets()"), abi.encode(uint256(0.5e18)));
        vm.mockCall(address(pool), abi.encodeWithSignature("get_virtual_price()"), abi.encode(uint256(0.02e18)));
        (, int256 price,, uint256 updatedAt,) = yv.latestRoundData();
        assertEq(price, 1); // 100 -> 2 LP units -> 1 vault unit
        assertEq(updatedAt, 0);
        assertEq(oracle.getPrice(collateral, 8500), 1);
        vm.mockCall(address(pool), abi.encodeWithSignature("get_virtual_price()"), abi.encode(uint256(0.02e18 - 1)));
        (, price,, updatedAt,) = yv.latestRoundData();
        assertEq(lp.latestAnswer(), 1);
        assertEq(price, 0); // 100 -> 1 LP unit -> 0 vault units: buffer is not universal
        assertEq(updatedAt, 0);
        vm.expectRevert(bytes("Invalid feed price"));
        oracle.getPrice(collateral, 8500);
    }

    function testInvalidConstructor() public {
        vm.expectRevert(ChainlinkCurveWindDownFeed.InvalidConfiguration.selector);
        deploy(0, 0);
        base.setDecimals(8);
        vm.expectRevert(ChainlinkCurveWindDownFeed.InvalidConfiguration.selector);
        deploy(0, DURATION);
        base.setDecimals(18);
        vm.expectRevert();
        deploy(2, DURATION);
        vm.expectRevert();
        new ChainlinkCurveWindDownFeed(address(0), address(pool), 0, DURATION, RWG);
        vm.expectRevert();
        new ChainlinkCurveWindDownFeed(address(base), address(0), 0, DURATION, RWG);
        vm.expectRevert(ChainlinkCurveWindDownFeed.InvalidConfiguration.selector);
        new ChainlinkCurveWindDownFeed(address(base), address(pool), 0, DURATION, address(0));
    }

    function testInvalidLivePricesReturnZeroAndCannotActivateOrClaimReward() public {
        pool.set(0, 1.9e18, false);
        dola.mint(address(feed), 10e18);
        int256[4] memory invalidPrices = [int256(-1e18), int256(-1), int256(0), int256(1)];
        for (uint256 i; i < invalidPrices.length; i++) {
            base.set(invalidPrices[i], block.timestamp, false);
            assertTrue(feed.canStartWindDown()); // eligibility only checks the EMA
            (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
                feed.latestRoundData();
            assertEq(roundId, 0);
            assertEq(price, 0);
            assertEq(startedAt, 0);
            assertEq(updatedAt, 0);
            assertEq(answeredInRound, 0);
            assertEq(feed.latestAnswer(), 0);
            for (uint256 attempt; attempt < 2; attempt++) {
                vm.expectRevert(ChainlinkCurveWindDownFeed.InvalidBasePrice.selector);
                feed.startWindDown();
                assertEq(feed.windDownStartPrice(), 0);
                assertEq(feed.windDownStartedAt(), 0);
                assertEq(dola.balanceOf(address(feed)), 10e18);
                assertEq(dola.balanceOf(address(this)), 0);
                assertEq(dola.transferCalls(), 0);
            }
        }
        base.set(1e18, block.timestamp, false);
        feed.startWindDown();
        assertGt(feed.windDownStartPrice(), 0);
        assertEq(dola.balanceOf(address(this)), 10e18);
        assertEq(dola.transferCalls(), 1);
    }

    function testInvalidPricePropagatesThroughLPAndYearnAndOracleRejectsIt() public {
        WindDownMockBase otherCoin = new WindDownMockBase();
        CurveLPPessimisticFeed lp = new CurveLPPessimisticFeed(address(pool), address(feed), address(otherCoin), false);
        CurveLPYearnV2Feed yv = new CurveLPYearnV2Feed(address(new WindDownMockYearn()), address(lp));
        Oracle oracle = new Oracle(address(this));
        address directCollateral = address(0xCA11);
        address vaultCollateral = address(0xCA12);
        oracle.setFeed(directCollateral, OracleFeed(address(feed)), 18);
        oracle.setFeed(vaultCollateral, OracleFeed(address(yv)), 18);
        pool.set(0, 1.9e18, false);
        int256[3] memory invalidPrices = [int256(-1e18), int256(0), int256(1)];
        for (uint256 i; i < invalidPrices.length; i++) {
            base.set(invalidPrices[i], block.timestamp, false);
            (, int256 lpPrice,, uint256 lpTimestamp,) = lp.latestRoundData();
            (, int256 yvPrice,, uint256 yvTimestamp,) = yv.latestRoundData();
            assertEq(lpPrice, 0);
            assertEq(lpTimestamp, 0);
            assertEq(yvPrice, 0);
            assertEq(yvTimestamp, 0);
            vm.expectRevert(bytes("Invalid feed price"));
            oracle.getPrice(directCollateral, 8500);
            vm.expectRevert(bytes("Invalid feed price"));
            oracle.getPrice(vaultCollateral, 8500);
            vm.expectRevert(bytes("Invalid feed price"));
            oracle.viewPrice(vaultCollateral, 8500);
            assertEq(oracle.dailyLows(directCollateral, block.timestamp / 1 days), 0);
            assertEq(oracle.dailyLows(vaultCollateral, block.timestamp / 1 days), 0);
        }
        base.set(1e18, block.timestamp, false);
        assertEq(oracle.getFeedPrice(directCollateral), uint256(feed.latestAnswer()));
        assertGt(oracle.getPrice(vaultCollateral, 8500), 0);
        assertEq(feed.windDownStartPrice(), 0);
    }

    function testArithmeticFailuresStillRevert() public {
        pool.set(0, 1.9e18, false);
        int256[2] memory overflowingPrices = [type(int256).min, type(int256).max / 1e18 + 1];
        for (uint256 i; i < overflowingPrices.length; i++) {
            base.set(overflowingPrices[i], block.timestamp, false);
            vm.expectRevert();
            feed.latestRoundData();
            vm.expectRevert();
            feed.startWindDown();
            assertEq(feed.windDownStartPrice(), 0);
        }
        base.set(1e18, block.timestamp, false);
        pool.set(0, 0, false);
        vm.expectRevert(); // division by zero is checked by Solidity
        feed.latestRoundData();
    }

    function testRecoveryAndOutagesDoNotAutomaticallyStopDecay() public {
        activate();
        assertFalse(feed.canStartWindDown());
        vm.expectRevert(ChainlinkCurveWindDownFeed.WindDownAlreadyStarted.selector);
        feed.startWindDown();
        uint256 startingPrice = feed.windDownStartPrice();
        pool.set(0, 1e18, false);
        assertEq(feed.latestAnswer(), int256(startingPrice));
        base.set(0, 0, true);
        pool.set(0, 0, true);
        assertFalse(feed.canStartWindDown()); // the active latch skips the failed pool call
        vm.warp(block.timestamp + DURATION / 2);
        assertEq(feed.latestAnswer(), int256(100 + (startingPrice - 100) / 2));
        (uint80 roundId,, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = feed.latestRoundData();
        assertEq(roundId, 0);
        assertEq(answeredInRound, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
    }

    function testOnlyRWGCanStopWindDown() public {
        vm.expectRevert(ChainlinkCurveWindDownFeed.OnlyRWG.selector);
        feed.stopWindDown();
        activate();
        uint256 price = feed.windDownStartPrice();
        uint256 startedAt = feed.windDownStartedAt();
        vm.expectRevert(ChainlinkCurveWindDownFeed.OnlyRWG.selector);
        feed.stopWindDown();
        assertEq(feed.windDownStartPrice(), price);
        assertEq(feed.windDownStartedAt(), startedAt);
    }

    function testStopRestoresLivePriceAndTimestampsAndEmitsEvent() public {
        activate();
        vm.warp(block.timestamp + DURATION / 2);
        base.set(1.03e18, block.timestamp, false);
        pool.set(0, 1.2e18, false);
        vm.recordLogs();
        vm.prank(RWG);
        feed.stopWindDown();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(feed));
        assertEq(logs[0].topics[0], keccak256("WindDownStopped(address)"));
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(RWG))));
        assertEq(feed.windDownStartPrice(), 0);
        assertEq(feed.windDownStartedAt(), 0);
        assertFalse(feed.canStartWindDown());
        ChainlinkCurveFeed existing = new ChainlinkCurveFeed(address(base), address(pool), 0, 0);
        (bool ok, bytes memory actual) = address(feed).staticcall(abi.encodeWithSignature("latestRoundData()"));
        (bool oldOk, bytes memory expected) = address(existing).staticcall(abi.encodeWithSignature("latestRoundData()"));
        assertTrue(ok && oldOk);
        assertEq(actual, expected);
        assertEq(feed.latestAnswer(), existing.latestAnswer());
    }

    function testStopPreservesStaleUpstreamTimestamp() public {
        activate();
        pool.set(0, 1e18, false);
        base.set(1e18, 0, false);
        vm.prank(RWG);
        feed.stopWindDown();
        (, int256 price,, uint256 updatedAt,) = feed.latestRoundData();
        assertEq(price, 1e18);
        assertEq(updatedAt, 0); // reset does not make stale live data fresh
    }

    function testStopDoesNotCallDependencies() public {
        activate();
        base.set(0, 0, true);
        pool.set(0, 0, true);
        dola.setFail(true);
        vm.prank(RWG);
        feed.stopWindDown();
        assertEq(feed.windDownStartPrice(), 0);
        assertEq(feed.windDownStartedAt(), 0);
        assertEq(dola.transferCalls(), 1);
        vm.expectRevert(bytes("base failure"));
        feed.latestRoundData(); // live mode is restored, including dependency failures
    }

    function testStopAllowsFreshActivationAndPaysOnlyNewReward() public {
        address firstCaller = address(123);
        address nextCaller = address(456);
        dola.mint(address(feed), 10e18);
        pool.set(0, 1.9e18, false);
        vm.prank(firstCaller);
        feed.startWindDown();
        uint256 firstPrice = feed.windDownStartPrice();
        vm.warp(block.timestamp + DURATION / 2);
        dola.mint(address(feed), 5e18);
        vm.prank(RWG);
        feed.stopWindDown();
        assertEq(dola.balanceOf(firstCaller), 10e18);
        assertEq(dola.balanceOf(RWG), 0);
        assertEq(dola.balanceOf(address(feed)), 5e18);
        assertTrue(feed.canStartWindDown()); // no pause or extra recovery threshold
        base.set(0.9e18, block.timestamp, false);
        uint256 nextPrice = uint256(feed.latestAnswer());
        vm.prank(nextCaller);
        feed.startWindDown();
        assertEq(feed.windDownStartedAt(), block.timestamp);
        assertEq(feed.windDownStartPrice(), nextPrice);
        assertLt(nextPrice, firstPrice);
        assertEq(feed.latestAnswer(), int256(nextPrice));
        assertEq(dola.balanceOf(firstCaller), 10e18);
        assertEq(dola.balanceOf(nextCaller), 5e18);
        assertEq(dola.balanceOf(address(feed)), 0);
        assertEq(dola.transferCalls(), 2);
        assertFalse(feed.canStartWindDown());
        vm.warp(block.timestamp + DURATION / 2);
        assertEq(feed.latestAnswer(), int256(100 + (nextPrice - 100) / 2));
    }

    function testStopIsIdempotentAndAvailableAtTerminalPrice() public {
        vm.prank(RWG);
        feed.stopWindDown();
        activate();
        vm.warp(block.timestamp + DURATION);
        assertEq(feed.latestAnswer(), 100);
        vm.prank(RWG);
        feed.stopWindDown();
        assertEq(feed.windDownStartPrice(), 0);
        assertGt(feed.latestAnswer(), 100);
        vm.prank(RWG);
        feed.stopWindDown();
        assertEq(feed.windDownStartedAt(), 0);
        assertEq(dola.transferCalls(), 1);
    }

    function testStopDoesNotClearOracleDailyLows() public {
        Oracle oracle = new Oracle(address(this));
        address collateral = address(0xCA11);
        oracle.setFeed(collateral, OracleFeed(address(feed)), 18);
        activate();
        vm.warp(block.timestamp + DURATION / 2);
        uint256 recordedLow = oracle.getPrice(collateral, 0);
        uint256 day = block.timestamp / 1 days;
        assertEq(oracle.dailyLows(collateral, day), recordedLow);
        pool.set(0, 1e18, false);
        base.set(1e18, block.timestamp, false);
        vm.prank(RWG);
        feed.stopWindDown();
        assertEq(oracle.getFeedPrice(collateral), 1e18);
        uint256 dampenedPrice = recordedLow * 10000 / 8500;
        assertEq(oracle.viewPrice(collateral, 8500), dampenedPrice);
        assertLt(dampenedPrice, 1e18);
        assertEq(oracle.dailyLows(collateral, day), recordedLow);
        vm.warp((day + 1) * 1 days);
        assertEq(oracle.viewPrice(collateral, 8500), dampenedPrice);
        vm.warp((day + 2) * 1 days);
        assertEq(oracle.viewPrice(collateral, 8500), 1e18);
    }

    function testFuzzDecay(uint32 elapsed, uint96 price, uint32 duration) public {
        price = uint96(bound(price, 190, type(uint96).max));
        duration = uint32(bound(duration, 1, type(uint32).max));
        feed = deploy(0, duration);
        base.set(int256(uint256(price)), block.timestamp, false);
        activate();
        uint256 start = feed.windDownStartPrice();
        assertEq(feed.latestAnswer(), int256(start));
        vm.warp(block.timestamp + elapsed);
        uint256 expected = elapsed >= duration ? 100 : 100 + (start - 100) * (duration - elapsed) / duration;
        assertEq(feed.latestAnswer(), int256(expected));
        assertLe(uint256(feed.latestAnswer()), start);
        assertGe(feed.latestAnswer(), 100);
        (,, uint256 startedAt, uint256 updatedAt,) = feed.latestRoundData();
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
    }

    function testEndpointAndMaximumArithmetic() public {
        feed = deploy(0, type(uint32).max);
        base.set(type(int256).max / 1e18, block.timestamp, false);
        activate();
        uint256 startTime = block.timestamp;
        uint256 startPrice = feed.windDownStartPrice();
        assertEq(feed.latestAnswer(), int256(startPrice));
        vm.warp(startTime + type(uint32).max - 1);
        assertEq(feed.latestAnswer(), int256(100 + (startPrice - 100) / type(uint32).max));
        vm.warp(startTime + type(uint32).max);
        assertEq(feed.latestAnswer(), 100);
        vm.warp(block.timestamp + 365 days);
        assertEq(feed.latestAnswer(), 100);
    }

    function testLPAndYearnPropagationBlocksBorrowingButKeepsPriceReadable() public {
        WindDownMockBase otherCoin = new WindDownMockBase();
        CurveLPPessimisticFeed lp = new CurveLPPessimisticFeed(address(pool), address(feed), address(otherCoin), false);
        CurveLPYearnV2Feed yv = new CurveLPYearnV2Feed(address(new WindDownMockYearn()), address(lp));
        Oracle oracle = new Oracle(address(this));
        address collateral = address(0xCA11);
        oracle.setFeed(collateral, OracleFeed(address(yv)), 18);
        WindDownMockMarket market = new WindDownMockMarket(address(oracle), collateral);
        BorrowController controller = new BorrowController(address(this), address(new WindDownMockDBR()));
        controller.setDailyLimit(address(market), 100e18);
        controller.setStalenessThreshold(address(market), BORROW_STALENESS_THRESHOLD);
        controller.allow(address(this));
        assertFalse(controller.isPriceStale(address(market)));
        vm.prank(address(market));
        assertTrue(controller.borrowAllowed(address(this), address(456), 1e18));
        // Borrowing is denied before any activation transaction, whichever coin supplies the LP minimum.
        for (uint256 i; i < 2; i++) {
            otherCoin.set(i == 0 ? int256(1e18) : int256(0.1e18), block.timestamp, false);
            pool.set(0, 1.9e18, false);
            (,,, uint256 pendingLpTimestamp,) = lp.latestRoundData();
            (, int256 pendingYvPrice,, uint256 pendingYvTimestamp,) = yv.latestRoundData();
            assertEq(pendingLpTimestamp, 0);
            assertEq(pendingYvTimestamp, 0);
            assertGt(pendingYvPrice, 0);
            assertGt(oracle.viewPrice(collateral, 8500), 0);
            assertEq(feed.windDownStartPrice(), 0);
            assertEq(dola.transferCalls(), 0);
            assertTrue(controller.isPriceStale(address(market)));
            vm.prank(address(market));
            assertFalse(controller.borrowAllowed(address(this), address(456), 1e18));
            controller.setStalenessThreshold(address(market), 0);
            assertFalse(controller.isPriceStale(address(market))); // check must be enabled
            controller.setStalenessThreshold(address(market), BORROW_STALENESS_THRESHOLD);
            pool.set(0, 1.9e18 - 1, false);
            (,,, pendingYvTimestamp,) = yv.latestRoundData();
            assertEq(pendingYvTimestamp, block.timestamp);
            vm.prank(address(market));
            assertTrue(controller.borrowAllowed(address(this), address(456), 1e18));
        }
        activate();
        // Timestamp minimum is independent of which coin supplies the minimum price.
        otherCoin.set(0.1e18, block.timestamp, false);
        (,,, uint256 lpTimestamp,) = lp.latestRoundData();
        (, int256 yvPrice,, uint256 yvTimestamp,) = yv.latestRoundData();
        assertEq(lpTimestamp, 0);
        assertEq(yvTimestamp, 0);
        assertGt(yvPrice, 0);
        assertTrue(controller.isPriceStale(address(market)));
        vm.prank(address(market));
        assertFalse(controller.borrowAllowed(address(this), address(456), 1e18));
        assertGt(oracle.viewPrice(collateral, 8500), 0); // liquidation pricing remains available
        controller.setStalenessThreshold(address(market), 0);
        assertFalse(controller.isPriceStale(address(market))); // deployment prerequisite
        controller.setStalenessThreshold(address(market), BORROW_STALENESS_THRESHOLD);
        pool.set(0, 1e18, false);
        otherCoin.set(1e18, block.timestamp, false);
        vm.prank(RWG);
        feed.stopWindDown();
        (,,, lpTimestamp,) = lp.latestRoundData();
        (,,, yvTimestamp,) = yv.latestRoundData();
        assertEq(lpTimestamp, block.timestamp);
        assertEq(yvTimestamp, block.timestamp);
        assertFalse(controller.isPriceStale(address(market)));
        vm.prank(address(market));
        assertTrue(controller.borrowAllowed(address(this), address(456), 1e18));
    }
}
