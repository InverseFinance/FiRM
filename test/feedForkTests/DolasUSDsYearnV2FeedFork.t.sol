// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {CurveLPYearnV2FeedBaseTest} from "test/feedForkTests/CurveLPYearnV2FeedBaseTest.t.sol";

contract DolasUSDsYearnV2FeedFork is CurveLPYearnV2FeedBaseTest {
    address clDaiFeed = address(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);
    uint256 daiHeartbeat = 3600;

    ICurvePool public constant dolasUSDs =
        ICurvePool(0x8b83c4aA949254895507D09365229BC3a8c7f710);

    address public constant yearnVault =
        address(0x342D24F2a3233F7Ac8A7347fA239187BFd186066);

    CurveLPPessimisticFeed dolasUSDsFeed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21239299);

        ChainlinkBasePriceFeed sUSDsFeed = new ChainlinkBasePriceFeed(
            gov,
            clDaiFeed,
            address(0),
            daiHeartbeat
        );

        dolasUSDsFeed = new CurveLPPessimisticFeed(
            address(dolasUSDs),
            address(sUSDsFeed),
            dolaFixedFeedAddr,
            false
        );
        init(address(dolasUSDsFeed), address(sUSDsFeed), yearnVault);
    }
}
