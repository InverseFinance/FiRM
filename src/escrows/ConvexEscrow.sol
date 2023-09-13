// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

//sample convex reward contracts interface
interface ICvxRewardPool{
    function withdraw(uint amount, bool claimRewads) external;
    function stake(uint amount) external;
    function stakeAll() external;
    function getReward(address staker, bool claimExtra, bool stake) external;
    function extraRewards(uint index) external returns(address token);
    function extraRewardsLength() external returns(uint length);
}

/**
@title Convex Escrow
@notice Collateral is stored in unique escrow contracts for every user and every market.
@dev Caution: This is a proxy implementation. Follow proxy pattern best practices
*/
contract ConvexCurveEscrow {
    using SafeERC20 for IERC20;
    address public market;
    IERC20 public constant token = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public constant rewardToken = IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    uint public stakedBalance;
    ICvxRewardPool public constant rewardPool = ICvxRewardPool(0xCF50b810E57Ac33B91dCF525C6ddd9881B139332);
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

    event AllowClaim(address indexed allowedAddress, bool allowed);

    /**
    @notice Initialize escrow with a token
    @dev Must be called right after proxy is created.
    @param _beneficiary The beneficiary who cvxCRV is staked on behalf
    */
    function initialize(address, address _beneficiary) public {
        require(market == address(0), "ALREADY INITIALIZED");
        market = msg.sender;
        token.approve(address(rewardPool), type(uint).max);
        beneficiary = _beneficiary;
    }

    /**
    @notice Withdraws the wrapped token from the reward pool and transfers the associated ERC20 token to a recipient.
    @param recipient The address to receive payment from the escrow
    @param amount The amount of ERC20 token to be transferred.
    */
    function pay(address recipient, uint amount) public {
        require(msg.sender == market, "ONLY MARKET");
        stakedBalance -= amount;
        rewardPool.withdraw(amount, false);
        token.transfer(recipient, amount);
    }

    /**
    @notice Get the token balance of the escrow
    @return Uint representing the staked balance of the escrow
    */
    function balance() public view returns (uint) {
        return stakedBalance;
    }

    /**
    @notice Function called by market on deposit. Stakes deposited collateral into convex reward pool
    @dev This function should remain callable by anyone to handle direct inbound transfers.
    */
    function onDeposit() public {
        //Stake cvxCRV
        uint tokenBal = token.balanceOf(address(this));
        stakedBalance += tokenBal;
        rewardPool.stake(tokenBal);
    }

    /**
    @notice Claims reward tokens to the specified address. Only callable by beneficiary and allowlisted addresses
    @param to Address to send claimed rewards to
    */
    function claimTo(address to) public onlyBeneficiaryOrAllowlist{

        uint extraRewards = rewardPool.extraRewardsLength();
        //Claim rewards, only claim extra rewards if there are any
        rewardPool.getReward(address(this), extraRewards > 0, false);
        rewardToken.transfer(to, rewardToken.balanceOf(address(this)));

        //Go through extra rewards and send tokens, if extraRewards == 0, will not execute
        for(uint rewardIndex; rewardIndex < extraRewards; ++rewardIndex){
            address extraRewardToken = rewardPool.extraRewards(rewardIndex);
            uint rewardBal = IERC20(extraRewardToken).balanceOf(address(this));
            if(rewardBal > 0){
                //Use safe transfer in case bad reward token is added
                IERC20(extraRewardToken).safeTransfer(to, rewardBal);
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
        emit AllowClaim(allowee, true);
    }

    /**
    @notice Disallow address to claim on behalf of the beneficiary to any address
    @param allowee Address that are disallowed to claim on behalf of the beneficiary
    */
    function disallowClaimOnBehalf(address allowee) external onlyBeneficiary {
        allowlist[allowee] = false;   
        emit AllowClaim(allowee, false);
    }
}
