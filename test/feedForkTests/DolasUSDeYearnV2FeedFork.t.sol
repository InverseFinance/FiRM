// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {CurveLPYearnV2FeedBaseTest} from "test/feedForkTests/CurveLPYearnV2FeedBaseTest.t.sol";

contract DolasUSDeYearnV2FeedFork is CurveLPYearnV2FeedBaseTest {
    ChainlinkBasePriceFeed sUSDeFeed =
        ChainlinkBasePriceFeed(0x6277cB27232F35C75D3d908b26F3670e7d167400);

    ICurvePool public constant dolasUSDe =
        ICurvePool(0x744793B5110f6ca9cC7CDfe1CE16677c3Eb192ef);

    address public constant yearnVault =
        address(0x1Fc80CfCF5B345b904A0fB36d4222196Ed9eB8a5);

    CurveLPPessimisticFeed dolasUSDeFeed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21239297);

        dolasUSDeFeed = new CurveLPPessimisticFeed(
            address(dolasUSDe),
            address(sUSDeFeed),
            dolaFixedFeedAddr,
            false
        );
        init(address(dolasUSDeFeed), address(sUSDeFeed), yearnVault);
    }
}
