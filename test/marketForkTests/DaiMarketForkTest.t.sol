// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";

contract DaiMarketForkTest is MarketBaseForkTest {
    
    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        //For non-deployed markets, instantiate market and feed after fork and use new contract addresses
        address marketAddr = 0x0971B1690d101169BFca4715897aD3a9b3C39b26;
        address feedAddr = 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9;
        _advancedInit(marketAddr, feedAddr, true);
    }
}
