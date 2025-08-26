// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";
import {NavBeforeMaturityFeed} from "src/feeds/NavBeforeMaturityFeed.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {FeedSwitch} from "src/util/FeedSwitch.sol";
import {PendleNAVFeed} from "src/feeds/PendleNAVFeed.sol";

contract PendlePTUSDe27Nov25MarketForkTest is MarketBaseForkTest {
    address pendlePT = address(0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7); // PT USDe 27 Nov 25
    address pendlePTHolder =
        address(0xAc5CE72d29836f41d235F643F6f0190E8c12db8A);

    ChainlinkBasePriceFeed usdeWrappedFeed = ChainlinkBasePriceFeed(0xB3C1D801A02d88adC96A294123c2Daa382345058); // USDe/USD wrapped
    NavBeforeMaturityFeed beforeMaturityFeed;
    ChainlinkBasePriceFeed afterMaturityFeed = ChainlinkBasePriceFeed(0xB3C1D801A02d88adC96A294123c2Daa382345058);
    address navFeed;

    uint256 baseDiscount = 0.20 ether; // 20%
    FeedSwitch feedSwitch;

    address feedAddr; //FeedSwitch
    address marketAddr;

    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 23225429);

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
        navFeed = address(new PendleNAVFeed(pendlePT, baseDiscount)); 
        beforeMaturityFeed = new NavBeforeMaturityFeed(
            address(usdeWrappedFeed),
            address(navFeed)
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