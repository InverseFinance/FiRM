// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYearnVaultV2} from "src/interfaces/IYearnVaultV2.sol";
import {YearnVaultV2Helper} from "src/util/YearnVaultV2Helper.sol";

interface ICvxCrvStakingWrapper {
    //get balance of an address
    function balanceOf(address _account) external view returns (uint256);

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
    function userRewardWeight(address user) external view returns (uint256);

    //get number of reward tokens
    function rewardLength() external view returns (uint);

    //get reward address, reward group, reward integral and reward remaining
    function rewards(
        uint index
    ) external view returns (address, uint8, uint128, uint128);
}

contract DolaFraxBPEscrow {
    using SafeERC20 for IERC20;
    address public market;
    IERC20 public token;
    uint public stakedBalance;
    uint public yStakedBalance;
    ICvxCrvStakingWrapper public constant rewardPool =
        ICvxCrvStakingWrapper(0x0404d05F3992347d2f0dC3a97bdd147D77C85c1c);
    IYearnVaultV2 public yearn =
        IYearnVaultV2(0xe5F625e8f4D2A038AE9583Da254945285E5a77a4);
    address public beneficiary;
    mapping(address => bool) public allowlist;

    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary, "ONLY BENEFICIARY");
        _;
    }

    modifier onlyBeneficiaryOrAllowlist() {
        require(
            msg.sender == beneficiary || allowlist[msg.sender],
            "ONLY BENEFICIARY OR ALLOWED"
        );
        _;
    }

    event AllowClaim(address indexed allowedAddress, bool allowed);

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

        uint256 tokenBal = token.balanceOf(address(this));
        uint256 missingAmount = amount - tokenBal;
        uint256 yearnBal = yearn.balanceOf(address(this));
        // If there are enought tokens in the escrow, transfer the amount
        if (tokenBal >= amount) {
            token.transfer(recipient, amount);
        } else {
            // If there is enough balance in Yearn, withdraw all missing amount from Yearn
            if (
                YearnVaultV2Helper.collateralToAsset(yearn, yearnBal) >=
                missingAmount
            ) {
                uint256 withdrawAmount = YearnVaultV2Helper.assetToCollateral(
                    yearn,
                    missingAmount
                );
                //withdraw from Yearn
                token.transfer(
                    recipient,
                    yearn.withdraw(withdrawAmount, address(this)) + tokenBal
                );
            } else if (yearnBal > 0) {
                // Withdraw all possible balance from Yearn
                uint256 withdrawAmount = yearn.withdraw(
                    yearnBal,
                    address(this)
                );
                missingAmount -= withdrawAmount;
                // Then withdraw the missing amount from convex
                stakedBalance -= missingAmount;
                rewardPool.withdraw(missingAmount);
                token.transfer(
                    recipient,
                    tokenBal + withdrawAmount + missingAmount
                );
            } else {
                //withdraw from convex
                stakedBalance -= missingAmount;
                rewardPool.withdraw(missingAmount);
                token.transfer(recipient, missingAmount + tokenBal);
            }
        }
    }

    /**
    @notice Get the token balance of the escrow
    @return Uint representing the staked balance of the escrow
    */
    function balance() public view returns (uint) {
        return
            stakedBalance +
            YearnVaultV2Helper.collateralToAsset(
                yearn,
                yearn.balanceOf(address(this))
            ) +
            token.balanceOf(address(this));
    }

    /**
    @notice Function called by market on deposit. Stakes deposited collateral into convex reward pool
    @dev This function should remain callable by anyone to handle direct inbound transfers.
    */
    function onDeposit() public {}

    /**
    @notice Sets the reward weight for staked cvxCrv tokens.
    @param rewardWeightBps The percentage amount of reward tokens to be paid out in 3CRV tokens, set in basis points.
    */
    function setRewardWeight(
        uint rewardWeightBps
    ) external onlyBeneficiaryOrAllowlist {
        require(rewardWeightBps <= 10000, "WEIGHT > 10000");
        rewardPool.setRewardWeight(rewardWeightBps);
    }

    /**
    @notice Claims reward tokens to the specified address. Only callable by beneficiary and allowlisted addresses
    @param to Address to send claimed rewards to
    */
    function claimTo(address to) public onlyBeneficiaryOrAllowlist {
        //Claim rewards
        rewardPool.getReward(address(this), to);

        //Send contract balance of rewards
        uint rewardLength = rewardPool.rewardLength();
        for (uint rewardIndex; rewardIndex < rewardLength; ++rewardIndex) {
            (address rewardToken, , , ) = rewardPool.rewards(rewardIndex);
            uint rewardBal = IERC20(rewardToken).balanceOf(address(this));
            if (rewardBal > 0) {
                //Use safe transfer in case bad reward token is added
                IERC20(rewardToken).safeTransfer(to, rewardBal);
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

    function depositToConvex() external onlyBeneficiary {
        uint tokenBal = token.balanceOf(address(this));
        stakedBalance += tokenBal;
        rewardPool.stake(tokenBal, address(this));
    }

    function depositToYearn() external onlyBeneficiary {
        uint tokenBal = token.balanceOf(address(this));
        yearn.deposit(tokenBal, address(this));
    }

    function redeemSharesFromYearn(uint shares) external onlyBeneficiary {
        yearn.withdraw(shares, address(this));
    }

    function withdrawFromYearn(uint amount) external onlyBeneficiary {
        uint shares = YearnVaultV2Helper.assetToCollateral(yearn, amount);
        yearn.withdraw(shares, address(this));
    }

    function withdrawFromConvex(uint amount) external onlyBeneficiary {
        stakedBalance -= amount;
        rewardPool.withdraw(amount);
    }
}
