// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/Market.sol";

contract MarketFactory {
    IOracle public constant ORACLE = IOracle(0xaBe146CF570FD27ddD985895ce9B138a7110cce8);
    IDolaBorrowingRights public constant DBR = IDolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
    address public constant GOV = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    address public constant FED = address(0x2b34548b865ad66A2B046cb82e59eE43F75B90fd);
    address public constant PAUSE_GUARDIAN = address(0xE3eD95e130ad9E15643f5A5f232a3daE980784cd);
    uint256 public constant initialCollateralFactorBps = 5000;
    uint256 public constant initialReplenishmentIncentiveBps = 5000;
    uint256 public constant initialLiquidationIncentiveBps = 100;

    mapping(address => bool) public isFromFactory;

    event NewMarket(address collateral, address market);

    function deployMarket(address collateral, address escrowImpl, bool callbackOnDeposit)
        external
        returns (address market)
    {
        market = address(
            new Market(
                GOV,
                FED,
                PAUSE_GUARDIAN,
                escrowImpl,
                DBR,
                IERC20(collateral),
                ORACLE,
                initialCollateralFactorBps,
                initialReplenishmentIncentiveBps,
                initialLiquidationIncentiveBps,
                callbackOnDeposit
            )
        );
        isFromFactory[market] = true;
        emit NewMarket(collateral, market);
    }
}
