// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";
import {USDeBeforeMaturityFeed} from "src/feeds/USDeBeforeMaturityFeed.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {DolaFixedPriceFeed} from "src/feeds/DolaFixedPriceFeed.sol";
import {FeedSwitch} from "src/util/FeedSwitch.sol";

contract PendlePTUSDeMarketForkTest is MarketBaseForkTest {
    address USDeFeed = address(0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961);
    address sUSDeFeed = address(0xFF3BC18cCBd5999CE63E788A1c250a88626aD099);
    address sUSDe = address(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    address pendlePT = address(0xE00bd3Df25fb187d6ABBB620b3dfd19839947b81); // PT sUSDe 27 MAR 2025
    address pendlePTHolder =
        address(0x9Dc53706C02c63Cf149F18978D478d4A3454B964);

    ChainlinkBasePriceFeed sUSDeWrappedFeed;
    USDeBeforeMaturityFeed beforeMaturityFeed;
    ChainlinkBasePriceFeed afterMaturityFeed;
    DolaFixedPriceFeed initialFeed;
    FeedSwitch feedSwitch;
    address marketAddr = address(0x0DFE3D04536a74Dd532dd0cEf5005bA14c5f4112);
    address feedAddr = address(0xddB5653FaC7a215139141863B2FAd021D44d7Ee4);

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21077341);

        _advancedInit(address(marketAddr), feedAddr, false);
    }

    function _deployFeed() internal returns (address feed) {
        sUSDeWrappedFeed = new ChainlinkBasePriceFeed(
            gov,
            sUSDeFeed,
            address(0),
            24 hours
        );
        beforeMaturityFeed = new USDeBeforeMaturityFeed(
            address(sUSDeWrappedFeed),
            address(sUSDe)
        );
        afterMaturityFeed = new ChainlinkBasePriceFeed(
            gov,
            USDeFeed,
            address(0),
            24 hours
        );
        initialFeed = new DolaFixedPriceFeed();
        feedSwitch = new FeedSwitch(
            address(initialFeed),
            address(beforeMaturityFeed),
            address(afterMaturityFeed),
            18 hours,
            pendlePT,
            pauseGuardian
        );
        return address(feedSwitch);
    }

    // Override the function to use the PendlePTHolder to avoid error revert: stdStorage find(StdStorage): Slot(s) not found
    function gibCollateral(
        address _address,
        uint _amount
    ) internal virtual override {
        vm.prank(pendlePTHolder);
        IERC20(pendlePT).transfer(_address, _amount);
    }
}
