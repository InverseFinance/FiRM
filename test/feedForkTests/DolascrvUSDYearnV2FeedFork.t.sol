// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {CurveLPYearnV2FeedBaseTest} from "test/feedForkTests/CurveLPYearnV2FeedBaseTest.t.sol";

contract DolascrvUSDYearnV2FeedFork is CurveLPYearnV2FeedBaseTest {
    address clCrvUSDFeed = address(0xEEf0C605546958c1f899b6fB336C20671f9cD49F);
    uint256 crvUSDHeartbeat = 86400;
    ICurvePool public constant dolascrvUSD =
        ICurvePool(0xff17dAb22F1E61078aBa2623c89cE6110E878B3c);

    address public constant yearnVault =
        address(0xbCe40f1840A449cAAaF374Df0A1fEe1e212784CB);

    CurveLPPessimisticFeed dolascrvUSDFeed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21286315);

        ChainlinkBasePriceFeed scrvUSDFeed = new ChainlinkBasePriceFeed(
            gov,
            clCrvUSDFeed,
            address(0),
            crvUSDHeartbeat
        );

        dolascrvUSDFeed = new CurveLPPessimisticFeed(
            address(dolascrvUSD),
            address(scrvUSDFeed),
            dolaFixedFeedAddr,
            false
        );
        init(address(dolascrvUSDFeed), address(scrvUSDFeed), yearnVault);
    }
}
