// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "src/interfaces/IERC20.sol";

interface IDBR {
    function markets(address) external view returns (bool);
    function mint(address, uint) external;
}

interface IINVEscrow {
    function market() external view returns (address);
    function beneficiary() external view returns (address);
}

interface IMarket {
    function escrows(address) external view returns (address);
    function collateral() external view returns (IERC20);
}

contract DbrDistributor {

    IDBR public immutable dbr;
    address public gov;
    address public operator;
    address public constant INV = 0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68;
    uint public constant mantissa = 10**18;
    uint public minRewardRate; // starts at 0
    uint public maxRewardRate = type(uint).max / 3652500 days; // 10,000 years
    uint public rewardRate; // starts at 0
    uint public lastUpdate;
    uint public rewardIndexMantissa;
    uint public totalSupply;
    
    mapping (address => uint) public balanceOf;
    mapping (address => uint) public stakerIndexMantissa;
    mapping (address => uint) public accruedRewards;
    
    modifier updateIndex() {
        uint deltaT = block.timestamp - lastUpdate;
        if(deltaT > 0) {
            if(rewardRate > 0 && totalSupply > 0) {
                uint rewardsAccrued = deltaT * rewardRate * mantissa;
                rewardIndexMantissa += rewardsAccrued / totalSupply;
            }
            lastUpdate = block.timestamp;
        }

        uint deltaIndex = rewardIndexMantissa - stakerIndexMantissa[msg.sender];
        uint bal = balanceOf[msg.sender];
        uint stakerDelta = bal * deltaIndex;
        stakerIndexMantissa[msg.sender] = rewardIndexMantissa;
        accruedRewards[msg.sender] += stakerDelta / mantissa;
        _;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "ONLY GOV");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operator, "ONLY OPERATOR");
        _;
    }

    modifier onlyINVEscrow() { // We don't check if escrow's market is INV and assume all calling markets to be INV markets
        _; // we break checks-effects-interactions to guard against re-entrancy below
        IMarket market = IMarket(IINVEscrow(msg.sender).market());
        address beneficiary = IINVEscrow(msg.sender).beneficiary();
        require(dbr.markets(address(market)), "UNSUPPORTED MARKET");
        require(address(market.collateral()) == address(INV), "UNSUPPORTED TOKEN");
        require(market.escrows(beneficiary) == msg.sender, "MSG SENDER NOT A VALID ESCROW");
    }

    constructor (IDBR _dbr, address _gov, address _operator) {
        dbr = _dbr;
        gov = _gov;
        operator = _operator;
        lastUpdate = block.timestamp;
    }

    function setOperator(address _operator) public onlyGov { operator = _operator; }
    function setGov(address _gov) public onlyGov { gov = _gov; }

    function setRewardRateConstraints(uint _min, uint _max) public onlyGov updateIndex {
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

    function setRewardRate(uint _rewardRate) public onlyOperator updateIndex {
        require(_rewardRate >= minRewardRate, "REWARD RATE BELOW MIN");
        require(_rewardRate <= maxRewardRate, "REWARD RATE ABOVE MIN");
        rewardRate = _rewardRate;
    }

    function stake(uint amount) public updateIndex onlyINVEscrow {
        balanceOf[msg.sender] += amount;
        totalSupply += amount;
    }

    function unstake(uint amount) public updateIndex onlyINVEscrow {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
    }

    function claimable(address user) public view returns(uint) {
        uint deltaT = block.timestamp - lastUpdate;
        uint rewardsAccrued = deltaT * rewardRate * mantissa;
        uint _rewardIndexMantissa = totalSupply > 0 ? rewardIndexMantissa + (rewardsAccrued / totalSupply) : rewardIndexMantissa;
        uint deltaIndex = _rewardIndexMantissa - stakerIndexMantissa[user];
        uint bal = balanceOf[user];
        uint stakerDelta = bal * deltaIndex / mantissa;
        return (accruedRewards[user] + stakerDelta);
    }

    function claim(address to) public updateIndex onlyINVEscrow {
        dbr.mint(to, accruedRewards[msg.sender]);
        accruedRewards[msg.sender] = 0;
    }

}
