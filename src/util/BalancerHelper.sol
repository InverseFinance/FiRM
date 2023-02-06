pragma solidity ^0.8.16;
import "src/util/IVault.sol";
import "src/util/AbstractHelper.sol";

interface BalancerPool {
    function getSwapFeePercentage() external view returns(uint);
}

contract BalancerHelper is AbstractHelper{

    IVault immutable vault;
    bytes32 immutable poolId;
    BalancerPool balancerPool;
    IVault.FundManagement fundManangement;

    constructor(address _dola, address _dbr, bytes32 _poolId, address _vault) AbstractHelper(_dola, _dbr){
        vault = IVault(_vault);
        poolId = _poolId;
        (address balancerPoolAddress,) = vault.getPool(_poolId);
        balancerPool = BalancerPool(balancerPoolAddress);
        fundManangement.sender = address(this);
        fundManangement.fromInternalBalance = false;
        //TODO: Explore if it makes sense to have recipient be the user
        fundManangement.recipient = payable(address(this));
        fundManangement.toInternalBalance = false;
        IERC20(_dola).approve(_vault, type(uint).max);
        IERC20(_dbr).approve(_vault, type(uint).max);
    }

    /**
    @notice Swaps exact amount of assetIn for asseetOut through a balancer pool. Output must be higher than minOut
    @dev Due to the unique design of Balancer ComposableStablePools, where BPT are part of the swappable balance, we can just swap DOLA directly for BPT
    @param amount Amount of DBR to sell
    @param minOut minimum amount of DOLA to receive
    */
    function _sellExactDbr(uint amount, uint minOut) internal override {
        IVault.SingleSwap memory swapStruct;

        //Populate Single Swap struct
        swapStruct.poolId = poolId;
        swapStruct.kind = IVault.SwapKind.GIVEN_IN;
        swapStruct.assetIn = IAsset(address(DBR));
        swapStruct.assetOut = IAsset(address(DOLA));
        swapStruct.amount = amount;
        //swapStruct.userData: User data can be left empty

        vault.swap(swapStruct, fundManangement, minOut, block.timestamp+1);
    }

    /**
    @notice Swaps amount of DOLA for exact amount of DBR through a balancer pool. Input must be lower than maxIn
    @dev Due to the unique design of Balancer ComposableStablePools, where BPT are part of the swappable balance, we can just swap DOLA directly for BPT
    @param amount Amount of DBR to receive
    @param maxIn maximum amount of DOLA to put in
    */
    function _buyExactDbr(uint amount, uint maxIn) internal override {
        IVault.SingleSwap memory swapStruct;

        //Populate Single Swap struct
        swapStruct.poolId = poolId;
        swapStruct.kind = IVault.SwapKind.GIVEN_OUT;
        swapStruct.assetIn = IAsset(address(DOLA));
        swapStruct.assetOut = IAsset(address(DBR));
        swapStruct.amount = amount;
        //swapStruct.userData: User data can be left empty

        vault.swap(swapStruct, fundManangement, maxIn, block.timestamp+1);
    }

    function _getTokenBalances(address tokenIn, address tokenOut) internal view returns(uint balanceIn, uint balanceOut){
        (address[] memory tokens, uint[] memory balances,) = vault.getPoolTokens(poolId);
        if(tokens[0] == tokenIn && tokens[1] == tokenOut){
            balanceIn = balances[0];
            balanceOut = balances[1];
        } else if(tokens[1] == tokenIn && tokens[0] == tokenOut){
            balanceIn = balances[1];
            balanceOut = balances[0];       
        } else {
            revert("Wrong tokens in pool");
        }   
    }

    /**
    @notice Calculates the amount of a token received from balancer weighted pool, given balances and amount in
    @dev Will only work for 50-50 weighted pools
    @param balanceIn Pool balance of token being traded in
    @param balanceOut Pool balance of token received
    @param amountIn Amount of token being traded in
    @return Amount of token received
    */
    function _getOutGivenIn(uint balanceIn, uint balanceOut, uint amountIn, uint tradeFee) internal pure returns(uint){
        return balanceOut * (10**18 - (balanceIn * 10**18 / (balanceIn + amountIn))) / 10**18 * (10**18 - tradeFee) / 10**18;
    }

    /**
    @notice Calculates the amount of a token to pay to a balancer weighted pool, given balances and amount out
    @dev Will only work for 50-50 weighted pools
    @param balanceIn Pool balance of token being traded in
    @param balanceOut Pool balance of token received
    @param amountOut Amount of token desired to receive
    @return Amount of token to pay in
    */
    function _getInGivenOut(uint balanceIn, uint balanceOut, uint amountOut, uint tradeFee) internal pure returns(uint){
        return balanceIn * (balanceOut * 10**18 / (balanceOut - amountOut) - 10**18) / 10**18 * (10**18 + tradeFee) / 1 ether;
    }

    function approximateDolaAndDbrNeeded(uint dolaBorrowAmount, uint period, uint iterations) override public view returns(uint, uint){
        (uint balanceIn, uint balanceOut) = _getTokenBalances(address(DOLA), address(DBR));
        uint dolaNeeded  = dolaBorrowAmount;
        uint dbrNeeded;
        uint tradeFee = balancerPool.getSwapFeePercentage();
        for(uint i; i < iterations;i++){
            dbrNeeded = dolaNeeded * period / 365 days;
            dolaNeeded = dolaBorrowAmount + _getInGivenOut(balanceIn, balanceOut, dbrNeeded, tradeFee);
        }
        return (dolaNeeded, dbrNeeded);
    }
}
