// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {NavBeforeMaturityFeed} from "src/feeds/NavBeforeMaturityFeed.sol";
import {ChainlinkBasePriceFeed, IChainlinkFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "forge-std/console.sol";
import {PendleNAVFeed} from "src/feeds/PendleNAVFeed.sol";

interface INavFeed {
    function getDiscount(uint256 timeLeft) external view returns (uint256) ;
    function maturity() external view returns (uint256);
    function decimals() external view returns (uint8);
}

contract NavBeforeMaturityFeedTest is Test {
    address USDeFeed = address(0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961);
    NavBeforeMaturityFeed feed;
    ChainlinkBasePriceFeed usdeWrappedFeed = ChainlinkBasePriceFeed(0xB3C1D801A02d88adC96A294123c2Daa382345058); // USDe/USD wrapped
  
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    address pendlePT = address(0xBC6736d346a5eBC0dEbc997397912CD9b8FAe10a); // PT USDe 25 Sep 25

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 23132371);
        address navFeed = address(new PendleNAVFeed(pendlePT, 0.2 ether)); // 20% discount
        feed = new NavBeforeMaturityFeed(
            address(usdeWrappedFeed),
            navFeed
        );
    }

    function test_decimals() public {
        assertEq(feed.feed().decimals(), 18);
        assertEq(feed.decimals(), 18);
    }

    function test_description() public {
        string memory expected = string(
            abi.encodePacked(
                "USDe / USD with NAV"
            )
        );
        assertEq(feed.description(), expected);
    }

    function test_latestRoundData() public {
        (
            uint80 roundId,
            int256 navUSDeUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        (
            uint80 roundIdCl,
            int256 usdeUsdPrice,
            uint startedAtCl,
            uint updatedAtCl,
            uint80 answeredInRoundCl
        ) = usdeWrappedFeed.latestRoundData();
        assertEq(roundId, roundIdCl);
        assertEq(startedAt, startedAtCl);
        assertEq(updatedAt, updatedAtCl);
        assertEq(answeredInRound, answeredInRoundCl);

        
        (,int256 navDiscountedPrice,,,) = feed.navFeed().latestRoundData();
        int256 discountPrice = (usdeUsdPrice * navDiscountedPrice) / 1e18;
        assertEq(discountPrice, navUSDeUsdPrice);
    }

    function test_latestAnswer() public {
        int256 USDeUsdPrice = feed.latestAnswer();
        (,int256 navDiscountedPrice,,,) = feed.navFeed().latestRoundData();
        int256 discountPrice = (usdeWrappedFeed.latestAnswer() * navDiscountedPrice) / 1e18;
        assertEq(discountPrice, USDeUsdPrice);
    }

    function test_NAV() public {
        uint256 maturity = INavFeed(address(feed.navFeed())).maturity();
        vm.warp(maturity - 365 days/6); //2 months before expiry
        uint256 discount = INavFeed(address(feed.navFeed())).getDiscount(365 days/6);
        assertApproxEqAbs(discount, 0.0333 ether, 0.0001 ether);
        (,int256 navDiscountedPrice,,,) = feed.navFeed().latestRoundData();
        assertApproxEqAbs(navDiscountedPrice, 0.966666666 ether, 0.00000001 ether);
        int256 USDeUsdPrice = feed.latestAnswer();
        int256 discountPrice = (usdeWrappedFeed.latestAnswer() * navDiscountedPrice) / 1e18;
        assertEq(discountPrice, USDeUsdPrice);

        vm.warp(maturity - 365 days/12); //1 months before expiry
        uint256 discount2 = INavFeed(address(feed.navFeed())).getDiscount(365 days/12);
        assertApproxEqAbs(discount2, 0.016666666 ether, 0.0001 ether);
        (,int256 navDiscountedPrice2,,,) = feed.navFeed().latestRoundData();
        assertApproxEqAbs(navDiscountedPrice2, 0.983333333 ether, 0.00000001 ether);
        int256 USDeUsdPrice2 = feed.latestAnswer();
         int256 discountPrice2 = (usdeWrappedFeed.latestAnswer() * navDiscountedPrice2) / 1e18;
        assertEq(discountPrice2, USDeUsdPrice2);
        // Check if the discount is decreasing
        assertGt(discount, discount2);
        // Check if the price is increasing
        assertLt(navDiscountedPrice, navDiscountedPrice2);
        assertLt(USDeUsdPrice, USDeUsdPrice2);
        assertLt(discountPrice, discountPrice2);
    }
    function test_STALE_USDeFeed() public {
        vm.mockCall(
            address(USDeFeed),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 1.1e8, 0, 0, 0)
        );
        (
            uint80 roundId,
            int256 USDeUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        
        (,int256 navDiscountedPrice,,,) = feed.navFeed().latestRoundData();
        int256 discountPrice = (usdeWrappedFeed.latestAnswer() * navDiscountedPrice) / 1e18;
        assertEq(roundId, 0);
        assertEq(USDeUsdPrice, discountPrice);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
    }

    function test_maturity_passed() public {
        uint256 maturity = INavFeed(address(feed.navFeed())).maturity();
        vm.warp(maturity);
        address navFeed = address(new PendleNAVFeed(pendlePT, 0.2 ether)); 
        vm.expectRevert(NavBeforeMaturityFeed.MaturityPassed.selector);
        feed = new NavBeforeMaturityFeed(
            address(usdeWrappedFeed),
            navFeed
        );
    }
}
