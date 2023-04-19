pragma solidity ^0.8.13;
import "src/util/OffchainAbstractHelper.sol";

interface ICurvePool {
    function coins(uint index) external view returns(address);
    function get_dy(uint i, uint j, uint dx) external view returns(uint);
    function exchange(uint i, uint j, uint dx, uint min_dy, bool use_eth) external payable returns(uint);
    function exchange(uint i, uint j, uint dx, uint min_dy, bool use_eth, address receiver) external payable returns(uint);
}

contract CurveHelper is OffchainAbstractHelper{

    ICurvePool immutable curvePool;
    uint dbrIndex;
    uint dolaIndex;

    constructor(address _pool) {
        curvePool = ICurvePool(_pool);
        DOLA.approve(_pool, type(uint).max);
        DBR.approve(_pool, type(uint).max);
        if(ICurvePool(_pool).coins(0) == address(DOLA)){
            dolaIndex = 0;
            dbrIndex = 1;
        } else {
            dolaIndex = 1;
            dbrIndex = 0;
        }
    }

    /**
    @notice Sells an exact amount of DBR for DOLA in a curve pool
    @param amount Amount of DBR to sell
    @param minOut minimum amount of DOLA to receive
    */
    function _sellDbr(uint amount, uint minOut) internal override {
        curvePool.exchange(dbrIndex, dolaIndex, amount, minOut, false);
    }

    /**
    @notice Buys an exact amount of DBR for DOLA in a curve pool
    @param amount Amount of DOLA to sell
    @param minOut minimum amount of DBR out
    */
    function _buyDbr(uint amount, uint minOut, address receiver) internal override {
        curvePool.exchange(dolaIndex, dbrIndex, amount, minOut, false, receiver);
    }
    
    /**
    @notice Approximates the total amount of dola and dbr needed to borrow a dolaBorrowAmount while also borrowing enought to buy the DBR needed to cover for the borrowing period
    @dev Uses a binary search to approximate the amounts needed. 
    @param dolaBorrowAmount Amount of dola the user wishes to end up with
    @param period Amount of time in seconds the loan will last
    @param iterations Number of approximation iterations. The higher the more precise the result
    */
    function approximateDolaAndDbrNeeded(uint dolaBorrowAmount, uint period, uint iterations) public view override returns(uint dolaForDbr, uint dbrNeeded){
        uint amountIn = dolaBorrowAmount;
        for(uint i; i < iterations; ++i){
            uint dbrToBuy = (amountIn + dolaBorrowAmount) * period / 365 days;
            uint dbrReceived = curvePool.get_dy(dolaIndex, dbrIndex, amountIn);
            if(dbrReceived > dbrToBuy){
                amountIn = amountIn / 2;
            } else {
                amountIn = amountIn + amountIn/2;
            }
        }
        return (amountIn, (dolaBorrowAmount + amountIn) * period / 365 days);
    }
}
