// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";
import {USDeNavBeforeMaturityFeed} from "src/feeds/USDeNavBeforeMaturityFeed.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {FeedSwitch} from "src/util/FeedSwitch.sol";
import {PendleNAVFeed} from "src/feeds/PendleNAVFeed.sol";

contract PendlePTsUSDe24Sep25MarketForkTest is MarketBaseForkTest {
    address USDeFeed = address(0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961);
    address sUSDeFeed = address(0xFF3BC18cCBd5999CE63E788A1c250a88626aD099);
    address sUSDe = address(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    address pendlePT = address(0x9F56094C450763769BA0EA9Fe2876070c0fD5F77); // PT sUSDe 24 Sep 25
    address pendlePTHolder =
        address(0x5c14F9573697176b1cBd8af8378Cff9583DE4166);

    ChainlinkBasePriceFeed sUSDeWrappedFeed;
    USDeNavBeforeMaturityFeed beforeMaturityFeed;
    ChainlinkBasePriceFeed afterMaturityFeed;
    address navFeed;
    
    uint256 baseDiscount = 0.2 ether; // 20%
    FeedSwitch feedSwitch;
    
    address feedAddr; //FeedSwitch
    address marketAddr;
    
    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url,22590519);
        
        feedAddr = _deployFeed();

        marketAddr = address(
            new Market(
                gov,
                lender,
                pauseGuardian,
                simpleERC20EscrowAddr,
                IDolaBorrowingRights(dbrAddr),
                IERC20(pendlePT),
                IOracle(oracleAddr),
                9150,
                5000,
                500,
                false
            )
        );
        _advancedInit(marketAddr, feedAddr, false);
    }

    function _deployFeed() internal returns (address feed) {
        sUSDeWrappedFeed = new ChainlinkBasePriceFeed(
            gov,
            sUSDeFeed,
            address(0),
            24 hours
        );
        navFeed = address(new PendleNAVFeed(pendlePT, baseDiscount)); 
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
