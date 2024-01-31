// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./FiRMBaseTest.sol";

contract OracleTest is FiRMBaseTest {
    address operator;
    
    bytes onlyPendingOperator = "ONLY PENDING OPERATOR";

    function setUp() public {
        vm.label(gov, "operator");
        operator = gov;

        initialize(replenishmentPriceBps, collateralFactorBps, replenishmentIncentiveBps, liquidationBonusBps, callOnDepositCallback);

        vm.startPrank(gov);
        oracle.setWindow(address(WETH), 3 days);
        oracle.setWindow(address(DOLA), 3 days);
        oracle.setWindow(address(wBTC), 3 days);
        vm.stopPrank();

    }

    function test_getPrice_recordsWindowLowWeth() public {
        uint collateralFactor = market.collateralFactorBps();
        uint feedPrice = ethFeed.latestAnswer();
        uint oraclePrice = oracle.getPrice(address(WETH), collateralFactor);

        assertEq(oraclePrice, feedPrice);
        (uint low, uint timestamp) = oracle.lows(address(WETH));
        assertEq(low, feedPrice, "Oracle didn't record low on call to getPrice");

        uint newPrice = 1200e18;
        ethFeed.changeAnswer(newPrice);
        oraclePrice = oracle.getPrice(address(WETH), collateralFactor);

        assertEq(oraclePrice, newPrice, "Oracle didn't update when feed did");
        (low, timestamp) = oracle.lows(address(WETH));
        assertEq(low, newPrice, "Oracle didn't record low on call to getPrice");
    }

    function test_getPrice_records_NEW_WindowLowWeth() public {
        uint collateralFactor = market.collateralFactorBps();
        uint feedPrice = ethFeed.latestAnswer();
        uint oraclePrice = oracle.getPrice(address(WETH), collateralFactor);

        assertEq(oraclePrice, feedPrice);
        (uint low, uint timestamp) = oracle.lows(address(WETH));
        assertEq(low, feedPrice, "Oracle didn't record low on call to getPrice");

        uint newPrice = 1200e18;
        ethFeed.changeAnswer(newPrice);
        oraclePrice = oracle.getPrice(address(WETH), collateralFactor);

        assertEq(oraclePrice, newPrice, "Oracle didn't update when feed did");
        (low, timestamp) = oracle.lows(address(WETH));
        assertEq(low, newPrice, "Oracle didn't record low on call to getPrice");

        vm.warp(block.timestamp + 3 days + 1);
        newPrice = 3000e18;
        ethFeed.changeAnswer(newPrice);
        oraclePrice = oracle.getPrice(address(WETH), collateralFactor);

        assertEq(oraclePrice, newPrice, "Oracle didn't update when feed did");
        (low, timestamp) = oracle.lows(address(WETH));
        assertEq(low, newPrice, "Oracle didn't record low on call to getPrice");
    }

    function test_getPrice_records_NEW_LOWER_Window_set() public {
        uint collateralFactor = market.collateralFactorBps();
        uint feedPrice = ethFeed.latestAnswer();
        uint oraclePrice = oracle.getPrice(address(WETH), collateralFactor);

        assertEq(oraclePrice, feedPrice);
        (uint low, uint timestamp) = oracle.lows(address(WETH));
        assertEq(low, feedPrice, "Oracle didn't record low on call to getPrice");

        // Advance time to 1 day + 1 second
        vm.warp(block.timestamp + 1 days + 1);

        // Update window to 1 day
        vm.prank(gov);
        oracle.setWindow(address(WETH), 1 days);

        // Will update timestamp because of new window
        uint newPrice = 2000e18;
        ethFeed.changeAnswer(newPrice);
        oraclePrice = oracle.getPrice(address(WETH), collateralFactor);

        assertEq(oraclePrice, newPrice, "Oracle didn't update when feed did");
        (low, timestamp) = oracle.lows(address(WETH));
        assertEq(low, newPrice, "Oracle didn't record low on call to getPrice");        
    }

    function test_getPrice_records_NEW_BIGGER_Window_set() public {
        uint collateralFactor = market.collateralFactorBps();
        uint feedPrice = ethFeed.latestAnswer();
        uint oraclePrice = oracle.getPrice(address(WETH), collateralFactor);

        assertEq(oraclePrice, feedPrice);
        (uint low, uint timestamp) = oracle.lows(address(WETH));
        assertEq(low, feedPrice, "Oracle didn't record low on call to getPrice");

        // Advance time to 3 days + 1 second
        vm.warp(block.timestamp + 3 days + 1);

        // Update window to 5 day
        vm.prank(gov);
        oracle.setWindow(address(WETH), 5 days);

        // Won't update bc of new window (5 days) still include the previous low, return current price
        uint newPrice = 2200e18;
        ethFeed.changeAnswer(newPrice);
        oraclePrice = oracle.getPrice(address(WETH), collateralFactor);

        assertNotEq(oraclePrice, feedPrice, "Oracle update when shouldn't");
        (low, timestamp) = oracle.lows(address(WETH));
        assertEq(low, feedPrice, "Oracle didn't record low on call to getPrice");
        assertEq(oraclePrice, newPrice, "Oracle update when shouldn't");        
    }

    function test_getPrice_recordsWindowLowDola() public {
        uint collateralFactor = market.collateralFactorBps();
        uint feedPrice = dolaFeed.latestAnswer();
        uint oraclePrice = oracle.getPrice(address(DOLA), collateralFactor);

        //Oracle price is 18 decimals, while feed price is 20 decimals, therefor we have to divide by 100
        assertEq(oraclePrice, feedPrice / 100);
        (uint low, uint timestamp) = oracle.lows(address(DOLA));
        assertEq(low, feedPrice / 100, "Oracle didn't record low on call to getPrice");

        uint newPrice = 1e20 - 10;
        dolaFeed.changeAnswer(newPrice);
        oraclePrice = oracle.getPrice(address(DOLA), collateralFactor);

        assertEq(oraclePrice, newPrice / 100, "Oracle didn't update when feed did");
        (low, timestamp) = oracle.lows(address(DOLA));
        assertEq(low, newPrice / 100, "Oracle didn't record low on call to getPrice");
    }


    function test_getPrice_recordsWindowLowWbtc() public {
        uint collateralFactor = market.collateralFactorBps();
        uint feedPrice = wbtcFeed.latestAnswer();
        uint expectedOraclePrice = feedPrice * 1e20;
        uint oraclePrice = oracle.getPrice(address(wBTC), collateralFactor);
        assertEq(oraclePrice, expectedOraclePrice);
        (uint low, uint timestmap) = oracle.lows(address(wBTC));
        assertEq(low, expectedOraclePrice, "Oracle didn't record low on call to getPrice");

        uint newPrice = 12000e8;
        uint expectedPrice = newPrice * 1e20;
        wbtcFeed.changeAnswer(newPrice);
        oraclePrice = oracle.getPrice(address(wBTC), collateralFactor);

        assertEq(oraclePrice, expectedPrice, "Oracle didn't update when feed did");
        (low, timestmap) = oracle.lows(address(wBTC));
        assertEq(low, expectedPrice, "Oracle didn't record low on call to getPrice");
    }

    function test_viewPrice_returnsDampenedPrice() public {
        uint collateralFactor = market.collateralFactorBps();
        uint feedPrice = ethFeed.latestAnswer();

        //1600e18 price saved as daily low
        oracle.getPrice(address(WETH), collateralFactor);
        (uint low, uint timestamp) = oracle.lows(address(WETH));
        assertEq(low, feedPrice, "Oracle didn't record low on call to getPrice");

        vm.warp(block.timestamp + 1 days);
        uint newPrice = 1200e18;
        ethFeed.changeAnswer(newPrice);
        //1200e18 price saved as daily low
        oracle.getPrice(address(WETH), collateralFactor);
        (low, timestamp) = oracle.lows(address(WETH));
        assertEq(low, newPrice, "Oracle didn't record daily low on call to getPrice");

        vm.warp(block.timestamp + 1 days);
        newPrice = 3000e18;
        ethFeed.changeAnswer(newPrice);

        //1200e18 should be twoDayLow, 3000e18 is current price. We should receive dampened price here.
        uint price = oracle.getPrice(address(WETH), collateralFactor);
        uint viewPrice = oracle.viewPrice(address(WETH), collateralFactor);
        (low, timestamp) = oracle.lows(address(WETH));
        assertEq(low, 1200e18, "Oracle didn't record daily low on call to getPrice");

        assertEq(price, 1200e18 * 10_000 / collateralFactor, "Oracle did not dampen price correctly");
        assertEq(viewPrice, 1200e18 * 10_000 / collateralFactor, "Oracle did not dampen view price correctly");
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

    function test_viewPriceNoDampenedPrice_AUDIT() public {
        uint collateralFactor = market.collateralFactorBps();
        uint feedPrice = ethFeed.latestAnswer();

        //1600e18 price saved as window low
        oracle.getPrice(address(WETH), collateralFactor);
        (uint low, uint timestamp) = oracle.lows(address(WETH));
        assertEq(low, feedPrice, "Oracle didn't record low on call to getPrice");

        vm.warp(block.timestamp + 1 days);
        uint newPrice = 1200e18;
        ethFeed.changeAnswer(newPrice);
        //1200e18 price saved as window low
        oracle.getPrice(address(WETH), collateralFactor);
        (low, timestamp) = oracle.lows(address(WETH));
        assertEq(low, newPrice, "Oracle didn't record low on call to getPrice");

        vm.warp(block.timestamp + 1 days);
        newPrice = 3000e18;
        ethFeed.changeAnswer(newPrice);

        //1200e18 should be twoDayLow, 3000e18 is current price. We should receive dampened price here.
        // Notice that viewPrice is called before getPrice.
        uint viewPrice = oracle.viewPrice(address(WETH), collateralFactor);
        uint price = oracle.getPrice(address(WETH), collateralFactor);
        assertEq(viewPrice, price);
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

}
