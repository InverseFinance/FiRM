// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";
import "src/feeds/ERC4626Feed.sol";
import "src/Market.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";

contract SdeUSDMarketForkTest is MarketBaseForkTest {
    address curvePool = address(0x82202CAEC5E6d85014eADC68D4912F3C90093e7C);
    uint256 k = 0;
    uint256 targetIndex = 1;
    address sdeUSD = address(0x5C5b196aBE0d54485975D1Ec29617D42D9198326);
    address dolaFeed = address(0x6255981e2a1EBeA600aFC506185590eD383517be);

    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21880983);
        address curveFeed = address(
            new ChainlinkCurveFeed(dolaFeed, curvePool, k, targetIndex)
        );
        address feedAddr = address(new ERC4626Feed(sdeUSD, curveFeed));

        address marketAddr = address(
            new Market(
                gov,
                lender,
                pauseGuardian,
                simpleERC20EscrowAddr,
                IDolaBorrowingRights(dbrAddr),
                IERC20(sdeUSD),
                IOracle(oracleAddr),
                5000,
                1000,
                1000,
                false
            )
        );
        _advancedInit(marketAddr, feedAddr, false);
    }
}
