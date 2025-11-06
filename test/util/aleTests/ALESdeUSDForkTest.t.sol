// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/marketForkTests/SdeUSDMarketForkTest.t.sol";
import "test/util/aleTests/ALEV2BaseSimpleForkTest.t.sol";
import "src/DBR.sol";
import "test/mocks/ERC20.sol";

contract ALESdeUSDForkTest is SdeUSDMarketForkTest, ALEV2BaseSimpleForkTest {
    function setUp() public override {
        super.setUp();

        exchangeProxy = new MockExchangeProxy(
            address(market.oracle()),
            address(DOLA)
        );
        ale = new ALEV2(newTriDBRAddr, gov);
        
        // ALE setup
        vm.startPrank(gov);
      
        DOLA.addMinter(address(ale));
        borrowController.allow(address(ale));
        vm.stopPrank();
        ale.allowProxy(address(exchangeProxy));
       
        ale.setMarket(
            address(market),
            address(market.collateral()),
            address(0),
            true
        );
        
    }
}
