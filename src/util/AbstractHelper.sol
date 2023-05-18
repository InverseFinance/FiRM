pragma solidity ^0.8.13;
import "src/interfaces/IMarket.sol";
import "src/interfaces/IERC20.sol";

interface IWETH is IERC20 {
    function withdraw(uint wad) external;
    function deposit() external payable;
}

abstract contract AbstractHelper {

    IERC20 constant DOLA = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 constant DBR = IERC20(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
    IWETH constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    
    /**
    Virtual functions implemented by the AMM interfacing part of the Helper contract
    */

    /**
    @notice Buys an exact amount of DBR for DOLA
    @param amount Amount of DBR to receive
    @param maxIn maximum amount of DOLA to put in
    */
    function _buyExactDbr(uint amount, uint maxIn) internal virtual;

    /**
    @notice Sells an exact amount of DBR for DOLA
    @param amount Amount of DBR to sell
    @param minOut minimum amount of DOLA to receive
    */
    function _sellExactDbr(uint amount, uint minOut) internal virtual;

    /**
    @notice Approximates the amount of additional DOLA and DBR needed to sustain dolaBorrowAmount over the period
    @dev Larger number of iterations increases both accuracy of the approximation and gas cost. Will always undershoot actual DBR amount needed.
    @param dolaBorrowAmount The amount of DOLA the user wishes to borrow before covering DBR expenses
    @param period The amount of seconds the user wish to borrow the DOLA for
    @param iterations The amount of approximation iterations.
    @return Tuple of (dolaNeeded, dbrNeeded) representing the total dola needed to pay for the DBR and pay out dolaBorrowAmount and the dbrNeeded to sustain the loan over the period
    */
    function approximateDolaAndDbrNeeded(uint dolaBorrowAmount, uint period, uint iterations) public view virtual returns(uint, uint);

    /**
    @notice Borrows on behalf of the caller, buying the necessary DBR to pay for the loan over the period, by borrowing aditional funds to pay for the necessary DBR
    @dev Has to borrow the maxDebt amount due to how the market's borrowOnBehalf functions, and repay the excess at the end of the call resulting in a weird repay event
    @param market Market the caller wishes to borrow from
    @param dolaAmount Amount the caller wants to end up with at their disposal
    @param maxDebt The max amount of debt the caller is willing to end up with
     This is a sensitive parameter and should be reasonably low to prevent sandwhiching.
     A good estimate can be calculated given the approximateDolaAndDbrNeeded function, though should be set slightly higher.
    @param duration The duration the caller wish to borrow for
    @param deadline Deadline of the signature
    @param v V parameter of the signature
    @param r R parameter of the signature
    @param s S parameter of the signature
    */
    function buyDbrAndBorrowOnBehalf(
        IMarket market, 
        uint dolaAmount,
        uint maxDebt,
        uint duration,
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s) 
        public 
    {
        //Calculate DOLA needed to pay out dolaAmount + buying enough DBR to approximately sustain loan for the duration
        (uint dolaToBorrow, uint dbrNeeded) = approximateDolaAndDbrNeeded(dolaAmount, duration, 8);
        require(maxDebt >= dolaToBorrow, "Cost of borrow exceeds max borrow");

        //Borrow Dola
        market.borrowOnBehalf(msg.sender, maxDebt, deadline, v, r, s);
        
        //Buy DBR
        _buyExactDbr(dbrNeeded, maxDebt - dolaAmount);

        //Transfer remaining DBR and DOLA amount to user
        DOLA.transfer(msg.sender, dolaAmount);
        DBR.transfer(msg.sender, dbrNeeded);

        //Repay what remains of max borrow
        uint dolaBalance = DOLA.balanceOf(address(this));
        DOLA.approve(address(market), dolaBalance);
        market.repay(msg.sender, dolaBalance);
    }

    /**
    @notice Deposits collateral and borrows on behalf of the caller, buying the necessary DBR to pay for the loan over the period, by borrowing aditional funds to pay for the necessary DBR
    @dev Has to borrow the maxDebt amount due to how the market's borrowOnBehalf functions, and repay the excess at the end of the call resulting in a weird repay event
    @param market Market the caller wish to deposit to and borrow from
    @param dolaAmount Amount the caller wants to end up with at their disposal
    @param maxDebt The max amount of debt the caller is willing to end up with
     This is a sensitive parameter and should be reasonably low to prevent sandwhiching.
     A good estimate can be calculated given the approximateDolaAndDbrNeeded function, though should be set slightly higher.
    @param duration The duration the caller wish to borrow for
    @param deadline Deadline of the signature
    @param v V parameter of the signature
    @param r R parameter of the signature
    @param s S parameter of the signature
    */
    function depositBuyDbrAndBorrowOnBehalf(
        IMarket market, 
        uint collateralAmount, 
        uint dolaAmount,
        uint maxDebt,
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
        buyDbrAndBorrowOnBehalf(market, dolaAmount, maxDebt, duration, deadline, v, r , s);
    }

    /**
    @notice Deposits native eth as collateral and borrows on behalf of the caller,
    buying the necessary DBR to pay for the loan over the period, by borrowing aditional funds to pay for the necessary DBR
    @dev Has to borrow the maxDebt amount due to how the market's borrowOnBehalf functions, and repay the excess at the end of the call resulting in a weird repay event
    @param market Market the caller wish to deposit to and borrow from
    @param dolaAmount Amount the caller wants to end up with at their disposal
    @param maxDebt The max amount of debt the caller is willing to end up with
     This is a sensitive parameter and should be reasonably low to prevent sandwhiching.
     A good estimate can be calculated given the approximateDolaAndDbrNeeded function, though should be set slightly higher.
    @param duration The duration the caller wish to borrow for
    @param deadline Deadline of the signature
    @param v V parameter of the signature
    @param r R parameter of the signature
    @param s S parameter of the signature
    */
    function depositNativeEthBuyDbrAndBorrowOnBehalf(
        IMarket market, 
        uint dolaAmount,
        uint maxDebt,
        uint duration,
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s) 
        public payable
    {
        IERC20 collateral = IERC20(market.collateral());
        require(address(collateral) == address(WETH), "Market is not an ETH market");
        WETH.deposit{value:msg.value}();

        //Deposit collateral
        collateral.approve(address(market), msg.value);
        market.deposit(msg.sender, msg.value);

        //Borrow dola and buy dbr
        buyDbrAndBorrowOnBehalf(market, dolaAmount, maxDebt, duration, deadline, v, r , s);
    }

    /**
    @notice Sells DBR on behalf of the caller and uses the proceeds along with DOLA from the caller to repay debt.
    @dev The caller is unlikely to spend all of the DOLA they make available for the function call
    @param market The market the user wishes to repay debt in
    @param dolaAmount The maximum amount of dola debt the user is willing to repay
    @param minDolaFromDbr The minimum amount of DOLA the caller expects to get in return for selling their DBR.
     This is a sensitive parameter and should be provided with reasonably low slippage to prevent sandwhiching.
    @param dbrAmountToSell The amount of DBR the caller wishes to sell
    */
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
        
        //If the debt is lower than the dolaAmount, repay debt else repay dolaAmount
        uint repayAmount = debt < dolaAmount ? debt : dolaAmount;

        //If dolaBal is less than repayAmount, transfer remaining DOLA from user, otherwise transfer excess dola to user
        if(dolaBal < repayAmount){
            DOLA.transferFrom(msg.sender, address(this), repayAmount - dolaBal);
        } else {
            DOLA.transfer(msg.sender, dolaBal - repayAmount);
        }

        //Repay repayAmount
        DOLA.approve(address(market), repayAmount);
        market.repay(msg.sender, repayAmount);
    }

    /**
    @notice Sells DBR on behalf of the caller and uses the proceeds along with DOLA from the caller to repay debt, and then withdraws collateral
    @dev The caller is unlikely to spend all of the DOLA they make available for the function call
    @param market Market the user wishes to repay debt in
    @param dolaAmount Maximum amount of dola debt the user is willing to repay
    @param minDolaFromDbr Minimum amount of DOLA the caller expects to get in return for selling their DBR
     This is a sensitive parameter and should be provided with reasonably low slippage to prevent sandwhiching.
    @param dbrAmountToSell Amount of DBR the caller wishes to sell
    @param collateralAmount Amount of collateral to withdraw
    @param deadline Deadline of the signature
    @param v V parameter of the signature
    @param r R parameter of the signature
    @param s S parameter of the signature
    */
    function sellDbrRepayAndWithdrawOnBehalf(
        IMarket market, 
        uint dolaAmount, 
        uint minDolaFromDbr,
        uint dbrAmountToSell, 
        uint collateralAmount, 
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s) 
        external 
    {
        //Repay
        sellDbrAndRepayOnBehalf(market, dolaAmount, minDolaFromDbr, dbrAmountToSell);

        //Withdraw
        market.withdrawOnBehalf(msg.sender, collateralAmount, deadline, v, r, s);

        //Transfer collateral to msg.sender
        IERC20(market.collateral()).transfer(msg.sender, collateralAmount);
    }

    /**
    @notice Sells DBR on behalf of the caller and uses the proceeds along with DOLA from the caller to repay debt, and then withdraws collateral
    @dev The caller is unlikely to spend all of the DOLA they make available for the function call
    @param market Market the user wishes to repay debt in
    @param dolaAmount Maximum amount of dola debt the user is willing to repay
    @param minDolaFromDbr Minimum amount of DOLA the caller expects to get in return for selling their DBR
     This is a sensitive parameter and should be provided with reasonably low slippage to prevent sandwhiching.
    @param dbrAmountToSell Amount of DBR the caller wishes to sell
    @param collateralAmount Amount of collateral to withdraw
    @param deadline Deadline of the signature
    @param v V parameter of the signature
    @param r R parameter of the signature
    @param s S parameter of the signature
    */
    function sellDbrRepayAndWithdrawNativeEthOnBehalf(
        IMarket market, 
        uint dolaAmount, 
        uint minDolaFromDbr,
        uint dbrAmountToSell, 
        uint collateralAmount, 
        uint deadline, 
        uint8 v, 
        bytes32 r, 
        bytes32 s) 
        external 
    {
        //Repay
        sellDbrAndRepayOnBehalf(market, dolaAmount, minDolaFromDbr, dbrAmountToSell);

        //Withdraw
        withdrawNativeEthOnBehalf(market, collateralAmount, deadline, v, r, s);
    }

    /**
    @notice Repays debt, and then withdraws native ETH
    @dev The caller is unlikely to spend all of the DOLA they make available for the function call
    @param market Market the user wishes to repay debt in
    @param dolaAmount Amount of dola debt the user is willing to repay    
    @param collateralAmount Amount of collateral to withdraw
    @param deadline Deadline of the signature
    @param v V parameter of the signature
    @param r R parameter of the signature
    @param s S parameter of the signature
    */
    function repayAndWithdrawNativeEthOnBehalf(
        IMarket market, 
        uint dolaAmount,                 
        uint collateralAmount, 
        uint deadline,
        uint8 v, 
        bytes32 r, 
        bytes32 s) 
        external 
    {        
        // Repay
        DOLA.transferFrom(msg.sender, address(this), dolaAmount);        
        DOLA.approve(address(market), dolaAmount);
        market.repay(msg.sender, dolaAmount);

        // Withdraw
        withdrawNativeEthOnBehalf(market, collateralAmount, deadline, v, r, s);
    }

    /**
    @notice Helper function for depositing native eth to WETH markets
    @param market The WETH market to deposit to
    */
    function depositNativeEthOnBehalf(IMarket market) public payable {
        require(address(market.collateral()) == address(WETH), "Not an ETH market");
        WETH.deposit{value:msg.value}();
        WETH.approve(address(market), msg.value);
        market.deposit(msg.sender, msg.value);
    }

    /**
    @notice Helper function for depositing native eth to WETH markets before borrowing on behalf of the depositor
    @param market The WETH market to deposit to
    @param borrowAmount The amount to borrow on behalf of the depositor
    @param deadline Deadline of the signature
    @param v V parameter of the signature
    @param r R parameter of the signature
    @param s S parameter of the signature
    */
    function depositNativeEthAndBorrowOnBehalf(IMarket market, uint borrowAmount, uint deadline, uint8 v, bytes32 r, bytes32 s) public payable {
        require(address(market.collateral()) == address(WETH), "Not an ETH market");

        //Deposit native eth
        WETH.deposit{value:msg.value}();
        WETH.approve(address(market), msg.value);
        market.deposit(msg.sender, msg.value);

        //Borrow Dola
        market.borrowOnBehalf(msg.sender, borrowAmount, deadline, v, r, s);
        DOLA.transfer(msg.sender, borrowAmount);
    }

    /**
    @notice Helper function for withdrawing to native eth
    @param market WETH market to withdraw collateral from
    @param collateralAmount Amount of collateral to withdraw
    @param deadline Deadline of the signature
    @param v V parameter of the signature
    @param r R parameter of the signature
    @param s S parameter of the signature
    */
    function withdrawNativeEthOnBehalf(
        IMarket market,
        uint collateralAmount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s)
        public
    {
        market.withdrawOnBehalf(msg.sender, collateralAmount, deadline, v, r, s);

        IERC20 collateral = IERC20(market.collateral());
        require(address(collateral) == address(WETH), "Not an ETH market");
        WETH.withdraw(collateralAmount);

        (bool success,) = payable(msg.sender).call{value:collateralAmount}("");
        require(success, "Failed to transfer ETH");
    }
    
    //Empty receive function for receiving the native eth sent by the WETH contract
    receive() external payable {}
}
