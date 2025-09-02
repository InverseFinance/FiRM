pragma solidity ^0.8.20;


import "forge-std/Test.sol";
import "src/factory/PTUSDeFeedSwitchFactory.sol";
import {ConfigAddr} from "test/ConfigAddr.sol";
contract PTUSDeFeedSwitchFactoryTest is Test, ConfigAddr {

    PTUSDeFeedSwitchFactory factory;
    uint256 timelockPeriod = 18 hours;
    address pendlePT = address(0xe6A934089BBEe34F832060CE98848359883749B3); // PT sUSDe 24 Nov 25
    address pendlePTsUSDe = address(0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7); // PT USDe 27 Nov 25
    address guardian = address(0x4b6c63E6a94ef26E2dF60b89372db2d8e211F1B7); 
    address usdeWrappedFeed = address(0xB3C1D801A02d88adC96A294123c2Daa382345058); // USDe/USD wrapper
    uint256 baseDiscount = 0.2 ether;
    address sUSDeWrapper = address(0xD723a0910e261de49A90779d38A94aFaAA028F15);
    address sUSDe = address(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
    function setUp() public {
        string memory rpcUrl = vm.rpcUrl('mainnet');
        vm.createSelectFork(rpcUrl);

        factory = new PTUSDeFeedSwitchFactory(gov, guardian, timelockPeriod);
    }

    function test_deployment() public view {
        assertEq(gov, factory.gov());
        assertEq(timelockPeriod, factory.timelockPeriod());
        assertEq(guardian, factory.guardian());
    }

    function test_PT_USDe_deployment() public {
        address factoryFeed = factory.deployUSDeFeed(pendlePT, baseDiscount);
        assertTrue(factory.isFromFactory(factoryFeed));

        address navFeed = address(new PendleNAVFeed(pendlePT, baseDiscount));
        address beforeMaturityFeed = address(new NavBeforeMaturityFeed(
            address(usdeWrappedFeed),
            address(navFeed)
        ));

        FeedSwitch feedSwitch = new FeedSwitch(
            navFeed,
            beforeMaturityFeed,
            usdeWrappedFeed,
            18 hours,
            pendlePT,
            guardian
        );

        FeedSwitch feed = FeedSwitch(factoryFeed);

        assertEq(PendleNAVFeed(address(feed.initialFeed())).PT(), PendleNAVFeed(address(feedSwitch.initialFeed())).PT());
        assertEq(PendleNAVFeed(address(feed.initialFeed())).maturity(), PendleNAVFeed(address(feedSwitch.initialFeed())).maturity());
        assertEq(PendleNAVFeed(address(feed.initialFeed())).baseDiscountPerYear(), PendleNAVFeed(address(feedSwitch.initialFeed())).baseDiscountPerYear());
        assertEq(address(NavBeforeMaturityFeed(address(feed.beforeMaturityFeed())).feed()), address(NavBeforeMaturityFeed(address(feedSwitch.beforeMaturityFeed())).feed()));
        assertEq(address(NavBeforeMaturityFeed(address(feed.beforeMaturityFeed())).navFeed()),address(feed.initialFeed()));
        assertEq(address(feed.afterMaturityFeed()), address(feedSwitch.afterMaturityFeed()));
        assertEq(feed.timelockPeriod(), feedSwitch.timelockPeriod());
        assertEq(feed.guardian(), feedSwitch.guardian());
    }

    function test_PT_sUSDe_deployment() public {
        address factoryFeed = factory.deploySUSDeFeed(pendlePTsUSDe, baseDiscount);
        assertTrue(factory.isFromFactory(factoryFeed));

        address navFeed = address(new PendleNAVFeed(pendlePTsUSDe, baseDiscount)); 
        address beforeMaturityFeed = address(new USDeNavBeforeMaturityFeed(
            sUSDeWrapper,
            sUSDe,
            address(navFeed)
        ));
        FeedSwitch feedSwitch = new FeedSwitch(
            navFeed,
            beforeMaturityFeed,
            usdeWrappedFeed,
            18 hours,
            pendlePTsUSDe,
            guardian
        );

        FeedSwitch feed = FeedSwitch(factoryFeed);

        assertEq(PendleNAVFeed(address(feed.initialFeed())).PT(), PendleNAVFeed(address(feedSwitch.initialFeed())).PT());
        assertEq(PendleNAVFeed(address(feed.initialFeed())).maturity(), PendleNAVFeed(address(feedSwitch.initialFeed())).maturity());
        assertEq(PendleNAVFeed(address(feed.initialFeed())).baseDiscountPerYear(), PendleNAVFeed(address(feedSwitch.initialFeed())).baseDiscountPerYear());
        assertEq(address(USDeNavBeforeMaturityFeed(address(feed.beforeMaturityFeed())).sUSDe()), address(USDeNavBeforeMaturityFeed(address(feedSwitch.beforeMaturityFeed())).sUSDe()));
        assertEq(address(USDeNavBeforeMaturityFeed(address(feed.beforeMaturityFeed())).sUSDeFeed()), address(USDeNavBeforeMaturityFeed(address(feedSwitch.beforeMaturityFeed())).sUSDeFeed()));
        assertEq(address(USDeNavBeforeMaturityFeed(address(feed.beforeMaturityFeed())).navFeed()),address(feed.initialFeed()));
        assertEq(address(feed.afterMaturityFeed()), address(feedSwitch.afterMaturityFeed()));
        assertEq(feed.timelockPeriod(), feedSwitch.timelockPeriod());
        assertEq(feed.guardian(), feedSwitch.guardian());
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


    function test_setTimelockPeriod() public {
        uint256 newTimelockPeriod = 1 days;
        vm.prank(gov);
        factory.setTimelockPeriod(newTimelockPeriod);
        assertEq(factory.timelockPeriod(), newTimelockPeriod);
    }

    function test_fail_setTimelockPeriod_if_not_gov() public {
        uint256 newTimelockPeriod = 1 days;
        vm.expectRevert("Only gov");
        factory.setTimelockPeriod(newTimelockPeriod);
    }

    function test_setGuardian() public {
        address newGuardian = address(0x123);
        vm.prank(gov);
        factory.setGuardian(newGuardian);
        assertEq(factory.guardian(), newGuardian);
    }

    function test_fail_setGuardian_if_not_gov() public {
        address newGuardian = address(0x123);
        vm.expectRevert("Only gov");
        factory.setGuardian(newGuardian);
    }
}