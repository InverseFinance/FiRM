// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {BorrowController} from "src/BorrowController.sol";
import "src/DBR.sol";
import "src/Fed.sol";
import {SimpleERC20Escrow} from "src/escrows/SimpleERC20Escrow.sol";
import "src/Market.sol";
import "src/Oracle.sol";

import "test/mocks/ERC20.sol";
import "test/mocks/WETH9.sol";
import {MockFeed} from "test/mocks/MockFeed.sol";

contract FiRMBaseTest is Test {
    //EOAs & Multisigs
    address user = address(0x69);
    address user2 = address(0x70);
    address replenisher = address(0x71);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    address chair = address(0xB);
    address pauseGuardian = address(0xB);

    //ERC-20s
    ERC20 DOLA;
    WETH9 WETH;
    ERC20 wBTC;

    //Frontier V2
    Oracle oracle;
    MockFeed ethFeed;
    MockFeed wbtcFeed;
    MockFeed dolaFeed;
    BorrowController borrowController;
    SimpleERC20Escrow escrowImplementation;
    DolaBorrowingRights dbr;
    Market market;
    Fed fed;

    //Constants
    uint collateralFactorBps = 8500;
    uint replenishmentIncentiveBps = 500;
    uint liquidationBonusBps = 100;
    bool callOnDepositCallback = false;

    uint replenishmentPriceBps = 10000;

    uint wethTestAmount = 1 ether;

    bytes onlyChair = "ONLY CHAIR";
    bytes onlyGov = "Only gov can call this function";
    bytes onlyLender = "Only lender can recall";
    bytes onlyOperator = "ONLY OPERATOR";

    function initialize(
        uint replenishmentPriceBps_,
        uint collateralFactorBps_,
        uint replenishmentIncentiveBps_,
        uint liquidationBonusBps_,
        bool callOnDepositCallback_
    ) public {
        vm.label(user, "user");
        vm.label(user2, "user2");

        //Warp forward 7 days since local chain timestamp is 0, will cause revert when calculating `days` in oracle.
        vm.warp(block.timestamp + 7 days);

        //This is done to make DOLA live at a predetermined address so it does not need to be included in constructor
        DOLA = new ERC20("DOLA", "DOLA", 18);
        bytes memory code = codeAt(address(DOLA));
        vm.etch(0x865377367054516e17014CcdED1e7d814EDC9ce4, code);
        DOLA = ERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
        vm.startPrank(DOLA.operator());
        DOLA.setPendingOperator(gov);
        vm.stopPrank();

        vm.startPrank(gov, gov);
        DOLA.claimOperator();
        WETH = new WETH9();
        wBTC = new ERC20("WBTC", "WRAPPED BITCOIN", 8);

        ethFeed = new MockFeed(18, 2000e18);
        wbtcFeed = new MockFeed(8, 30000e8);
        dolaFeed = new MockFeed(20, 1e20);
        oracle = new Oracle(gov);
        escrowImplementation = new SimpleERC20Escrow();
        dbr = new DolaBorrowingRights(
            replenishmentPriceBps_,
            "DOLA Borrowing Rights",
            "DBR",
            gov
        );
        borrowController = new BorrowController(gov, address(dbr));
        fed = new Fed(
            IDBR(address(dbr)),
            IDola(address(DOLA)),
            gov,
            chair,
            type(uint).max
        );
        market = new Market(
            gov,
            address(fed),
            pauseGuardian,
            address(escrowImplementation),
            IDolaBorrowingRights(address(dbr)),
            IERC20(address(WETH)),
            IOracle(address(oracle)),
            collateralFactorBps_,
            replenishmentIncentiveBps_,
            liquidationBonusBps_,
            callOnDepositCallback_
        );
        borrowController.setStalenessThreshold(address(market), 3600 * 24);
        fed.changeMarketCeiling(IMarket(address(market)), type(uint).max);
        market.setBorrowController(
            IBorrowController(address(borrowController))
        );

        dbr.addMarket(address(market));
        oracle.setFeed(address(WETH), IChainlinkFeed(address(ethFeed)), 18);
        oracle.setFeed(address(wBTC), IChainlinkFeed(address(wbtcFeed)), 8);
        oracle.setFeed(address(DOLA), IChainlinkFeed(address(dolaFeed)), 18);
        DOLA.addMinter(address(fed));
        vm.stopPrank();
        vm.prank(chair);
        fed.expansion(IMarket(address(market)), 1 ether);
    }

    //Helper functions
    function deposit(uint amount) internal {
        WETH.approve(address(market), amount);
        market.deposit(amount);
    }

    function convertWethToDola(uint amount) public view returns (uint) {
        return (amount * ethFeed.latestAnswer()) / 1e18;
    }

    function convertDolaToWeth(uint amount) public view returns (uint) {
        return (amount * 1e18) / ethFeed.latestAnswer();
    }

    function getMaxBorrowAmount(uint amountWeth) public view returns (uint) {
        return
            (convertWethToDola(amountWeth) * market.collateralFactorBps()) /
            10_000;
    }

    function gibWeth(address _address, uint _amount) internal {
        vm.deal(_address, _amount);
        vm.startPrank(_address);
        WETH.deposit{value: _amount}();
        vm.stopPrank();
    }

    function gibDBR(address _address, uint _amount) internal {
        vm.startPrank(gov);
        dbr.mint(_address, _amount);
        vm.stopPrank();
    }

    function gibDOLA(address _address, uint _amount) internal {
        bytes32 slot;
        assembly {
            mstore(0, _address)
            mstore(0x20, 0x6)
            slot := keccak256(0, 0x40)
        }

        vm.store(address(DOLA), slot, bytes32(_amount));
    }

    function codeAt(address _addr) public view returns (bytes memory o_code) {
        assembly {
            // retrieve the size of the code, this needs assembly
            let size := extcodesize(_addr)
            // allocate output byte array - this could also be done without assembly
            // by using o_code = new bytes(size)
            o_code := mload(0x40)
            // new "memory end" including padding
            mstore(
                0x40,
                add(o_code, and(add(add(size, 0x20), 0x1f), not(0x1f)))
            )
            // store length in memory
            mstore(o_code, size)
            // actually retrieve the code, this needs assembly
            extcodecopy(_addr, add(o_code, 0x20), 0, size)
        }
    }
}
