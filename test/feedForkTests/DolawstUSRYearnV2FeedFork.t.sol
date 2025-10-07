// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "src/feeds/ChainlinkBasePriceFeed.sol";
import {ChainlinkCurveFeed} from "src/feeds/ChainlinkCurveFeed.sol";
import "src/feeds/CurveLPPessimisticFeed.sol";
import {CurveLPYearnV2FeedBaseTest} from "test/feedForkTests/CurveLPYearnV2FeedBaseTest.t.sol";

contract DolawstUSRYearnV2FeedFork is CurveLPYearnV2FeedBaseTest {
     ICurvePool public constant dolawstUSR =
        ICurvePool(0x64273624eb57c5cA961d366CBF3968e760Bf0452); 
    
    address usrWrapper = address(0x182Af82E3619D2182b3669BbFA8C72bC57614aDf);

    address public constant yearnVault =
        address(0x8A5f20dA6B393fE25aCF1522C828166D22eF8321);

    CurveLPPessimisticFeed dolaWstUSRFeed;

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);

        dolaWstUSRFeed = new CurveLPPessimisticFeed(
            address(dolawstUSR),
            usrWrapper,
            dolaFixedFeedAddr,
            false
        );
        init(address(dolaWstUSRFeed), address(dolawstUSR), yearnVault);
    }
}
