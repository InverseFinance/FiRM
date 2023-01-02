pragma solidity ^0.8.13;

interface IERC20 {
    function transfer(address to, uint amount) external;
    function transferFrom(address from, address to, uint amount) external;
    function approve(address to, uint amount) external;
    function balanceOf(address user) external view returns(uint);
}

interface IMarket {
    function borrowOnBehalf(address msgSender, uint dolaAmount, uint deadline, uint v, uint r, uint s) external;
    function withdrawOnBehalf(address msgSender, uint amount, uint deadline, uint v, uint r, uint s) external;
    function deposit(address msgSender, uint collateralAmount) external;
    function repay(address msgSender, uint amount) external;
    function collateral() external returns(address);
    function debts(address user) external returns(uint);
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
    function getDbrPrice() public virtual view returns(uint);

    function _buyExactDbr(uint amount) internal virtual;

    function _sellExactDbr(uint amount) internal virtual;

    function borrowOnBehalf(
        IMarket market, 
        uint dolaAmount, 
        uint duration, 
        uint deadline, 
        uint v, 
        uint r, 
        uint s) 
        public 
    {
        //Borrow Dola
        market.borrowOnBehalf(msg.sender, dolaAmount, deadline, v, r, s);
        
        //Buy DBR
        uint amountToBuy = dolaAmount * duration / 365 days;
        _buyExactDbr(amountToBuy);

        //Transfer remaining DBR and DOLA balance to user
        DOLA.transfer(msg.sender, DOLA.balanceOf(address(this)));
        DBR.transfer(msg.sender, DBR.balanceOf(address(this)));
    }

    function depositAndBorrowOnBehalf(
        IMarket market, 
        uint collateralAmount, 
        uint dolaAmount, 
        uint duration, 
        uint deadline, 
        uint v, 
        uint r, 
        uint s) 
        public 
    {
        IERC20 collateral = IERC20(market.collateral());

        //Deposit collateral
        collateral.transferFrom(msg.sender, address(this), collateralAmount);
        collateral.approve(address(market), collateralAmount);
        market.deposit(msg.sender, collateralAmount);

        //Borrow dola and buy dbr
        borrowOnBehalf(market, dolaAmount, duration, deadline, v, r , s);

    }

    function sellDbrAndRepayOnBehalf(IMarket market, uint dolaAmount, uint dbrAmountToSell) public {
        uint dbrBal = DBR.balanceOf(msg.sender);

        //If user has less DBR than ordered, sell what's available
        if(dbrAmountToSell > dbrBal){
            _sellExactDbr(dbrBal);
        } else {
            _sellExactDbr(dbrAmountToSell);
        }

        uint debt = market.debts(msg.sender);
        uint dolaBal = DOLA.balanceOf(address(this));

        //Repay user's entire debt if less than dolaAmount, otherwise repay dolaAmount
        uint repayAmount = market.debts(msg.sender) < dolaAmount ? debt : dolaAmount;

        //If dolaBal is less than repayAmount, transfer remaining DOLA from user, otherwise transfer excess dola to user
        if(dolaBal < repayAmount){
            DOLA.transferFrom(msg.sender, address(this), repayAmount - DOLA.balanceOf(address(this)));
        } else {
            DOLA.transfer(msg.sender, dolaBal - repayAmount);
        }

        //Repay repayAmount
        market.repay(msg.sender, repayAmount);
    }

    function sellDbrRepayAndWithdrawOnBehalf(
        IMarket market, 
        uint dolaAmount, 
        uint dbrAmountToSell, 
        uint collateralAmount, 
        uint deadline, 
        uint v, 
        uint r, 
        uint s) 
        external 
    {
        //Repay
        sellDbrAndRepayOnBehalf(market, dolaAmount, dbrAmountToSell);

        //Withdraw
        market.withdrawOnBehalf(msg.sender, collateralAmount, deadline, v, r, s);

        //Transfer collateral to msg.sender
        IERC20(market.collateral()).transfer(msg.sender, collateralAmount);
    }
}
