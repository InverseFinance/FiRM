// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";
import {DolaFraxBPEscrow} from "src/escrows/DolaFraxBPEscrow.sol";
import {DolaFraxBPPriceFeed} from "src/feeds/DolaFraxBPPriceFeed.sol";

contract DolaFraxBPMarketForkTest is MarketBaseForkTest {
    DolaFraxBPEscrow escrow;
    DolaFraxBPPriceFeed feedDolaBP;
    IERC20 dolaFraxBP = IERC20(0xE57180685E3348589E9521aa53Af0BCD497E884d);

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 20020781);

        escrow = new DolaFraxBPEscrow();

        feedDolaBP = new DolaFraxBPPriceFeed();

        Market market = new Market(
            gov,
            lender,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbr)),
            dolaFraxBP,
            IOracle(address(oracle)),
            5000,
            5000,
            1000,
            true
        );

        _advancedInit(address(market), address(feedDolaBP), true);
    }
}
