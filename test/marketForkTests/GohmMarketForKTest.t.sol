// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";

contract GohmMarketForkTest is MarketBaseForkTest {
    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, 18000000);
        //For non-deployed markets, instantiate market and feed after fork and use new contract addresses
        address marketAddr = 0x7Cd3ab8354289BEF52c84c2BF0A54E3608e66b37;
        address feedAddr = 0xe893297a9d4310976424fD0B25f53aC2B6464fe3;
        _advancedInit(marketAddr, feedAddr, false);
    }
}
