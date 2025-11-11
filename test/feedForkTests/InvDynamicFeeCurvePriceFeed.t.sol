// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/DynamicFeeCurveFeed.sol";
import "forge-std/console.sol";

contract InvDynamicFeeCurveFeedTest is Test {
    DynamicFeeCurveFeed feed;
    address invWethPool = 0xDcD90D866Ff9636e5a04768825d05d27b3Fb19eC;
    address baseWethToUsdFeed = 0x22390B88C53D1631f673b8Dcd91860267137b2c8;
    address inv = address(0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    IChainlinkBasePriceFeed oldInvFeed = IChainlinkBasePriceFeed(0x54F1E4EB93c5b5F4C12776c96e08a49A9928FE84);
    address newGov = address(0xA);
    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 23776456);
        feed = new DynamicFeeCurveFeed(baseWethToUsdFeed, invWethPool, inv, gov);
    }

    function test_decimals() public {
        assertEq(feed.decimals(), 18);
    }

    function test_description() public {
        string memory expected = "INV / USD";
        assertEq(feed.description(), expected);
    }

    function test_latestRoundData() public {
        (
            uint80 roundId,
            int256 invUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = IChainlinkBasePriceFeed(feed.pairedTokenToUsd()).latestRoundData();

        (,int256 estInvUsdPrice,,,) = oldInvFeed.latestRoundData();

        assertEq(roundId, clRoundId);
        assertApproxEqRel(invUsdPrice, estInvUsdPrice, 2e18, "Price feeds diverge too much");
        assertEq(startedAt, clStartedAt);
        assertEq(updatedAt, clUpdatedAt);
        assertEq(answeredInRound, clAnsweredInRound);
        console.log(uint(invUsdPrice));
    }

    function testMaxFee() external {
        vm.expectRevert("ONLY GOV");
        feed.setMaxFee(0);

        vm.prank(gov);
        vm.expectRevert("CurveFeed: maxFee > 100%");
        feed.setMaxFee(1e10 + 1);

        vm.prank(gov);
        feed.setMaxFee(0);

        (,int256 invUsdPrice,,,) = feed.latestRoundData();
        vm.prank(gov);
        feed.setMaxFee(2e8);
        (,int256 invUsdPriceWithFee,,,) = feed.latestRoundData();
        assertLt(invUsdPriceWithFee, invUsdPrice);
    }

    function testGovChange() external {
        vm.expectRevert("ONLY GOV");
        feed.setPendingGov(newGov);

        vm.prank(gov);
        feed.setPendingGov(newGov);
        assertEq(feed.pendingGov(), newGov);

        vm.expectRevert("ONLY PENDING GOV");
        feed.acceptGov();

        vm.prank(newGov);
        feed.acceptGov();
        assertEq(feed.gov(), newGov);
        assertEq(feed.pendingGov(), address(0));
    }
}
