pragma solidity ^0.8.13;
import "src/util/AbstractHelper.sol";

interface ICurvePool {
    function coins(uint index) external view returns(uint);
    function exchange(uint i, uint j, uint dx, uint min_dy, bool use_eth) external payable returns(uint);
    function exchange(uint i, uint j, uint dx, uint min_dy, bool use_eth, address receiver) external payable returns(uint);
}

contract CurveHelper is AbstractHelper{

    ICurvePool immutable curvePool;
    uint immutable dbrIndex;
    uint immutable dolaIndex;

    constructor(address _pool) {
        curvePool = ICurvePool(curvePool);
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
    @param amount Amount of DBR to receive
    @param maxIn maximum amount of DOLA to put in
    */
    function _buyDbr(uint amount, uint minOut, address receiver) internal override {
        curvePool.exchange(dolaIndex, dbrIndex, amount, minOut, false, receiver);
    }

    /**
    @notice Calculates the amount of a token to pay to a curve weighted pool, given balances and amount out
    @param balanceIn Pool balance of token being traded in
    @param balanceOut Pool balance of token received
    @param amountOut Amount of token desired to receive
    @param tradeFee The fee taking by LPs
    @return Amount of token to pay in
    */
    function _getInGivenOut(uint balanceIn, uint balanceOut, uint amountOut) internal view returns(uint){
        balances: uint256[N_COINS] = self.balances
        price_scale: uint256[N_COINS-1] = self._unpack_prices(self.price_scale_packed)
        A_gamma: uint256[2] = self._A_gamma()
        precisions: uint256[N_COINS] = self._unpack(self.packed_precisions)
        _D: uint256 = self._calc_D_ramp(balances, price_scale, A_gamma, precisions)

        uint x = 0;
        uint dx = 0
        _dy: uint256 = dy  # <------------ _dy will have less fee element than dy.
        fee_dy: uint256 = 0  # <-------- the amount of fee removed from dy in each
        #                                                               iteration.
        _xp: uint256[N_COINS] = empty(uint256[N_COINS])
        for k in range(20):

            _xp = balances  # <---------------------------------------- reset xp.

            # Adjust xp with output dy. dy contains fee element, which needs to be
            # iteratively sieved out:
            _xp[j] -= _dy
            _xp[0] *= precisions[0]
            for l in range(N_COINS - 1):
                _xp[l + 1] = _xp[l + 1] * price_scale[l] * precisions[l + 1] / PRECISION

            # calculate x for given xp
            x = MATH.get_y(A_gamma[0], A_gamma[1], _xp, _D, i)[0]
            dx = x - _xp[i]

            if i > 0:
                dx = dx * PRECISION / price_scale[i - 1]
            dx /= precisions[i]

            fee_dy = self._fee(_xp) * _dy / 10**10  # <----- Fee amount to remove.
            _dy = dy + fee_dy  # <--------------------- Sieve out fee_dy from _dy.

    return dx

    }

    /**
    @notice Approximates the amount of additional DOLA and DBR needed to sustain dolaBorrowAmount over the period
    @dev Larger number of iterations increases both accuracy of the approximation and gas cost. Will always undershoot actual DBR amount needed..
    @param dolaBorrowAmount The amount of DOLA the user wishes to borrow before covering DBR expenses
    @param period The amount of seconds the user wish to borrow the DOLA for
    @param iterations The amount of approximation iterations.
    @return dolaNeeded dbrNeeded Tuple of (dolaNeeded, dbrNeeded) representing the total dola needed to pay for the DBR and pay out dolaBorrowAmount and the dbrNeeded to sustain the loan over the period
    */
    function approximateDolaAndDbrNeeded(uint dolaBorrowAmount, uint period, uint iterations) override public view returns(uint dolaNeeded, uint dbrNeeded){
        (uint balanceIn, uint balanceOut) = _getTokenBalances(address(DOLA), address(DBR));
        dolaNeeded  = dolaBorrowAmount;
        uint tradeFee = curvePool.getSwapFeePercentage();
        //There may be a better analytical way of computing this
        for(uint i; i < iterations; i++){
            dbrNeeded = dolaNeeded * period / 365 days;
            dolaNeeded = dolaBorrowAmount + _getInGivenOut(balanceIn, balanceOut, dbrNeeded, tradeFee);
        }
    }
}
