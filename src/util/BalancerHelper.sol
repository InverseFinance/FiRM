pragma solidity ^0.8.16;
import "src/util/IVault.sol";
import "src/util/AbstractHelper.sol";

contract BalancerHelper is AbstractHelper{

    IVault immutable vault;
    bytes32 immutable poolId;
    IVault.FundManagement fundManangement;

    constructor(address _dola, address _dbr, bytes32 _poolId, address _vault) AbstractHelper(_dola, _dbr){
        vault = IVault(_vault);
        poolId = _poolId;
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


}
