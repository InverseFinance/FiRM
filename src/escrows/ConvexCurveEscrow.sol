// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Caution. We assume all failed transfers cause reverts and ignore the returned bool.
interface IERC20 {
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
    function approve(address spender, uint value) external returns (bool);
}

//sample convex reward contracts interface
interface ICvxCrvStakingWrapper{
    //get balance of an address
    function balanceOf(address _account) external view returns(uint256);
    //withdraw to a convex tokenized deposit
    function withdraw(uint256 _amount) external;
    //claim rewards
    function getReward(address claimant) external;
    //claim rewards and forward to address
    function getReward(address claimant, address forwardTo) external;
    //stake convex curve
    function stake(uint256 _amount, address _to) external;
    //sets the weight of gov token to receive, can be set between 0 and 10000
    function setRewardWeight(uint govTokenBps) external;
    //get the reward weight of a specific address
    function userRewardWeight(address user) external view returns(uint256);
    //get number of reward tokens
    function rewardLength() external view returns(uint);
    //get reward address, reward group, reward integral and reward remaining
    function rewards(uint index) external view returns(address,uint8,uint128,uint128);
}

/**
@title Convex Curve Escrow
@notice Collateral is stored in unique escrow contracts for every user and every market.
@dev Caution: This is a proxy implementation. Follow proxy pattern best practices
*/
contract ConvexCurveEscrow {
    address public market;
    IERC20 public token;
    ICvxCrvStakingWrapper public constant rewardPool = ICvxCrvStakingWrapper(0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434);
    address public beneficiary;
    mapping(address => bool) public allowlist;

    modifier onlyBeneficiary {
        require(msg.sender == beneficiary, "ONLY BENEFICIARY");
        _; 
    }

    modifier onlyBeneficiaryOrAllowlist {
        require(msg.sender == beneficiary || allowlist[msg.sender], "ONLY BENEFICIARY OR ALLOWED");
        _; 
    }

    /**
    @notice Initialize escrow with a token
    @dev Must be called right after proxy is created.
    @param _token The IERC20 token representing the governance token
    @param _beneficiary The beneficiary who cvxCRV is staked on behalf
    */
    function initialize(IERC20 _token, address _beneficiary) public {
        require(market == address(0), "ALREADY INITIALIZED");
        market = msg.sender;
        token = _token;
        token.approve(address(rewardPool), type(uint).max);
        rewardPool.setRewardWeight(rewardPool.userRewardWeight(_beneficiary));
        beneficiary = _beneficiary;
    }

    /**
    @notice Withdraws the wrapped token from the reward pool and transfers the associated ERC20 token to a recipient.
    @param recipient The address to receive payment from the escrow
    @param amount The amount of ERC20 token to be transferred.
    */
    function pay(address recipient, uint amount) public {
        require(msg.sender == market, "ONLY MARKET");
        rewardPool.withdraw(amount);
        token.transfer(recipient, amount);
    }

    /**
    @notice Get the token balance of the escrow
    @return Uint representing the token balance of the contract + the staked balance
    */
    function balance() public view returns (uint) {
        return rewardPool.balanceOf(address(this));
    }

    /**
    @notice Function called by market on deposit. Stakes deposited collateral into convex reward pool
    @dev This function should remain callable by anyone to handle direct inbound transfers.
    */
    function onDeposit() public {
        //Stake cvxCRV
        rewardPool.stake(token.balanceOf(address(this)), address(this));
    }
    /**
    @notice Sets the reward weight for staked cvxCrv tokens.
    @param threeCurveTokenBps The percentage amount of reward tokens to be paid out in 3CRV tokens, set in basis points.
    */
    function setRewardWeight(uint threeCurveTokenBps) external onlyBeneficiaryOrAllowlist {
        require(threeCurveTokenBps <= 10000, "WEIGHT > 10000");
        rewardPool.setRewardWeight(threeCurveTokenBps);
    }

    /**
    @notice Claims reward tokens to the specified address. Only callable by beneficiary and allowlisted addresses
    @param to Address to send claimed rewards to
    */
    function claimTo(address to) public onlyBeneficiaryOrAllowlist{
        //Claim rewards
        rewardPool.getReward(address(this), to);

        //Send contract balance of rewards
        uint rewardLength = rewardPool.rewardLength();
        for(uint rewardIndex; rewardIndex < rewardLength; ++rewardIndex){
            (address rewardToken,,,) = rewardPool.rewards(rewardIndex);
            uint rewardBal = IERC20(rewardToken).balanceOf(address(this));
            if(rewardBal > 0){
                IERC20(rewardToken).transfer(to, rewardBal);
            }
        }
    }
    
    /**
    @notice Claims reward tokens to the message sender. Only callable by beneficiary and allowlisted addresses
    */
    function claim() external {
        claimTo(msg.sender);
    }

    /**
    @notice Allow address to claim on behalf of the beneficiary to any address
    @param allowee Address that are allowed to claim on behalf of the beneficiary
    @dev Can be used to build contracts for auto-compounding cvxCrv, auto-buying DBR or auto-repaying loans
    */
    function allowClaimOnBehalf(address allowee) external onlyBeneficiary {
        allowlist[allowee] = true;
    }

    /**
    @notice Disallow address to claim on behalf of the beneficiary to any address
    @param allowee Address that are disallowed to claim on behalf of the beneficiary
    */
    function disallowClaimOnBehalf(address allowee) external onlyBeneficiary {
        allowlist[allowee] = false;   
    }
}
