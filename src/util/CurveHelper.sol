pragma solidity ^0.8.13;
import "src/util/OffchainAbstractHelper.sol";

interface ICurvePool {
    function coins(uint index) external view returns(address);
    function get_dy(uint i, uint j, uint dx) external view returns(uint);
    function exchange(uint i, uint j, uint dx, uint min_dy, address receiver) external returns(uint);
    function exchange(uint i, uint j, uint dx, uint min_dy) external returns(uint);
}

contract CurveHelper is OffchainAbstractHelper {

    ICurvePool public curvePool;
    address public pendingGov;
    address public gov;
    uint public dbrIndex = type(uint).max;
    uint public dolaIndex = type(uint).max;

    event NewPendingGov(address indexed oldPendingGov, address indexed newPendingGov);
    event NewGov(address indexed oldGov, address indexed newGov);
    event NewCurvePool(address indexed newPool, uint256 dolaIndex, uint256 dbrIndex);

    constructor(address _pool, address _gov) {
        curvePool = ICurvePool(_pool);
        gov = _gov;
        for(uint i; i < 3; ++i){
            if(curvePool.coins(i) == address(DOLA)){
                dolaIndex = i;
            }
            else if(curvePool.coins(i) == address(DBR)){
                dbrIndex = i;
            }
        }
        require(dolaIndex != type(uint).max && dbrIndex != type(uint).max, "CurveHelper: pool missing DOLA or DBR");
        DOLA.approve(_pool, type(uint).max);
        DBR.approve(_pool, type(uint).max);
    }

    modifier onlyGov() {
        require(msg.sender == gov, "CurveHelper: only gov");
        _;
    }

    /**
    @notice Sells an exact amount of DBR for DOLA in a curve pool
    @param amount Amount of DBR to sell
    @param minOut minimum amount of DOLA to receive
    */
    function _sellDbr(uint amount, uint minOut, address receiver) internal override {
        if(amount > 0){
            curvePool.exchange(dbrIndex, dolaIndex, amount, minOut, receiver);
        }
    }

    /**
    @notice Buys an exact amount of DBR for DOLA in a curve pool
    @param amount Amount of DOLA to sell
    @param minOut minimum amount of DBR out
    */
    function _buyDbr(uint amount, uint minOut, address receiver) internal override {
        if(amount > 0) {
            curvePool.exchange(dolaIndex, dbrIndex, amount, minOut, receiver);
        }
    }
    
    /**
    @notice Approximates the total amount of dola and dbr needed to borrow a dolaBorrowAmount while also borrowing enough to buy the DBR needed to cover for the borrowing period
    @dev Uses a binary search to approximate the amounts needed. Should only be called as part of generating transaction parameters.
    @param dolaBorrowAmount Amount of dola the user wishes to end up with
    @param period Amount of time in seconds the loan will last
    @param iterations Number of approximation iterations. The higher the more precise the result
    */
    function approximateDolaAndDbrNeeded(uint dolaBorrowAmount, uint period, uint iterations) public view override returns(uint dolaForDbr, uint dbrNeeded){
        uint amountIn = dolaBorrowAmount;
        uint stepSize = amountIn / 2;
        uint dbrReceived = curvePool.get_dy(dolaIndex, dbrIndex, amountIn);
        uint dbrToBuy = (amountIn + dolaBorrowAmount) * period / 365 days;
        uint dist = dbrReceived > dbrToBuy ? dbrReceived - dbrToBuy : dbrToBuy - dbrReceived;
        for(uint i; i < iterations; ++i){
            uint newAmountIn = amountIn;
            if(dbrReceived > dbrToBuy){
                newAmountIn -= stepSize;
            } else {
                newAmountIn += stepSize;
            }
            uint newDbrReceived = curvePool.get_dy(dolaIndex, dbrIndex, newAmountIn);
            uint newDbrToBuy = (newAmountIn + dolaBorrowAmount) * period / 365 days;
            uint newDist = newDbrReceived > newDbrToBuy ? newDbrReceived - newDbrToBuy : newDbrToBuy - newDbrReceived;
            if(newDist < dist){
                dbrReceived = newDbrReceived;
                dbrToBuy = newDbrToBuy;
                dist = newDist;
                amountIn = newAmountIn;
            }
            stepSize /= 2;
        }
        return (amountIn, (dolaBorrowAmount + amountIn) * period / 365 days);
    }

    /**
     * @notice Set a new pending gov. The new pending gov then has to call `acceptGov`.
     * @dev Can only be called by the gov.
     * @param _pendingGov address of the new pending gov
     */
    function setPendingGov(address _pendingGov) external onlyGov {
        emit NewPendingGov(pendingGov, _pendingGov);
        pendingGov = _pendingGov;
    }

    /**
     * @notice Accept the new pending gov.
     * @dev Can only be called by the pending gov.
     */
    function acceptGov() external {
        require(msg.sender == pendingGov, "Only pending gov");
        emit NewGov(gov, pendingGov);
        gov = pendingGov;
        pendingGov = address(0);
    }

    /**
    @notice Sets a new curve pool
    @dev Can only be called by the gov
    @param _pool Address of the new curve pool
    @param _dolaIndex Index of DOLA in the new curve pool
    @param _dbrIndex Index of DBR in the new curve pool
    */
    function setCurvePool(address _pool, uint256 _dolaIndex, uint256 _dbrIndex) external onlyGov {
        ICurvePool newPool = ICurvePool(_pool);
        require(newPool.coins(_dolaIndex) == address(DOLA), "Wrong dola index");
        require(newPool.coins(_dbrIndex) == address(DBR), "Wrong dbr index");
        DOLA.approve(address(curvePool), 0);
        DBR.approve(address(curvePool), 0);
        curvePool = newPool;
        DOLA.approve(_pool, type(uint).max);
        DBR.approve(_pool, type(uint).max);
        dolaIndex = _dolaIndex;
        dbrIndex = _dbrIndex;
        emit NewCurvePool(_pool, _dolaIndex, _dbrIndex);
    }
}
