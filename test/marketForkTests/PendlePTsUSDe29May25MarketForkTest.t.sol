// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";
import {PTDiscountedNAVFeed} from "src/feeds/PTDiscountedNAVFeed.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {FeedSwitch} from "src/util/FeedSwitch.sol";

interface PendleSparkLinearDiscountOracleFactory {
      function createWithPt(address pt, uint256 baseDiscountPerYear) external returns (address);
}

contract PendlePTsUSDe29May25MarketForkTest is MarketBaseForkTest {
    address USDeFeed = address(0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961);
    address pendlePT = address(0xb7de5dFCb74d25c2f21841fbd6230355C50d9308); // PT sUSDe 29 May 25
    address pendlePTHolder =
        address(0x8C0824fFccBE9A3CDda4c3d409A0b7447320F364);

    ChainlinkBasePriceFeed USDeWrappedFeed;
    uint256 baseDiscount = 0.2 ether; // 20%
    
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
        USDeWrappedFeed = new ChainlinkBasePriceFeed(
            gov,
            USDeFeed,
            address(0),
            24 hours
        );
        
        feed = address(new PTDiscountedNAVFeed(
            address(USDeWrappedFeed),
            pendlePT,
            0.2 ether
        ));
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
