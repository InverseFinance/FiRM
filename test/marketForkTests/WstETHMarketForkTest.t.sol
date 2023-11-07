// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./MarketBaseForkTest.sol";
import {Market} from "src/Market.sol";
import {SimpleERC20Escrow} from "src/escrows/SimpleERC20Escrow.sol";
import {WstETHPriceFeed} from "src/feeds/WstETHPriceFeed.sol";

contract SFraxMarketForkTest is MarketBaseForkTest {
    SimpleERC20Escrow escrow;
    WstETHPriceFeed feedWstETH;
    IERC20 wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        escrow = new SimpleERC20Escrow();

        feedWstETH = new WstETHPriceFeed();

        Market market = new Market(
            gov,
            lender,
            pauseGuardian,
            address(escrow),
            IDolaBorrowingRights(address(dbr)),
            wstETH,
            IOracle(address(oracle)),
            5000,
            5000,
            1000,
            true
        );

        _advancedInit(address(market), address(feedWstETH), true);
    }
}