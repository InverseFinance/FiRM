pragma solidity ^0.8.13;
import "src/interfaces/IDolaBorrowingRights.sol";
import "src/interfaces/IBorrowController.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IOracle.sol";
import "src/interfaces/IEscrow.sol";

interface IMarket {
    function gov() external view returns(address);
    function lender() external view returns(address);
    function pauseGuardian() external view returns(address);
    function escrowImplementation() external view returns(address);
    function dbr() external view returns(IDolaBorrowingRights);
    function borrowController() external view returns(IBorrowController);
    function dola() external view returns(IERC20);
    function collateral() external view returns(IERC20);
    function oracle() external view returns(IOracle);
    function collateralFactorBps() external view returns(uint);
    function replenishmentIncentiveBps() external view returns(uint);
    function liquidationFeeBps() external view returns(uint);
    function liquidationFactorBps() external view returns(uint);
    function totalDebt() external view returns(uint);
    function callOnDepositCallback() external view returns(bool);
    function borrowPaused() external view returns(bool);
    function escrows(address borrower) external view returns(address);
    function debts(address borrower) external returns(uint);
    function nonces(address borrower) external returns(uint);
    function deposit(address msgSender, uint collateralAmount) external;
    function deposit(uint collateralAmount) external;
    function depositAndBorrow(uint amountDeposit, uint amountBorrow) external;
    function predictEscrow(address borrower) external view returns(IEscrow);
    function getCollateralValue(address borrower) external view returns(uint);
    function getCreditLimit(address borrower) external view returns(uint);
    function getWithdrawalLimit(address borrower) external view returns(uint);
    function borrow(uint amount) external;
    function borrowOnBehalf(address msgSender, uint dolaAmount, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    function withdraw(uint amount) external;
    function withdrawMax() external;
    function withdrawOnBehalf(address msgSender, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    function withdrawMaxOnBehalf(address msgSender, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    function invalidateNonce() external;
    function repay(address msgSender, uint amount) external;
    function repayAndWithdraw(uint repayAmount, uint withdrawAmount) external;
    function forceReplenish(address user, uint amount) external;
    function forceReplenishAll(address user) external;
    function liquidate(address user, uint repaidDebt) external;
    function recall(uint amount) external;
}

