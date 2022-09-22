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
        assertEq(oracle.getPrice(address(WETH)), ethFeed.latestAnswer(), "Feed failed to set");
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        oracle.setFeed(address(WETH), IChainlinkFeed(address(ethFeed)), 18);
    }

    function test_accessControl_setFixedPrice() public {
        vm.startPrank(operator);
        oracle.setFixedPrice(address(WETH), 1200e18);
        assertEq(oracle.getPrice(address(WETH)), 1200e18, "Fixed price failed to set");
        vm.stopPrank();

        vm.expectRevert(onlyOperator);
        oracle.setFixedPrice(address(WETH), 1200e18);
    }
}