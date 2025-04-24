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

contract SDolaReUSDConvexMarketForkTest is MarketBaseForkTest {
    ConvexEscrowV2 escrow;

    CurveLPPessimisticFeed feedSDolaReUSD;
    DolaFixedPriceFeed dolaFeed;

    address rewardPool = address(0x2042468f1D356F78717818531958d744114347B4);

    address booster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    uint256 pid = 446;

    IERC20 public cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    ConvexEscrowV2 userEscrow;

    address public constant baseCrvUSDFeed = address(0x237C421F396216d0869F5177c11E40e7F043b6d2);
    uint256 public assetOrTargetK = 0;
    uint256 public targetIndex = 0;
    address public reUSDsDola = address(0x48d670D189B4b48757992D36897bCa6E3f889040);
    address public reUSDscrvUSD = address(0xc522A6606BBA746d7960404F22a3DB936B6F4F50);
    address public reUSD = address(0x57aB1E0003F623289CD798B1824Be09a793e4Bec);
    ChainlinkCurveFeed reUSDFeed;
    address convexEscrow = address(0x6BCaA8f153D81fD0827d21c6a0DF96410eb7646B);
    address lpFeed = address(0x8c8A46bbaad08c3b90EEb687cA6E25aBb9203561);
    address marketAddr = address(0x79779cF928EF35d7B4Ec071A39D6ECdB233e5E2d);

    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
      
        _advancedInit(marketAddr, lpFeed, true);

        userEscrow = ConvexEscrowV2(
            address(Market(marketAddr).predictEscrow(user))
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

    function _deploySDolaReUSDFeed()
        internal
        returns (CurveLPPessimisticFeed feed)
    {
        reUSDFeed = new ChainlinkCurveFeed(
            baseCrvUSDFeed,
            reUSDscrvUSD,
            assetOrTargetK,
            targetIndex
        );

        feed = new CurveLPPessimisticFeed(
            address(reUSDsDola),
            address(reUSDFeed),
            address(dolaFixedFeedAddr),
            false
        );
    }
}
