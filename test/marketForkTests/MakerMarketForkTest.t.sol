// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";
import "src/escrows/MakerEscrow.sol";

contract MakerMarketForkTest is MarketBaseForkTest {
    
    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        //For non-deployed markets, instantiate market and feed after fork and use new contract addresses
        MakerEscrow escrow = new MakerEscrow();
        IERC20 maker = IERC20(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2);
        Market market = new Market(gov, lender, pauseGuardian, address(escrow), IDolaBorrowingRights(address(dbr)), maker, IOracle(address(oracle)), 7500, 5000, 1000, true);
        address feedAddr = 0xec1D1B3b0443256cc3860e24a46F108e699484Aa ;
        _advancedInit(address(market), feedAddr, false);
    }
}
