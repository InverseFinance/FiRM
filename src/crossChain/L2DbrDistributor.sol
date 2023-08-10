// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "src/interfaces/IERC20.sol";

interface IDBR {
    function markets(address) external view returns (bool);
    function mint(address, uint) external;
}

abstract contract L2DbrDistributor {

    IDBR public immutable dbr;
    address public gov;
    address public operator;
    address public messenger;
    uint public constant mantissa = 10**18;
    uint public minRewardRate; // starts at 0
    uint public maxRewardRate = type(uint).max / 3652500 days; // 10,000 years
    uint public rewardRate; // starts at 0
    uint public lastUpdate;
    uint public rewardIndexMantissa;
    uint public totalPower;
    mapping (address => uint) public stakingPower;
    mapping (address => uint) public stakerIndexMantissa;
    mapping (address => uint) public accruedRewards;
    
    modifier updateIndex(address staker) {
        uint deltaT = block.timestamp - lastUpdate;
        if(deltaT > 0) {
            if(rewardRate > 0 && totalPower > 0) {
                uint rewardsAccrued = deltaT * rewardRate * mantissa;
                rewardIndexMantissa += rewardsAccrued / totalPower;
            }
            lastUpdate = block.timestamp;
        }

        uint deltaIndex = rewardIndexMantissa - stakerIndexMantissa[staker];
        uint power = stakingPower[staker];
        uint stakerDelta = power * deltaIndex;
        stakerIndexMantissa[staker] = rewardIndexMantissa;
        accruedRewards[staker] += stakerDelta / mantissa;
        _;
    }

    modifier onlyGov() {
        require(isL1Sender(gov), "ONLY GOV");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "ONLY OPERATOR");
        _;
    }

    modifier onlyMessenger() {
        require(isL1Sender(messenger), "ONLY MESSENGER");
        _;
    }

    constructor (address _dbr, address _gov, address _operator, address _messenger) {
        dbr = IDBR(_dbr);
        gov = _gov;
        operator = _operator;
        messenger = _messenger;
        lastUpdate = block.timestamp;
    }

    function setOperator(address _operator) public onlyGov { operator = _operator; }
    function setGov(address _gov) public onlyGov { gov = _gov; }
    function setMessenger(address _messenger) external onlyGov { messenger = _messenger;}

    function setRewardRateConstraints(uint _min, uint _max) public onlyGov updateIndex(msg.sender) {
        require(_max < type(uint).max / 3652500 days); // cannot overflow and revert within 10,000 years
        require(_max >= _min);
        minRewardRate = _min;
        maxRewardRate = _max;
        if(rewardRate > _max) {
            rewardRate = _max;
        } else if(rewardRate < _min) {
            rewardRate = _min;
        }
    }

    function setRewardRate(uint _rewardRate) public onlyOperator updateIndex(msg.sender) {
        require(_rewardRate >= minRewardRate, "REWARD RATE BELOW MIN");
        require(_rewardRate <= maxRewardRate, "REWARD RATE ABOVE MIN");
        rewardRate = _rewardRate;
    }

    function updateStake(address staker, uint newPower) public updateIndex(staker) onlyMessenger {
        uint currentPower = stakingPower[staker];
        stakingPower[staker] = newPower;
        if(newPower > currentPower){
            totalPower += newPower - currentPower;
        } else {
            totalPower -= currentPower - newPower;
        }
    }

    function claimable(address user) public view returns(uint) {
        uint deltaT = block.timestamp - lastUpdate;
        uint rewardsAccrued = deltaT * rewardRate * mantissa;
        uint _rewardIndexMantissa = totalPower > 0 ? rewardIndexMantissa + (rewardsAccrued / totalPower) : rewardIndexMantissa;
        uint deltaIndex = _rewardIndexMantissa - stakerIndexMantissa[user];
        uint power = stakingPower[user];
        uint stakerDelta = power * deltaIndex / mantissa;
        return (accruedRewards[user] + stakerDelta);
    }

    function claim(address to) public updateIndex(msg.sender) {
        dbr.mint(to, accruedRewards[msg.sender]);
        accruedRewards[msg.sender] = 0;
    }

    function isL1Sender(address l1Address) internal virtual returns(bool);
}
