// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MarketBaseForkTest, IOracle, IDolaBorrowingRights, IERC20} from "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";

import {ConvexEscrowV2} from "src/escrows/ConvexEscrowV2.sol";
import {CurveLPPessimisticFeed} from "src/feeds/CurveLPPessimisticFeed.sol";
import {ChainlinkCurve2CoinsFeed, ICurvePool} from "src/feeds/ChainlinkCurve2CoinsFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {console} from "forge-std/console.sol";
import {YearnVaultV2Helper, IYearnVaultV2} from "src/util/YearnVaultV2Helper.sol";
import {DolaFixedPriceFeed} from "src/feeds/DolaFixedPriceFeed.sol";
import {ChainlinkBasePriceFeed} from "src/feeds/ChainlinkBasePriceFeed.sol";
import {MockFeedDescription} from "test/mocks/MockFeedDescription.sol";

contract DolaWstUSRConvexMarketForkTest is MarketBaseForkTest {
    ConvexEscrowV2 escrow;

    CurveLPPessimisticFeed feedDolaUSR;
    DolaFixedPriceFeed dolaFeed;

    ICurvePool public constant dolaWstUSR =
        ICurvePool(0x64273624eb57c5cA961d366CBF3968e760Bf0452);

    address usrWrapper = address(0x182Af82E3619D2182b3669BbFA8C72bC57614aDf); 

    address rewardPool = address(0x7F548ca54A86a326CE42772879338d429F14f048); 

    address booster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    uint256 pid = 496; 

    IERC20 public cvx = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public crv = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    ConvexEscrowV2 userEscrow;

    function setUp() public virtual {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        escrow = new ConvexEscrowV2(
            rewardPool,
            booster,
            address(cvx),
            address(crv),
            pid
        );
        feedDolaUSR = _deployDolaUSRFeed();
        market = new Market(
            gov,
            fedAddr,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbrAddr)),
            IERC20(address(dolaWstUSR)),
            IOracle(address(oracleAddr)),
            5000,
            5000,
            100,
            true
        );
        _advancedInit(address(market), address(feedDolaUSR), true);

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

    function _deployDolaUSRFeed()
        internal
        returns (CurveLPPessimisticFeed feed)
    {
        feed = new CurveLPPessimisticFeed(
            address(dolaWstUSR),
            address(usrWrapper),
            address(dolaFixedFeedAddr),
            false
        );
    }
}
