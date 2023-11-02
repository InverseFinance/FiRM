// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {BorrowController} from "src/BorrowController.sol";
import "src/DBR.sol";
import {Fed, IMarket} from "src/Fed.sol";
import {IERC20, IMintable} from "src/interfaces/IERC20.sol";
import {IMarket} from "src/interfaces/IMarket.sol";
import {IEscrow, IBorrowController, IOracle, IDolaBorrowingRights} from "src/Market.sol";
import "src/Oracle.sol";

contract MarketForkTest is Test {
    //Market deployment:
    IMarket market;
    IChainlinkFeed feed;
    BorrowController borrowController;
    bool callOnDepositCallback = false;

    //EOAs & Multisigs
    address user = address(0x69);
    address user2 = address(0x70);
    address replenisher = address(0x71);
    address collatHolder = address(0xD292b72e5C787f9F7E092aB7802aDDF76930981F);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    address chair = address(0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8);
    address pauseGuardian = address(0xE3eD95e130ad9E15643f5A5f232a3daE980784cd);

    //ERC-20s
    IMintable DOLA;
    IERC20 collateral;

    //FiRM
    Oracle oracle = Oracle(0xaBe146CF570FD27ddD985895ce9B138a7110cce8);
    IEscrow escrowImplementation;
    DolaBorrowingRights dbr = DolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
    Fed fed;

    //Variables
    uint collateralFactorBps;
    uint replenishmentIncentiveBps;
    uint liquidationBonusBps;
    uint replenishmentPriceBps;

    uint testAmount = 1 ether;

    bytes onlyChair = "ONLY CHAIR";
    bytes onlyGov = "Only gov can call this function";
    bytes onlyLender = "Only lender can recall";
    bytes onlyOperator = "ONLY OPERATOR";

    function init(address _market, address _feed) public {
        DOLA = IMintable(0x865377367054516e17014CcdED1e7d814EDC9ce4);
        market = IMarket(_market);
        feed = IChainlinkFeed(_feed);
        borrowController = BorrowController(0x20C7349f6D6A746a25e66f7c235E96DAC880bc0D);
        replenishmentIncentiveBps = market.replenishmentIncentiveBps();
        liquidationBonusBps = market.liquidationIncentiveBps();
        replenishmentPriceBps = dbr.replenishmentPriceBps();

        //FiRM
        escrowImplementation = IEscrow(market.escrowImplementation());
        fed = Fed(market.lender());
        collateral = IERC20(address(market.collateral()));

        vm.label(user, "user");
        vm.label(user2, "user2");

        //Warp forward 7 days since local chain timestamp is 0, will cause revert when calculating `days` in oracle.
        vm.warp(block.timestamp + 7 days);

        vm.startPrank(gov, gov);
        market.setBorrowController(IBorrowController(address(borrowController)));
        borrowController.setDailyLimit(address(market), 250_000*1e18);
        dbr.addMarket(address(market));
        fed.changeMarketCeiling(IMarket(address(market)), type(uint).max);
        fed.changeSupplyCeiling(type(uint).max);
        oracle.setFeed(address(collateral), feed, 18);
        vm.stopPrank();

        collateralFactorBps = market.collateralFactorBps();
    }

    //Helper functions
    function deposit(uint amount) internal {
        collateral.approve(address(market), amount);
        market.deposit(amount);
    }

    function deposit(uint amount, address depositor) internal {
        gibCollateral(depositor, amount);
        vm.startPrank(depositor);
        collateral.approve(address(market), amount);
        market.deposit(amount);
        vm.stopPrank();
    }

    function convertCollatToDola(uint amount) public view returns (uint) {
        (,int latestAnswer,,,) = feed.latestRoundData();
        return amount * uint(latestAnswer) / 10**feed.decimals();
    }

    function convertDolaToCollat(uint amount) public view returns (uint) {
        (,int latestAnswer,,,) = feed.latestRoundData();
        return amount * 10**feed.decimals() / uint(latestAnswer);
    }

    function getMaxBorrowAmount(uint amountCollat) public view returns (uint) {
        return convertCollatToDola(amountCollat) * market.collateralFactorBps() / 10_000;
    }

    function gibCollateral(address _address, uint _amount) internal virtual {
        deal(address(collateral), _address, _amount, true);
    }

    function gibDBR(address _address, uint _amount) internal {
        vm.prank(gov);
        dbr.mint(_address, _amount);
    }

    function gibDOLA(address _address, uint _amount) internal {
        vm.prank(gov);
        DOLA.mint(_address, _amount);
    }
}
