// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../BorrowController.sol";
import "../DBR.sol";
import "../Fed.sol";
import {SimpleERC20Escrow} from "../escrows/SimpleERC20Escrow.sol";
import "../Market.sol";
import "../Oracle.sol";

import "./mocks/ERC20.sol";
import "./mocks/WETH9.sol";
import {EthFeed} from "./mocks/EthFeed.sol";

contract FrontierV2Test is Test {
    //EOAs & Multisigs
    address user = address(0x69);
    address user2 = address(0x70);
    address gov = address(0xA);
    address chair = address(0xB);
    address pauseGuardian = address(0xB);

    //ERC-20s
    ERC20 DOLA;
    WETH9 WETH;

    //Frontier V2
    Oracle oracle;
    EthFeed ethFeed;
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

    function initialize(uint replenishmentPriceBps_, uint collateralFactorBps_, uint replenishmentIncentiveBps_, uint liquidationBonusBps_, bool callOnDepositCallback_) public {
        vm.label(user, "user");
        vm.label(user2, "user2");

        vm.startPrank(gov);
        DOLA = new ERC20("DOLA", "DOLA", 18);
        WETH = new WETH9();

        ethFeed = new EthFeed();

        oracle = new Oracle(gov);
        borrowController = new BorrowController(gov);
        escrowImplementation = new SimpleERC20Escrow();
        dbr = new DolaBorrowingRights(replenishmentPriceBps_, "DOLA Borrowing Rights", "DBR", gov);
        fed = new Fed(IDBR(address(dbr)), IDola(address(DOLA)), gov, chair);
        market = new Market(gov, address(fed), pauseGuardian, address(escrowImplementation), IDolaBorrowingRights(address(dbr)), IERC20(address(DOLA)), IERC20(address(WETH)), IOracle(address(oracle)), collateralFactorBps_, replenishmentIncentiveBps_, liquidationBonusBps_, callOnDepositCallback_);

        dbr.addMarket(address(market));
        oracle.setFeed(address(WETH), IChainlinkFeed(address(ethFeed)), 18);

        DOLA.addMinter(address(fed));
        vm.stopPrank();
    }

    //Helper functions
    function deposit(uint amount) internal {
        WETH.approve(address(market), amount);
        market.deposit(amount);
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
}