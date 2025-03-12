// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";
import {USDeNavBeforeMaturityFeed} from "src/feeds/USDeNavBeforeMaturityFeed.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {FeedSwitch} from "src/util/FeedSwitch.sol";

interface PendleSparkLinearDiscountOracleFactory {
      function createWithPt(address pt, uint256 baseDiscountPerYear) external returns (address);
}

contract PendlePTsUSDe29May25MarketForkTest is MarketBaseForkTest {
    address USDeFeed = address(0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961);
    address sUSDeFeed = address(0xFF3BC18cCBd5999CE63E788A1c250a88626aD099);
    address sUSDe = address(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    address pendlePT = address(0xb7de5dFCb74d25c2f21841fbd6230355C50d9308); // PT sUSDe 29 May 25
    address pendlePTHolder =
        address(0x8C0824fFccBE9A3CDda4c3d409A0b7447320F364);

    ChainlinkBasePriceFeed sUSDeWrappedFeed;
    USDeNavBeforeMaturityFeed beforeMaturityFeed;
    ChainlinkBasePriceFeed afterMaturityFeed;
    address navFeed;
    PendleSparkLinearDiscountOracleFactory navFactory = PendleSparkLinearDiscountOracleFactory(0xA9A924A4BB95509F77868E086154C25e934F6171);
    uint256 baseDiscount = 0.2 ether; // 20%
    FeedSwitch feedSwitch;
    
    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 22018716);
        
        Market pendleMarket = new Market(
            gov,
            fedAddr,
            pauseGuardian,
            simpleERC20EscrowAddr,
            IDolaBorrowingRights(address(dbrAddr)),
            IERC20(address(pendlePT)),
            IOracle(address(oracleAddr)),
            5000,
            5000,
            1000,
            true
        );
        
        address feedAddr = _deployFeed();
        _advancedInit(address(pendleMarket), feedAddr, false);
    }

    function _deployFeed() internal returns (address feed) {
        sUSDeWrappedFeed = new ChainlinkBasePriceFeed(
            gov,
            sUSDeFeed,
            address(0),
            24 hours
        );
        navFeed = navFactory.createWithPt(pendlePT, baseDiscount); 
        beforeMaturityFeed = new USDeNavBeforeMaturityFeed(
            address(sUSDeWrappedFeed),
            address(sUSDe),
            address(navFeed)
        );
        afterMaturityFeed = new ChainlinkBasePriceFeed(
            gov,
            USDeFeed,
            address(0),
            24 hours
        );
        
        feedSwitch = new FeedSwitch(
            address(navFeed),
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
