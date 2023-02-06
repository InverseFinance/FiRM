pragma solidity ^0.8.13;
import "../interfaces/IMarket.sol";
interface IERC20 {
    function transfer(address to, uint amount) external;
    function transferFrom(address from, address to, uint amount) external;
    function approve(address to, uint amount) external;
    function balanceOf(address user) external view returns(uint);
}

abstract contract AbstractHelper {

    IERC20 DOLA;
    IERC20 DBR;

    constructor(address _dola, address _dbr){
        DOLA = IERC20(_dola);
        DBR = IERC20(_dbr);
    }
    
    /**
    Abstract functions
    */
    function _buyExactDbr(uint amount, uint maxIn) internal virtual;

    function _sellExactDbr(uint amount, uint minOut) internal virtual;

    function approximateDolaAndDbrNeeded(uint dolaBorrowAmount, uint period, uint iterations) public view virtual returns(uint, uint);

    function borrowOnBehalf(
        IMarket market, 
        uint dolaAmount,
        uint maxBorrow,
        uint duration,
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s) 
        public 
    {
        //Calculate DOLA needed to pay out dolaAmount + buying enough DBR to approximately sustain loan for the duration
        (uint dolaToBorrow, uint dbrNeeded) = approximateDolaAndDbrNeeded(dolaAmount, duration, 8);
        require(maxBorrow >= dolaToBorrow, "Cost of borrow exceeds max borrow");

        //Borrow Dola
        market.borrowOnBehalf(msg.sender, maxBorrow, deadline, v, r, s);
        
        //Buy DBR
        _buyExactDbr(dbrNeeded, maxBorrow - dolaAmount);

        //Transfer remaining DBR and DOLA amount to user
        DOLA.transfer(msg.sender, dolaAmount);
        DBR.transfer(msg.sender, DBR.balanceOf(address(this)));

        //Repay what remains of max borrow
        uint dolaBalance = DOLA.balanceOf(address(this));
        market.repay(msg.sender, dolaBalance);
    }

    function depositAndBorrowOnBehalf(
        IMarket market, 
        uint collateralAmount, 
        uint dolaAmount,
        uint maxBorrow,
        uint duration,
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s) 
        public 
    {
        IERC20 collateral = IERC20(market.collateral());

        //Deposit collateral
        collateral.transferFrom(msg.sender, address(this), collateralAmount);
        collateral.approve(address(market), collateralAmount);
        market.deposit(msg.sender, collateralAmount);

        //Borrow dola and buy dbr
        borrowOnBehalf(market, dolaAmount, maxBorrow, duration, deadline, v, r , s);

    }

    function sellDbrAndRepayOnBehalf(IMarket market, uint dolaAmount, uint minDolaFromDbr, uint dbrAmountToSell) public {
        uint dbrBal = DBR.balanceOf(msg.sender);

        //If user has less DBR than ordered, sell what's available
        if(dbrAmountToSell > dbrBal){
            DBR.transferFrom(msg.sender, address(this), dbrBal);
            _sellExactDbr(dbrBal, minDolaFromDbr);
        } else {
            DBR.transferFrom(msg.sender, address(this), dbrAmountToSell);
            _sellExactDbr(dbrAmountToSell, minDolaFromDbr);
        }

        uint debt = market.debts(msg.sender);
        uint dolaBal = DOLA.balanceOf(address(this));

        uint repayAmount = debt < dolaAmount ? debt : dolaAmount;

        //If dolaBal is less than repayAmount, transfer remaining DOLA from user, otherwise transfer excess dola to user
        if(dolaBal < repayAmount){
            require(repayAmount <= dolaAmount + dolaBal, "Repay amount exceeds dola amount");
            DOLA.transferFrom(msg.sender, address(this), repayAmount - DOLA.balanceOf(address(this)));
        } else {
            DOLA.transfer(msg.sender, dolaBal - repayAmount);
        }

        //Repay repayAmount
        DOLA.approve(address(market), repayAmount);
        market.repay(msg.sender, repayAmount);
    }

    function sellDbrRepayAndWithdrawOnBehalf(
        IMarket market, 
        uint dolaAmount, 
        uint minDolaOut,
        uint dbrAmountToSell, 
        uint collateralAmount, 
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s) 
        external 
    {
        //Repay
        sellDbrAndRepayOnBehalf(market, dolaAmount, minDolaOut, dbrAmountToSell);

        //Withdraw
        market.withdrawOnBehalf(msg.sender, collateralAmount, deadline, v, r, s);

        //Transfer collateral to msg.sender
        IERC20(market.collateral()).transfer(msg.sender, collateralAmount);
    }
}
