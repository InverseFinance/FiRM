pragma solidity ^0.8.13;

import "src/escrows/MultiVaultEscrow.sol";

interface IRewardPool {
    function balanceOf(address account) external view returns(uint);
    function extraRewardsLength() external view returns(uint);
    function extraRewards() external view returns(address);
    function getReward(address to, bool claim) external returns(bool);
    function stakeAll() external returns(bool);
    function withdrawAndUnwrap(uint amount, bool claim) external returns(bool);
}

contract CurveLPConvexEscrow is MultiVaultEscrow {

    IRewardPool rewardPool;
    
    function _initializeBase(IERC20 _token, address beneficiary) internal override {
         _token.approve(address(rewardPool), type(uint).max);
    }

    function _balanceBase() internal view override returns(uint){
        return rewardPool.balanceOf(address(this));
    }

    function _depositBase() internal override {
        require(rewardPool.stakeAll(), "Stake failed");
    }

    function _withdrawBase(address recipient, uint amount) internal override {
        require(rewardPool.withdrawAndUnwrap(amount, false), "Withdraw failed");
        token.transfer(recipient, amount);
    }

    /**
     * @notice Claims reward tokens to the specified address. Only callable by beneficiary and allowlisted addresses
     * @param to Address to send claimed rewards to
     */
    function claimTo(address to, bool claimExtra) public onlyBeneficiaryOrAllowlist{
        //Claim rewards
        require(rewardPool.getReward(address(this), to), "Claim failed");

        //Send contract balance of rewards
        if(claimExtra){
            uint rewardLength = rewardPool.extraRewardsLength();
            for(uint rewardIndex; rewardIndex < rewardLength; ++rewardIndex){
                (address rewardToken,,,) = rewardPool.extraRewards(rewardIndex);
                uint rewardBal = IERC20(rewardToken).balanceOf(address(this));
                if(rewardBal > 0){
                    //Use safe transfer in case bad reward token is added
                    IERC20(rewardToken).safeTransfer(to, rewardBal);
                }
            }
        }
    }

}
