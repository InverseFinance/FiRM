pragma solidity ^0.8.13;

contract RewardDistributor is Governable {

    uint public constant MANTISSA = 1e18;
    uint public globalDebt;
    mapping(address => uint) marketDebt;

    address[] public activeGlobalRewards;
    mapping(address => address[]) public activeMarketRewards;
    mapping(address mapping(address => RewardState)) public rewardStates;
    mapping(address => mapping(address => uint)) public borrowerIndexMantissa;
    mapping(address => mapping(address => uint)) public marketBorrowerDebt;
    mapping(address => mapping(address => uint)) public accruedTokenRewards;
    mapping(address => uint) public globalBorrowerDebt;
    
    struct RewardState {
        address rewardToken;
        uint rewardRate;
        uint maxRewardRate;
        uint lastUpdate;
        uint rewardIndexMantissa;
        //TODO: May be cheaper to make calls to DBR/Market than to store debt amounts here
        uint globalDebt;    
    }

    modifier updateIndexes(address borrower) {
        //TODO: Concat global + market specific arrays? No, uses different debt calculations
        //TODO: Assumes that it will only be called by markets
        for(uint i; i < activeGlobalRewards.length;++i){
            _updateRewardIndex(borrower, activeGlobalRewards[i], address(0));
        }
        for(uint i; i < activeMarketlRewards[msg.sender].length;++i){
            _updateRewardIndex(borrower, activeGlobalRewards[msg.sender][i], msg.sender);
        }
        _;
    }

    function _updateRewardIndex(address borrower, address token, address market) internal {
        RewardState state = rewardStates[market][token];
        uint deltaT = block.timestamp - state.lastUpdate;
        if(deltaT > 0) {
            if(state.rewardRate > 0 && state.globalDebt > 0) {
                uint rewardsAccrued = deltaT * state.rewardRate * MANTISSA;
                state.rewardIndexMantissa += rewardsAccrued / state.globalDebt;
            }
            lastUpdate = block.timestamp;
        }

        uint deltaIndex = rewardIndexMantissa - stakerIndexMantissa[msg.sender];
        //TODO: Get market specific debt if updating for a market and global debt if updating globally
        uint debt;
        if(market != address(0)){
            debt = marketBorrowerDebt[market][borrower];
        } else {
            debt = globalBorrowerDebt[borrower];
        }
        uint stakerDelta = debt * deltaIndex;
        borrowerIndexMantissa[msg.sender][borrower] = rewardIndexMantissa;
        accruedTokenRewards[state.rewardToken][borrower] += stakerDelta / mantissa;
    }

    //Call on both force liquidation and borrow
    function onIncreaseDebt(address borrower, uint debtIncrease) public updateIndexes(borrower) onlyMarket {
        globalBorrowDebt[borrower] += debtIncrease;
        marketBorrowerDebt[msg.sender][borrower] += debtIncrease;
        marketDebt[msg.sender] += debtIncrease;
        globalDebt += debtIncrease;
    }

    //Call on both repayments and liquidations
    function onReduceDebt(address borrower, uint debtReduction) public updateIndexes(borrower) onlyMarket {
        globalBorrowDebt[borrower] -= debtReduction;
        marketBorrowerDebt[msg.sender] -= debtReduction;
        marketDebt[msg.sender] -= debtIncrease;
        globalDebt -= debtIncrease;
    }

    function claimable(address user) public view returns(uint);

    function claim(address to, address borrower, address token) public updateIndexes(borrower) onlyMarket {
        uint accrued = accruedTokenRewards[token][borrower];
        accruedTokenRewards[token][borrower] = 0;
        //TODO: Use safe-transfer?
        IERC20(token).transfer(to, accrued);
    }

    
}
