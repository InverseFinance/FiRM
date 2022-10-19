// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./FrontierV2Test.sol";
import "../Oracle.sol";

import {EthFeed} from "./mocks/EthFeed.sol";
import "./mocks/WETH9.sol";

contract OracleTest is FrontierV2Test {
    address operator;
    
    bytes onlyPendingOperator = "ONLY PENDING OPERATOR";

    function setUp() public {
        vm.label(gov, "operator");
        operator = gov;

        initialize(replenishmentPriceBps, collateralFactorBps, replenishmentIncentiveBps, liquidationBonusBps, callOnDepositCallback);
    }

    function test_getPrice_recordsDailyLow() public {
        uint day = block.timestamp / 1 days;
        uint collateralFactor = market.collateralFactorBps();
        uint feedPrice = ethFeed.latestAnswer();
        uint oraclePrice = oracle.getPrice(address(WETH), collateralFactor);

        assertEq(oraclePrice, feedPrice);
        assertEq(oracle.dailyLows(address(WETH), day), feedPrice, "Oracle didn't record daily low on call to getPrice");

        uint newPrice = 1200e18;
        ethFeed.changeAnswer(newPrice);
        oraclePrice = oracle.getPrice(address(WETH), collateralFactor);

        assertEq(oraclePrice, newPrice, "Oracle didn't update when feed did");
        assertEq(oracle.dailyLows(address(WETH), day), newPrice, "Oracle didn't record daily low on call to getPrice");
    }

    function test_viewPrice_returnsDampenedPrice() public {
        uint collateralFactor = market.collateralFactorBps();
        uint day = block.timestamp / 1 days;
        uint feedPrice = ethFeed.latestAnswer();

        //1600e18 price saved as daily low
        oracle.getPrice(address(WETH), collateralFactor);
        assertEq(oracle.dailyLows(address(WETH), day), feedPrice, "Oracle didn't record daily low on call to getPrice");

        vm.warp(block.timestamp + 1 days);
        uint newPrice = 1200e18;
        ethFeed.changeAnswer(newPrice);
        //1200e18 price saved as daily low
        oracle.getPrice(address(WETH), collateralFactor);
        assertEq(oracle.dailyLows(address(WETH), ++day), newPrice, "Oracle didn't record daily low on call to getPrice");

        vm.warp(block.timestamp + 1 days);
        newPrice = 3000e18;
        ethFeed.changeAnswer(newPrice);

        //1200e18 should be twoDayLow, 3000e18 is current price. We should receive dampened price here.
        uint price = oracle.getPrice(address(WETH), collateralFactor);
        uint viewPrice = oracle.viewPrice(address(WETH), collateralFactor);
        assertEq(oracle.dailyLows(address(WETH), ++day), newPrice, "Oracle didn't record daily low on call to getPrice");

        assertEq(price, 1200e18 * 10_000 / collateralFactor, "Oracle did not dampen price correctly");
        assertEq(viewPrice, 1200e18 * 10_000 / collateralFactor, "Oracle did not dampen price correctly");
    }

    function test_viewPrice_reverts_whenNoPriceSet() public {
        uint collateralFactor = market.collateralFactorBps();

        vm.expectRevert("Price not found");
        oracle.viewPrice(address(0), collateralFactor);
    }

    function test_getPrice_reverts_whenNoPriceSet() public {
        uint collateralFactor = market.collateralFactorBps();

        vm.expectRevert("Price not found");
        oracle.getPrice(address(0), collateralFactor);
    }

    function test_viewPrice_returnsFixedPrice_whenFixedPriceAndOracleSet() public {
        uint collateralFactor = market.collateralFactorBps();

        //WETH feed is already set in FrontierV2Test.sol's `initialize()`
        assertEq(oracle.viewPrice(address(WETH), collateralFactor), ethFeed.latestAnswer(), "WETH feed not set");

        vm.startPrank(operator);
        oracle.setFixedPrice(address(WETH), 1_000e18);
        assertEq(oracle.viewPrice(address(WETH), collateralFactor), 1_000e18, "Fixed price should overwrite feed");
    }

    function test_getPrice_returnsFixedPrice_whenFixedPriceAndOracleSet() public {
        uint collateralFactor = market.collateralFactorBps();

        //WETH feed is already set in FrontierV2Test.sol's `initialize()`
        assertEq(oracle.getPrice(address(WETH), collateralFactor), ethFeed.latestAnswer(), "WETH feed not set");

        vm.startPrank(operator);
        oracle.setFixedPrice(address(WETH), 1_000e18);
        assertEq(oracle.getPrice(address(WETH), collateralFactor), 1_000e18, "Fixed price should overwrite feed");
    }

    function test_viewPrice_reverts_whenFeedPriceReturns0() public {
        ethFeed.changeAnswer(0);
        uint collateralFactor = market.collateralFactorBps();

        vm.expectRevert("Invalid feed price");

        oracle.viewPrice(address(WETH), collateralFactor);
    }

    function test_getPrice_reverts_whenFeedPriceReturns0() public {
        ethFeed.changeAnswer(0);
        uint collateralFactor = market.collateralFactorBps();

        vm.expectRevert("Invalid feed price");

        oracle.getPrice(address(WETH), collateralFactor);
    }
    
    //Access Control

    function test_accessControl_setPendingOperator() public {
        vm.startPrank(operator);
        oracle.setPendingOperator(address(0));
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        oracle.setPendingOperator(address(0));
    }

    function test_accessControl_claimOperator() public {
        vm.startPrank(operator);
        oracle.setPendingOperator(user);
        vm.stopPrank();

        vm.startPrank(user2);
        vm.expectRevert(onlyPendingOperator);
        oracle.claimOperator();
        vm.stopPrank();

        vm.startPrank(user);
        oracle.claimOperator();
        assertEq(oracle.operator(), user, "Call to claimOperator failed");
    }

    function test_accessControl_setFeed() public {
        vm.startPrank(operator);
        oracle.setFeed(address(WETH), IChainlinkFeed(address(ethFeed)), 18);
        uint collateralFactor = market.collateralFactorBps();
        assertEq(oracle.viewPrice(address(WETH), collateralFactor), ethFeed.latestAnswer(), "Feed failed to set");
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        oracle.setFeed(address(WETH), IChainlinkFeed(address(ethFeed)), 18);
    }

    function test_accessControl_setFixedPrice() public {
        vm.startPrank(operator);
        uint collateralFactor = market.collateralFactorBps();
        oracle.setFixedPrice(address(WETH), 1200e18);
        assertEq(oracle.viewPrice(address(WETH), collateralFactor), 1200e18, "Fixed price failed to set");
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        oracle.setFixedPrice(address(WETH), 1200e18);
    }
}