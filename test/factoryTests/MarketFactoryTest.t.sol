pragma solidity ^0.8.20;


import "forge-std/Test.sol";
import "src/factory/MarketFactory.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";
contract MarketFactoryTest is Test, ConfigAddr {

    MarketFactory factory;
    address pendlePT = address(0xe6A934089BBEe34F832060CE98848359883749B3); // PT sUSDe 24 Nov 25
    function setUp() public {
        string memory rpcUrl = vm.rpcUrl('mainnet');
        vm.createSelectFork(rpcUrl);

        factory = new MarketFactory(gov, oracleAddr, fedAddr, pauseGuardian);
    }

    function test_deployment() public view {
        assertEq(gov, factory.gov());
        assertEq(oracleAddr, address(factory.oracle()));
        assertEq(fedAddr, factory.fed());
        assertEq(pauseGuardian, factory.pauseGuardian());
    }

    function test_market_deployment() public {
        address factoryMarket = factory.deployMarket(pendlePT, simpleERC20EscrowAddr, false);
        assertTrue(factory.isFromFactory(factoryMarket));

        Market pendleMarket = new Market(
            gov,
            fedAddr,
            pauseGuardian,
            simpleERC20EscrowAddr,
            IDolaBorrowingRights(address(dbrAddr)),
            IERC20(address(pendlePT)),
            IOracle(address(oracleAddr)),
            5000,
            5000,
            100,
            false
        );
        Market market = Market(factoryMarket); 

        assertEq(address(market.collateral()),address(pendleMarket.collateral()));
        assertEq(market.gov(),pendleMarket.gov());
        assertEq(market.lender(),pendleMarket.lender());
        assertEq(market.pauseGuardian(),pendleMarket.pauseGuardian());
        assertEq(market.escrowImplementation(), pendleMarket.escrowImplementation());
        assertEq(address(market.dbr()),address(pendleMarket.dbr()));
        assertEq(address(market.oracle()),address(pendleMarket.oracle()));
        assertEq(market.collateralFactorBps(),pendleMarket.collateralFactorBps());
        assertEq(market.replenishmentIncentiveBps(),pendleMarket.replenishmentIncentiveBps());
        assertEq(market.liquidationFactorBps(),pendleMarket.liquidationFactorBps());
    }

    function test_setPendingGov() public {
        address newGov = address(0x123);
        vm.prank(gov);
        factory.setPendingGov(newGov);
        assertEq(factory.pendingGov(), newGov);
    }

    function test_fail_setPendingGov_if_not_gov() public {
        address newGov = address(0x123);
        vm.expectRevert("Only gov");
        factory.setPendingGov(newGov);
    }

    function test_acceptGov() public {
        address newGov = address(0x123);
        vm.prank(gov);
        factory.setPendingGov(newGov);
        assertEq(factory.pendingGov(), newGov);

        vm.prank(newGov);
        factory.acceptGov();
        assertEq(factory.gov(), newGov);
        assertEq(factory.pendingGov(), address(0));
    }

    function test_fail_acceptGov_if_not_gov() public {
        address newGov = address(0x123);
        vm.prank(gov);
        factory.setPendingGov(newGov);
        assertEq(factory.pendingGov(), newGov);

        vm.expectRevert("Only pending gov");
        factory.acceptGov();
    }

    function test_setOracle() public {
        address newOracle = address(0x123);
        vm.prank(gov);
        factory.setOracle(newOracle);
        assertEq(address(factory.oracle()), newOracle);
    }

    function test_fail_setOracle_if_not_gov() public {
        address newOracle = address(0x123);
        vm.expectRevert("Only gov");
        factory.setOracle(newOracle);
    }

    function test_setFed() public {
        address newFed = address(0x123);
        vm.prank(gov);
        factory.setFed(newFed);
        assertEq(factory.fed(), newFed);
    }

    function test_fail_setFed_if_not_gov() public {
        address newFed = address(0x123);
        vm.expectRevert("Only gov");
        factory.setFed(newFed);
    }

    function test_setPauseGuardian() public {
        address newGuardian = address(0x123);
        vm.prank(gov);
        factory.setPauseGuardian(newGuardian);
        assertEq(factory.pauseGuardian(), newGuardian);
    }

    function test_fail_setGuardian_if_not_gov() public {
        address newGuardian = address(0x123);
        vm.expectRevert("Only gov");
        factory.setPauseGuardian(newGuardian);
    }
}