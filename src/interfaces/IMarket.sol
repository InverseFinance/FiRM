pragma solidity ^0.8.13;

import {IBorrowController, IEscrow, IOracle} from "src/Market.sol";

interface IMarket {
    function borrow(uint borrowAmount) external;

    function borrowOnBehalf(
        address msgSender,
        uint dolaAmount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function withdraw(uint amount) external;

    function withdrawMax() external;

    function withdrawOnBehalf(
        address msgSender,
        uint amount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function deposit(uint amount) external;

    function deposit(address msgSender, uint collateralAmount) external;

    function depositAndBorrow(
        uint collateralAmount,
        uint borrowAmount
    ) external;

    function repay(address msgSender, uint amount) external;

    function liquidate(address borrower, uint liquidationAmount) external;

    function forceReplenish(address borrower, uint deficitBefore) external;

    function collateral() external returns (address);

    function debts(address user) external returns (uint);

    function recall(uint amount) external;

    function invalidateNonce() external;

    function pauseBorrows(bool paused) external;

    function setBorrowController(IBorrowController borrowController) external;

    function escrows(address user) external view returns (IEscrow);

    function predictEscrow(address user) external view returns (IEscrow);

    function getCollateralValue(address user) external view returns (uint);

    function getWithdrawalLimit(address user) external view returns (uint);

    function getCreditLimit(address user) external view returns (uint);

    function lender() external view returns (address);

    function borrowController() external view returns (address);

    function escrowImplementation() external view returns (address);

    function totalDebt() external view returns (uint);

    function borrowPaused() external view returns (bool);

    function replenishmentIncentiveBps() external view returns (uint);

    function liquidationIncentiveBps() external view returns (uint);

    function collateralFactorBps() external view returns (uint);

    function setCollateralFactorBps(uint cfBps) external;

    function setOracle(IOracle oracle) external;

    function setGov(address newGov) external;

    function setLender(address newLender) external;

    function setPauseGuardian(address newPauseGuardian) external;

    function setReplenismentIncentiveBps(uint riBps) external;

    function setLiquidationIncentiveBps(uint liBps) external;

    function setLiquidationFactorBps(uint lfBps) external;

    function setLiquidationFeeBps(uint lfeeBps) external;

    function liquidationFeeBps() external view returns (uint);

    function DOMAIN_SEPARATOR() external view returns (uint);

    function oracle() external view returns (address);

    function escrows(address) external view returns (address);
}
