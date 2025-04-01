// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MarketBaseForkTest, IOracle, IDolaBorrowingRights, IERC20} from "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";

import {ConvexEscrowV2} from "src/escrows/ConvexEscrowV2.sol";
import {CurveLPPessimisticFeed} from "src/feeds/CurveLPPessimisticFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {console} from "forge-std/console.sol";
import {DolaFixedPriceFeed} from "src/feeds/DolaFixedPriceFeed.sol";

contract SDolascrvUSDConvexMarketForkTest is MarketBaseForkTest {
    ConvexEscrowV2 escrow;

    CurveLPPessimisticFeed feedsDolascrvUSD;
    DolaFixedPriceFeed dolaFeed;

    address clCrvUSDFeed = address(0xEEf0C605546958c1f899b6fB336C20671f9cD49F);
    uint256 crvUSDHeartbeat = 86400;
    address public constant sDolascrvUSD =
        address(0x76A962BA6770068bCF454D34dDE17175611e6637);

    address rewardPool = address(0x731868E273CDD4fC2dDC91c7E9553986355B5C3a);

    address booster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    uint256 pid = 400;

    IERC20 public cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    ConvexEscrowV2 userEscrow;

    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 21386890);
        escrow = new ConvexEscrowV2(
            rewardPool,
            booster,
            address(cvx),
            address(crv),
            pid
        );
        feedsDolascrvUSD = _deployDolascrvUSDFeed();
        market = new Market(
            gov,
            fedAddr,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbrAddr)),
            IERC20(address(sDolascrvUSD)),
            IOracle(address(oracleAddr)),
            5000,
            5000,
            1000,
            true
        );
        _advancedInit(address(market), address(feedsDolascrvUSD), true);

        userEscrow = ConvexEscrowV2(
            address(Market(address(market)).predictEscrow(user))
        );
    }

    function test_escrow_immutables() public {
        testDeposit();
        assertEq(
            address(userEscrow.rewardPool()),
            address(rewardPool),
            "Reward pool not set"
        );
        assertEq(
            address(userEscrow.booster()),
            address(booster),
            "Booster not set"
        );

        assertEq(address(userEscrow.cvx()), address(cvx), "CVX not set");
        assertEq(address(userEscrow.crv()), address(crv), "CRV not set");
    }

    function _deployDolascrvUSDFeed()
        internal
        returns (CurveLPPessimisticFeed feed)
    {
        ChainlinkBasePriceFeed scrvUSDFeed = new ChainlinkBasePriceFeed(
            gov,
            clCrvUSDFeed,
            address(0),
            crvUSDHeartbeat
        );
        feed = new CurveLPPessimisticFeed(
            address(sDolascrvUSD),
            address(scrvUSDFeed),
            address(dolaFixedFeedAddr),
            false
        );
    }
}
