pragma solidity ^0.8.13;

interface IERC20 {
    function transfer(address to, uint amount) external;
    function transferFrom(address from, address to, uint amount) external;
    function approve(address to, uint amount) external;
    function balanceOf(address user) external view returns(uint);
}

interface IMarket {
    function
}

abstract contract AbstractHelper {

    IERC20 DOLA;
    IERC20 DBR;
    
    /**
    Abstract functions
    */
    function getDbrPrice() public view returns(uint);

    function _buyExactDbr(uint amount) internal;

    function _sellExactDbr(uint amount) internal;

    function borrowOnBehalf(IMarket market, uint dolaAmount, uint duration, uint deadline, uint v, uint r, uint s) public {
        //Borrow Dola
        market.borrowOnBehalf(msg.sender, dolaAmount, deadline, v, r, s);
        
        //Buy DBR
        uint amountToBuy = dolaAmount * duration / 365 days;
        _buyExactDbr(amountToBuy);

        //Transfer remaining DBR and DOLA balance to user
        DOLA.transfer(msg.sender, DOLA.balanceOf(address(this));
        DBR.transfer(msg.sender, DBR.balanceOf(address(this));
    }

    function depositAndBorrowOnBehalf(IMarket market, uint collateralAmount, uint dolaAmount, uint duration, uint deadline, uint v, uint r, uint s) public {
        IERC20 collateral = market.collateral();

        //Deposit collateral
        collateral.transferFrom(msg.sender, address(this), collateralAmount);
        collateral.approve(market, collateralAmount);
        market.deposit(msg.sender, collateralAmount);

        //Borrow dola and buy dbr
        borrowOnBehalf(market, dolaAmunt, duration, deadline, v, r , s);

    }

    function sellDbrAndRepayOnBehalf(IMarket market, uint dolaAmount, uint dbrAmountToSell){
        uint dbrBal = DBR.balanceOf(msg.sender);
        if(dbrAmountToSell > dbrBal){
            _sellExactDbr(dbrBal);
        } else {
            _sellExactDbr(dbrAmountToSell);
        }
        uint dolaBal = DOLA.balanceOf(this);
        uint repayAmount = market.debts(msg.sender) < dolaAmount ? debt : dolaAmount;
        if(dolaBal < repayAmount){
            DOLA.transferFrom(msg.sender, address(this), repayAmount - DOLA.balanceOf(address(this)));
        else {
            DOLA.transfer(msg.sender, dolaBal - repayAmount);
        }
        market.repay(msg.sender, repayAmount);
    }

    function sellDbrRepayAndWithdrawOnBehalf(IMarket market, uint dolaAmount, uint dbrAmountToSell, uint collateralAmount, uint deadline, uint v, uint r, uint s){
        sellDbrAndRepayOnBehalf(market, dolaAmount, dbrAmountToSell);
        market.withdrawOnBehalf(msg.sender, collateralAmount, deadline, v, r, s);
        market.collateral().transfer(msg.sender, collateralAmount);
    }
}
