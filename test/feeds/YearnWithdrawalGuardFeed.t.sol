// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BorrowController} from "src/BorrowController.sol";
import {YearnWithdrawalGuardFeed} from "src/feeds/YearnWithdrawalGuardFeed.sol";
import {Oracle, IChainlinkFeed as OracleFeed} from "src/Oracle.sol";

contract WithdrawalGuardMockVault {
    address public asset;
    mapping(address => uint256) public balanceOf;
    uint256 public withdrawableAssets;

    constructor(address _asset) {
        asset = _asset;
    }

    function setPosition(address owner, uint256 shares, uint256 withdrawable) external {
        balanceOf[owner] = shares;
        withdrawableAssets = withdrawable;
    }

    function previewRedeem(uint256 shares) external pure returns (uint256) {
        return shares * 2;
    }

    function maxWithdraw(address owner, uint256 maxLoss) external view returns (uint256) {
        require(balanceOf[owner] != 0 && maxLoss == 0, "unexpected withdrawal check");
        return withdrawableAssets;
    }
}

contract WithdrawalGuardMockFeed {
    address public immutable vault;
    uint256 public updatedAt;
    int256 public constant latestAnswer = 1.1e18;
    uint8 public constant decimals = 18;
    string public constant description = "Yearn staking vault / USD";

    constructor(address _vault) {
        vault = _vault;
        updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (42, latestAnswer, 123, updatedAt, 43);
    }
}

contract WithdrawalGuardMockMarket {
    address public immutable oracle;
    address public immutable collateral;

    constructor(address _oracle, address _collateral) {
        oracle = _oracle;
        collateral = _collateral;
    }

    function borrowAllowed(BorrowController controller, address borrower, uint256 amount) external returns (bool) {
        return controller.borrowAllowed(borrower, borrower, amount);
    }
}

contract WithdrawalGuardMockDBR {
    function lastUpdated(address) external pure returns (uint256) {
        return 0;
    }

    function debts(address) external pure returns (uint256) {
        return 0;
    }
}

contract YearnWithdrawalGuardFeedTest is Test {
    WithdrawalGuardMockVault backingVault;
    WithdrawalGuardMockVault stakingVault;
    WithdrawalGuardMockFeed priceFeed;
    YearnWithdrawalGuardFeed guard;

    function setUp() external {
        vm.warp(10 days);
        backingVault = new WithdrawalGuardMockVault(address(1));
        stakingVault = new WithdrawalGuardMockVault(address(backingVault));
        priceFeed = new WithdrawalGuardMockFeed(address(stakingVault));
        guard = new YearnWithdrawalGuardFeed(address(priceFeed), 100);
        backingVault.setPosition(address(stakingVault), 500e18, 1000e18);
    }

    function testHealthyRoundPassesThroughUnchanged() external view {
        (uint80 id, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            guard.latestRoundData();
        assertEq(id, 42);
        assertEq(price, priceFeed.latestAnswer());
        assertEq(startedAt, 123);
        assertEq(updatedAt, priceFeed.updatedAt());
        assertEq(answeredInRound, 43);
    }

    function testThresholdUsesQuotedAssetsAndAllowsExactlyOnePercentShortfall() external {
        backingVault.setPosition(address(stakingVault), 500e18, 990e18);
        assertEq(_updatedAt(), priceFeed.updatedAt());

        backingVault.setPosition(address(stakingVault), 500e18, 990e18 - 1);
        assertEq(_updatedAt(), 0);
        assertEq(guard.latestAnswer(), priceFeed.latestAnswer());
    }

    function testWithdrawalReadFailureReturnsPriceWithZeroTimestamp() external {
        vm.mockCallRevert(
            address(backingVault),
            abi.encodeWithSelector(backingVault.maxWithdraw.selector, address(stakingVault), 0),
            bytes("withdrawal quote unavailable")
        );
        (, int256 price,, uint256 updatedAt,) = guard.latestRoundData();
        assertEq(price, priceFeed.latestAnswer());
        assertEq(updatedAt, 0);
    }

    function testMalformedWithdrawalReadReturnsPriceWithZeroTimestamp() external {
        vm.mockCall(
            address(backingVault),
            abi.encodeWithSelector(backingVault.maxWithdraw.selector, address(stakingVault), 0),
            hex"01"
        );
        (, int256 price,, uint256 updatedAt,) = guard.latestRoundData();
        assertEq(price, priceFeed.latestAnswer());
        assertEq(updatedAt, 0);
    }

    function testZeroBackingMarksRoundStale() external {
        backingVault.setPosition(address(stakingVault), 0, 0);
        assertEq(_updatedAt(), 0);
    }

    function testUpstreamStalenessAndTimestampArePreserved() external {
        priceFeed.setUpdatedAt(block.timestamp - 2 days);
        assertEq(_updatedAt(), block.timestamp - 2 days);

        priceFeed.setUpdatedAt(0);
        assertEq(_updatedAt(), 0);
    }

    function testBorrowingStopsAndResumesWhileLiquidationPriceRemainsAvailable() external {
        Oracle oracle = new Oracle(address(this));
        address collateral = address(stakingVault);
        oracle.setFeed(collateral, OracleFeed(address(guard)), 18);
        WithdrawalGuardMockMarket market = new WithdrawalGuardMockMarket(address(oracle), collateral);
        BorrowController controller = new BorrowController(address(this), address(new WithdrawalGuardMockDBR()));
        controller.setStalenessThreshold(address(market), 86_500);
        controller.setDailyLimit(address(market), 500_000e18);

        address borrower = makeAddr("borrower");
        controller.allow(borrower);
        assertTrue(market.borrowAllowed(controller, borrower, 10_000e18));

        backingVault.setPosition(address(stakingVault), 500e18, 989e18);
        assertTrue(controller.isPriceStale(address(market)));
        assertFalse(market.borrowAllowed(controller, borrower, 10_000e18));
        assertEq(oracle.getPrice(collateral, 8500), uint256(priceFeed.latestAnswer()));

        backingVault.setPosition(address(stakingVault), 500e18, 1000e18);
        assertTrue(market.borrowAllowed(controller, borrower, 10_000e18));
    }

    function _updatedAt() internal view returns (uint256 updatedAt) {
        (,,, updatedAt,) = guard.latestRoundData();
    }
}
