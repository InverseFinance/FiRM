// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/DolaPriceFeed.sol";
import "forge-std/console.sol";

contract DolaPriceFeedTest is Test {
    DolaPriceFeed feed;
    uint256 dolaHeartbeat = 24 hours;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 19720063); // FRAX < pyUSD at this block
        feed = new DolaPriceFeed();
    }

    function test_decimals() public {
        assertEq(feed.decimals(), 18);
    }

    function test_latestRoundData() public {
        (
            uint80 roundId,
            int256 lpUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        (
            uint80 oracleRoundId,
            int256 oracleLpToUsdPrice,
            uint oracleStartedAt,
            uint oracleUpdatedAt,
            uint80 oracleAnsweredInRound
        ) = _calculateOracleLpPrice();

        assertEq(roundId, oracleRoundId);
        assertEq(lpUsdPrice, oracleLpToUsdPrice);
        assertEq(startedAt, oracleStartedAt);
        assertEq(updatedAt, oracleUpdatedAt);
        assertEq(answeredInRound, oracleAnsweredInRound);
    }

    function test_use_Frax_when_pyUSD_gt_frax() public {
        (
            uint80 clRoundId,
            int256 fraxUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.fraxToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 dolaUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        uint256 estimDolaUsdPrice = uint256(
            (feed.pyUSDFrax().get_virtual_price() *
                uint256(fraxUsdPrice) *
                10 ** 18) / feed.crvDOLA().price_oracle(0)
        ) / 10 ** 8;
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);
        assertEq(uint256(dolaUsdPrice), estimDolaUsdPrice);
    }

    function test_use_pyUSD_when_pyUSD_lt_frax() public {
        // Set FRAX > than pyUSD
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        (
            uint80 clRoundId,
            int256 pyUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.pyUsdToUsd().latestRoundData();

        (
            uint80 roundId,
            int256 dolaUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        uint256 estimDolaUsdPrice = uint256(
            (feed.pyUSDFrax().get_virtual_price() *
                uint256(pyUsdPrice) *
                10 ** 18) / feed.crvDOLA().price_oracle(0)
        ) / 10 ** 8;
        assertEq(clRoundId, roundId);
        assertEq(clStartedAt, startedAt);
        assertEq(clUpdatedAt, updatedAt);
        assertEq(clAnsweredInRound, answeredInRound);
        assertEq(uint256(dolaUsdPrice), estimDolaUsdPrice);
    }

    function test_PyUSD_Out_of_bounds_MAX_use_Frax_when_pyUSD_lt_frax() public {
        // Set FRAX > than pyUSD
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        (
            uint80 clRoundId,
            ,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.pyUsdToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 fraxToUsd,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = feed.fraxToUsd().latestRoundData();

        // Out of MAX bounds pyUSD/USD price
        vm.mockCall(
            address(feed.pyUsdToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                10 ** 12,
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
        );

        (
            uint80 roundId,
            int256 dolaUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId2, roundId);
        assertEq(clStartedAt2, startedAt);
        assertEq(clUpdatedAt2, updatedAt);
        assertEq(clAnsweredInRound2, answeredInRound);

        int dolaPrice = int(
            (feed.pyUSDFrax().get_virtual_price() *
                uint256(fraxToUsd) *
                10 ** 18) / feed.crvDOLA().price_oracle(0)
        ) / 10 ** 8;
        assertEq(uint256(dolaUsdPrice), uint256(dolaPrice));
        assertEq(uint256(dolaUsdPrice), uint(feed.latestAnswer()));
    }

    function test_PyUSD_Out_of_bounds_MIN_return_STALE_when_pyUSD_lt_frax()
        public
    {
        // Set FRAX > than pyUSD
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(0, 110000000, 0, block.timestamp, 0)
        );

        (
            uint80 clRoundId,
            int256 pyUsdToUsd,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.pyUsdToUsd().latestRoundData();
        (
            uint80 clRoundId2,
            int256 fraxToUsd,
            uint clStartedAt2,
            uint clUpdatedAt2,
            uint80 clAnsweredInRound2
        ) = feed.fraxToUsd().latestRoundData();

        // Out of MIN bounds pyUSD/USD price
        vm.mockCall(
            address(feed.pyUsdToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                1,
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
        );

        (
            uint80 roundId,
            int256 dolaUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        assertEq(clRoundId, roundId, "roundId");
        assertEq(clStartedAt, startedAt, "startedAt");
        assertEq(0, updatedAt, "updatedAt");
        assertEq(clAnsweredInRound, answeredInRound, "answeredInRound");
        assertGt(block.timestamp, updatedAt + dolaHeartbeat);
    }

    function test_PyUSD_Out_of_bounds_return_Frax() public {
        (
            uint80 clRoundId,
            int256 pyUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.pyUsdToUsd().latestRoundData();

        // Out of MAX bounds pyUSD/USD price
        vm.mockCall(
            address(feed.pyUsdToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                IAggregator(feed.pyUsdToUsd().aggregator()).maxAnswer(),
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
        );

        (
            uint80 roundId,
            int256 dolaUsdPrice,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        (, int256 fraxToUsd, , uint256 updatedAtFrax, ) = feed
            .fraxToUsd()
            .latestRoundData();

        assertEq(updatedAt, updatedAtFrax);
        assertGt(updatedAt + dolaHeartbeat, block.timestamp);

        int dolaPrice = int(
            (feed.pyUSDFrax().get_virtual_price() *
                uint256(fraxToUsd) *
                10 ** 18) / feed.crvDOLA().price_oracle(0)
        ) / 10 ** 8;
        assertEq(uint256(dolaUsdPrice), uint256(dolaPrice));
        assertEq(uint256(dolaUsdPrice), uint(feed.latestAnswer()));
    }

    function test_Frax_Out_of_bounds_MAX_return_pyUSD() public {
        (
            uint80 clRoundId,
            int256 fraxUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.fraxToUsd().latestRoundData();

        // Out of MAX bounds Frax/USD price
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                IAggregator(feed.fraxToUsd().aggregator()).maxAnswer(),
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
        );

        (, int256 dolaUsdPrice, , uint updatedAt, ) = feed.latestRoundData();

        (, int256 pyUsdPrice, , uint256 updateAtPyUsd, ) = feed
            .pyUsdToUsd()
            .latestRoundData();

        assertEq(updateAtPyUsd, updatedAt);
        assertGt(updatedAt + dolaHeartbeat, block.timestamp);

        int dolaPrice = int(
            (feed.pyUSDFrax().get_virtual_price() *
                uint256(pyUsdPrice) *
                10 ** 18) / feed.crvDOLA().price_oracle(0)
        ) / 10 ** 8;
        assertEq(uint256(dolaUsdPrice), uint256(dolaPrice));
        assertEq(uint256(dolaUsdPrice), uint(feed.latestAnswer()));
    }

    function test_Frax_Out_of_bounds_MIN_return_use_pyUSD() public {
        (
            uint80 clRoundId,
            int256 fraxUsdPrice,
            uint clStartedAt,
            uint clUpdatedAt,
            uint80 clAnsweredInRound
        ) = feed.fraxToUsd().latestRoundData();

        // Out of MIN bounds Frax/USD price
        vm.mockCall(
            address(feed.fraxToUsd()),
            abi.encodeWithSelector(IChainlinkFeed.latestRoundData.selector),
            abi.encode(
                clRoundId,
                IAggregator(feed.fraxToUsd().aggregator()).minAnswer(),
                clStartedAt,
                clUpdatedAt,
                clAnsweredInRound
            )
        );

        (, int256 dolaUsdPrice, , uint updatedAt, ) = feed.latestRoundData();

        (, int256 pyUsdPrice, , uint256 updateAtPyUsd, ) = feed
            .pyUsdToUsd()
            .latestRoundData();

        assertEq(updateAtPyUsd, updatedAt);
        assertGt(updatedAt + dolaHeartbeat, block.timestamp);

        int dolaPrice = int(
            (feed.pyUSDFrax().get_virtual_price() *
                uint256(pyUsdPrice) *
                10 ** 18) / feed.crvDOLA().price_oracle(0)
        ) / 10 ** 8;
        assertEq(uint256(dolaUsdPrice), uint256(dolaPrice));
        assertEq(uint256(dolaUsdPrice), uint(feed.latestAnswer()));
    }

    function test_isPriceOutOfBounds() public {
        assertEq(feed.isPriceOutOfBounds(0, feed.pyUsdToUsd()), true);
        assertEq(feed.isPriceOutOfBounds(0, feed.fraxToUsd()), true);
        assertEq(
            feed.isPriceOutOfBounds(
                IAggregator(feed.pyUsdToUsd().aggregator()).maxAnswer(),
                feed.pyUsdToUsd()
            ),
            true
        );
        assertEq(
            feed.isPriceOutOfBounds(
                IAggregator(feed.fraxToUsd().aggregator()).maxAnswer(),
                feed.fraxToUsd()
            ),
            true
        );
    }

    function test_setPyUSDHeartbeat() public {
        assertEq(feed.pyUSDHeartbeat(), 86400);

        vm.expectRevert(DolaPriceFeed.OnlyGov.selector);
        feed.setPyUSDHeartbeat(100);
        assertEq(feed.pyUSDHeartbeat(), 86400);

        vm.prank(feed.gov());
        feed.setPyUSDHeartbeat(100);
        assertEq(feed.pyUSDHeartbeat(), 100);
    }

    function test_setFraxHeartbeat() public {
        assertEq(feed.fraxHeartbeat(), 3600);

        vm.expectRevert(DolaPriceFeed.OnlyGov.selector);
        feed.setFraxHeartbeat(100);
        assertEq(feed.fraxHeartbeat(), 3600);

        vm.prank(feed.gov());
        feed.setFraxHeartbeat(100);
        assertEq(feed.fraxHeartbeat(), 100);
    }

    function test_setGov() public {
        assertEq(feed.gov(), 0x926dF14a23BE491164dCF93f4c468A50ef659D5B);

        vm.expectRevert(DolaPriceFeed.OnlyGov.selector);
        feed.setGov(address(this));
        assertEq(feed.gov(), 0x926dF14a23BE491164dCF93f4c468A50ef659D5B);

        vm.prank(feed.gov());
        feed.setGov(address(this));
        assertEq(feed.gov(), address(this));
    }

    function _calculateOracleLpPrice()
        internal
        view
        returns (
            uint80 oracleRoundId,
            int256 oracleLpToUsdPrice,
            uint oracleStartedAt,
            uint oracleUpdatedAt,
            uint80 oracleAnsweredInRound
        )
    {
        int oracleMinToUsdPrice;

        (
            oracleRoundId,
            oracleMinToUsdPrice,
            oracleStartedAt,
            oracleUpdatedAt,
            oracleAnsweredInRound
        ) = feed.pyUsdToUsd().latestRoundData();

        (
            uint80 clRoundIdFrax,
            int256 clFraxToUsdPrice,
            uint clStartedAtFrax,
            uint clUpdatedAtFrax,
            uint80 clAnsweredInRoundFrax
        ) = feed.fraxToUsd().latestRoundData();

        if (oracleMinToUsdPrice < clFraxToUsdPrice) {
            oracleLpToUsdPrice =
                int(
                    (feed.pyUSDFrax().get_virtual_price() *
                        uint256(oracleMinToUsdPrice) *
                        10 ** 18) / feed.crvDOLA().price_oracle(0)
                ) /
                10 ** 8;
        } else {
            oracleRoundId = clRoundIdFrax;
            oracleMinToUsdPrice = clFraxToUsdPrice;
            oracleStartedAt = clStartedAtFrax;
            oracleUpdatedAt = clUpdatedAtFrax;
            oracleAnsweredInRound = clAnsweredInRoundFrax;

            oracleLpToUsdPrice =
                int(
                    (feed.pyUSDFrax().get_virtual_price() *
                        uint256(oracleMinToUsdPrice) *
                        10 ** 18) / feed.crvDOLA().price_oracle(0)
                ) /
                10 ** 8;
        }
    }
}
