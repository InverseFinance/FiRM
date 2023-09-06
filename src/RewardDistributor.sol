pragma solidity ^0.8.13;

import "src/Governable.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IDBR.sol";

contract RewardDistributor is Governable {

    uint public constant MANTISSA = 1e18;
    IDBR public immutable DBR;

    //Market -> Debt, address(0) is global debt
    mapping(address => uint) public marketDebt;
    //Market -> Array of active reward tokens, address(0) is global rewards
    mapping(address => address[]) public activeMarketRewards;
    //Market -> (Reward Token -> RewardState of Token) - Market will be address(0) if global reward
    mapping(address => mapping(address => RewardState)) public rewardStates;
    //Market -> (Borrower -> Debt Amount)
    //address(0) "market" represents global debt
    mapping(address => mapping(address => uint)) public marketBorrowerDebt;
    //Reward Token -> (Borrower -> Accrued Rewards)
    mapping(address => mapping(address => uint)) public accruedTokenRewards;

    error OnlyMarket();
    error TokenAlreadyActive(address market);
    error TokenInactive();
    error ActiveRateCantBeZero();
    error RewardRateAboveMaxRate();
    error ZeroAmount();

    constructor(address _dbr, address _gov) Governable(_gov){
        DBR = IDBR(_dbr);
    }
    
    struct RewardState {
        address rewardToken;
        uint rewardRate;
        uint maxRatePerDebt;
        uint lastUpdate;
        uint rewardIndexMantissa;
        uint surplus;
        mapping(address => uint) borrowerIndexMantissa;
    }

    modifier updateIndexes(address borrower) {
        //Update indexes of global rewards
        for(uint i; i < activeMarketRewards[address(0)].length;++i){
            _updateBorrowerIndex(borrower, activeMarketRewards[address(0)][i], address(0));
        }
        //Update indexes of market specific rewards
        for(uint i; i < activeMarketRewards[msg.sender].length;++i){
            _updateBorrowerIndex(borrower, activeMarketRewards[msg.sender][i], msg.sender);
        }
        _;
    }

    modifier onlyMarket() {
        if(!DBR.markets(msg.sender)) revert OnlyMarket();
        _;
    }

    function _updateRewardIndex(address token, address market) internal {
        RewardState storage state = rewardStates[market][token];
        uint deltaT = block.timestamp - state.lastUpdate;
        if(deltaT > 0) {
            if(state.rewardRate > 0 && marketDebt[market] > 0) {
                uint rewardsAccrued = deltaT * state.rewardRate * MANTISSA;
                uint maxAccrued = deltaT * state.maxRatePerDebt * marketDebt[market];
                if(rewardsAccrued > maxAccrued) rewardsAccrued = maxAccrued;
                if(rewardsAccrued > state.surplus){
                    rewardsAccrued = state.surplus;
                    rewardStates[market][token].surplus = 0;
                    _inactivateReward(token, market);
                }
                rewardStates[market][token].rewardIndexMantissa += rewardsAccrued / marketDebt[market];
            }
            rewardStates[market][token].lastUpdate = block.timestamp; 
        }
    }

    function _updateBorrowerIndex(address borrower, address token, address market) internal {
        _updateRewardIndex(token, market);
        RewardState storage state = rewardStates[market][token];
        uint deltaIndex = state.rewardIndexMantissa - state.borrowerIndexMantissa[borrower];
        uint debt = marketBorrowerDebt[market][borrower];
        uint stakerDelta = debt * deltaIndex;
        rewardStates[market][token].borrowerIndexMantissa[borrower] = state.rewardIndexMantissa;
        accruedTokenRewards[token][borrower] += stakerDelta / MANTISSA;
    }

    //Call on both force replenishments and borrow
    function onIncreaseDebt(address borrower, uint debtIncrease) public onlyMarket updateIndexes(borrower) {
        marketBorrowerDebt[msg.sender][borrower] += debtIncrease;
        marketBorrowerDebt[address(0)][borrower] += debtIncrease;
        marketDebt[msg.sender] += debtIncrease;
        marketDebt[address(0)] += debtIncrease;
    }

    //Call on both repayments and liquidations
    function onReduceDebt(address borrower, uint debtReduction) public onlyMarket updateIndexes(borrower) {
        marketBorrowerDebt[msg.sender][borrower] -= debtReduction;
        marketBorrowerDebt[address(0)][borrower] -= debtReduction;
        marketDebt[msg.sender] -= debtReduction;
        marketDebt[address(0)] -= debtReduction;
    }

    function claimable(address borrower, address token, address[] calldata markets) external view returns(uint) {
        uint totalClaimable;
        for(uint i; i < markets.length; ++i){
            totalClaimable = claimable(borrower, token, markets[i]);
        }
        return totalClaimable;
    }

    function claimable(address borrower, address token, address market) public view returns(uint) {
        RewardState storage state = rewardStates[market][token];
        uint deltaT = block.timestamp - state.lastUpdate;
        uint rewardsAccrued = deltaT * state.rewardRate * MANTISSA;
        uint _rewardIndexMantissa = marketDebt[market] > 0 ? state.rewardIndexMantissa + (rewardsAccrued / marketDebt[market]) : state.rewardIndexMantissa;
        uint deltaIndex = _rewardIndexMantissa - state.borrowerIndexMantissa[borrower];
        uint debt = marketBorrowerDebt[market][borrower];
        uint borrowerDelta = debt * deltaIndex / MANTISSA;
        return (accruedTokenRewards[token][borrower] + borrowerDelta);
    }

    function claim(address to, address borrower, address token, address market) external {
        require(msg.sender == borrower, "Claim disallowed");
        //TODO: Is it dangerous if a non-existent market or token is used?
        _updateBorrowerIndex(borrower, token, market);
        uint accrued = accruedTokenRewards[token][borrower];
        accruedTokenRewards[token][borrower] = 0;
        //TODO: Use safe-transfer?
        //TODO: What to do if not enough tokens?
        IERC20(token).transfer(to, accrued);
    }

    function setRewardRate(address token, address market, uint _rewardRate) external onlyGov{
        if(_rewardRate == 0) revert ActiveRateCantBeZero();
        if(!isTokenActive(token, market)) revert TokenInactive();
        _updateRewardIndex(token, market);
        rewardStates[market][token].rewardRate = _rewardRate;
    }

    function setMaxRatePerDebt(address token, address market, uint _maxRatePerDebt) external onlyGov{
        if(_maxRatePerDebt == 0) revert ActiveRateCantBeZero();
        if(!isTokenActive(token, market)) revert TokenInactive();
        _updateRewardIndex(token, market);
        rewardStates[market][token].maxRatePerDebt = _maxRatePerDebt;
    }

    function topUp(address token, address market, uint amount) external {
        if(!isTokenActive(token, market)) revert TokenInactive();
        if(amount == 0) revert ZeroAmount();
        //TODO: Use safe transfer
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        rewardStates[market][token].surplus += amount;
    }

    function activateReward(
        address token,
        address market,
        uint rewardRate,
        uint maxRatePerDebt,
        uint amount
    ) external onlyGov {
        if(maxRatePerDebt == 0 || rewardRate == 0) revert ActiveRateCantBeZero();
        if(isTokenActive(token, market)) revert TokenAlreadyActive(market);
        //TODO: Use safe transfer
        if(amount > 0) IERC20(token).transferFrom(msg.sender, address(this), amount);
        activeMarketRewards[market].push(token);
        rewardStates[market][token].lastUpdate = block.timestamp;
        rewardStates[market][token].rewardRate = rewardRate;
        rewardStates[market][token].maxRatePerDebt = maxRatePerDebt;
        rewardStates[market][token].surplus += amount;
    }

    function inactivateReward( address token, address market) external onlyGov {
        _updateRewardIndex(token, market);
        _inactivateReward(token, market);
    }

    function _inactivateReward(
        address token,
        address market
    ) internal {
        bool isActive;
        for(uint i; i < activeMarketRewards[market].length; ++i){
            if(activeMarketRewards[market][i] == token){
                isActive = true;
                delete(activeMarketRewards[market][i]);
                break;
            }
        }
        if(!isActive) revert TokenInactive();
        rewardStates[market][token].lastUpdate = block.timestamp;
        rewardStates[market][token].rewardRate = 0;
        rewardStates[market][token].maxRatePerDebt = 0;
    }

    function isTokenActive(address token, address market) public view returns(bool){
        for(uint i; i < activeMarketRewards[market].length; ++i){
            if(activeMarketRewards[market][i] == token) return true;
        }
        return false;
    }
}
