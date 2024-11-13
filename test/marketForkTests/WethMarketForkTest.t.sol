// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";

interface WETH is IERC20 {
    function deposit() external payable;
}

contract WethMarketForkTest is MarketBaseForkTest {
    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        //For non-deployed markets, instantiate market and feed after fork and use new contract addresses
        address marketAddr = 0x63Df5e23Db45a2066508318f172bA45B9CD37035;
        address feedAddr = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
        _advancedInit(marketAddr, feedAddr, false);
    }

    function gibCollateral(
        address _address,
        uint _amount
    ) internal virtual override {
        deal(_address, _amount);
        vm.startPrank(_address);
        WETH(address(market.collateral())).deposit{value: _amount}();
        vm.stopPrank();
    }
}
