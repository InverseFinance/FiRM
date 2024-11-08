// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./MarketBaseForkTest.sol";
import "src/Market.sol";
import {GovTokenEscrow} from "src/escrows/GovTokenEscrow.sol";

contract CompMarketForkTest is MarketBaseForkTest {
    
    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        //For non-deployed markets, instantiate market and feed after fork and use new contract addresses
        address escrow = address(new GovTokenEscrow());
        address feedAddr = 0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5;
        address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
        address lender = 0x2b34548b865ad66A2B046cb82e59eE43F75B90fd;
        address pauseGuardian = 0xE3eD95e130ad9E15643f5A5f232a3daE980784cd;
        IDolaBorrowingRights dbr = IDolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
        IERC20 comp = IERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
        IOracle oracle = IOracle(0xaBe146CF570FD27ddD985895ce9B138a7110cce8);

        address marketAddr = address(new Market(gov, lender, pauseGuardian, escrow, dbr, comp, oracle, 5000, 1000, 1000, false));
        _advancedInit(marketAddr, feedAddr, false);
    }
}
