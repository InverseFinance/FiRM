// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/marketForkTests/SdeUSDMarketForkTest.t.sol";
import "test/util/aleTests/ALEBaseSimpleForkTest.t.sol";
import "src/DBR.sol";
import "test/mocks/ERC20.sol";

contract ALESdeUSDForkTest is SdeUSDMarketForkTest, ALEBaseSimpleForkTest {
    function setUp() public override {
        super.setUp();

        exchangeProxy = new MockExchangeProxy(
            address(market.oracle()),
            address(DOLA)
        );

        ale = new ALE(address(exchangeProxy), triDBR);
        // ALE setup
        vm.startPrank(gov);
        DOLA.addMinter(address(ale));
        borrowController.allow(address(ale));
        vm.stopPrank();

        ale.setMarket(
            address(market),
            address(market.collateral()),
            address(0),
            true
        );
    }
}
