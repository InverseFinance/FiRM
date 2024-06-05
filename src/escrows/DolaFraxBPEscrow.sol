// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYearnVaultV2} from "src/interfaces/IYearnVaultV2.sol";
import {YearnVaultV2Helper} from "src/util/YearnVaultV2Helper.sol";

interface IConvexBooster {
    //get balance of an address
    function balanceOf(address _account) external view returns (uint256);

    //withdraw to a convex tokenized deposit
    function withdraw(uint256 pid, uint256 _amount) external;

    //claim rewards
    function getReward(address claimant) external;

    //claim rewards and forward to address
    function getReward(address claimant, address forwardTo) external;

    //stake convex curve
    function stake(uint256 _amount) external;

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

    function deposit(uint256 pid, uint256 amount, bool stake) external;
}

interface IRewardPool {
    function withdraw(uint256 amount, bool claim) external returns (bool);

    function withdrawAndUnwrap(
        uint256 amount,
        bool claim
    ) external returns (bool);

    function getReward(
        address account,
        bool claimExtras
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract DolaFraxBPEscrow {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error OnlyMarket();
    error OnlyBeneficiary();
    error OnlyBeneficiaryOrAllowlist();
    error CannotDepositToConvex(uint256 yearnAmount);
    error CannotDepositToYearn(uint256 convexAmount);
    address public market;
    IERC20 public token;
    uint public stakedBalance;
    uint public yStakedBalance;
    uint256 public pid = 115;
    IRewardPool public constant rewardPool =
        IRewardPool(0x0404d05F3992347d2f0dC3a97bdd147D77C85c1c);
    IConvexBooster public constant booster =
        IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IERC20 public constant depositToken =
        IERC20(0xf7eCC27CC9DB5d28110AF2d89b176A6623c7E351);
    IYearnVaultV2 public yearn =
        IYearnVaultV2(0xe5F625e8f4D2A038AE9583Da254945285E5a77a4);
    address public beneficiary;
    mapping(address => bool) public allowlist;

    modifier onlyBeneficiary() {
        if (msg.sender != beneficiary) revert OnlyBeneficiary();
        _;
    }

    modifier onlyBeneficiaryOrAllowlist() {
        if (msg.sender != beneficiary && !allowlist[msg.sender])
            revert OnlyBeneficiaryOrAllowlist();
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
        if (market != address(0)) revert AlreadyInitialized();
        market = msg.sender;
        token = _token;
        token.approve(address(rewardPool), type(uint).max);
        token.approve(address(booster), type(uint).max);
        token.approve(address(yearn), type(uint).max);
        //rewardPool.setRewardWeight(rewardPool.userRewardWeight(_beneficiary));
        beneficiary = _beneficiary;
    }

    /**
    @notice Withdraws the wrapped token from the reward pool and transfers the associated ERC20 token to a recipient.
    @param recipient The address to receive payment from the escrow
    @param amount The amount of ERC20 token to be transferred.
    */
    function pay(address recipient, uint amount) public {
        if (msg.sender != market) revert OnlyMarket();
        uint256 tokenBal = token.balanceOf(address(this));
        uint256 missingAmount = amount - tokenBal;
        // If there are enought tokens in the escrow, transfer the amount
        if (tokenBal >= amount) {
            token.safeTransfer(recipient, amount);
        } else if (stakedBalance >= missingAmount) {
            // If there are enough staked tokens in convex, withdraw the amount from convex
            stakedBalance -= missingAmount;
            rewardPool.withdrawAndUnwrap(missingAmount, false);
            token.safeTransfer(recipient, amount);
        } else if (
            YearnVaultV2Helper.collateralToAsset(
                yearn,
                yearn.balanceOf(address(this))
            ) >= missingAmount
        ) {
            // If there are enough tokens in Yearn, withdraw the amount from Yearn
            uint256 withdrawAmount = YearnVaultV2Helper.assetToCollateral(
                yearn,
                amount
            );
            // Withdraw from Yearn
            yearn.withdraw(withdrawAmount, address(this));
            // Transfer the amount to the recipient
            token.safeTransfer(recipient, amount);
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
    @notice Claims reward tokens to the specified address. Only callable by beneficiary and allowlisted addresses
    @param to Address to send claimed rewards to
    */
    function claimTo(address to) public onlyBeneficiaryOrAllowlist {
        //Claim rewards
        rewardPool.getReward(to, true);

        // //Send contract balance of rewards
        // uint rewardLength = rewardPool.rewardLength();
        // for (uint rewardIndex; rewardIndex < rewardLength; ++rewardIndex) {
        //     (address rewardToken, , , ) = rewardPool.rewards(rewardIndex);
        //     uint rewardBal = IERC20(rewardToken).balanceOf(address(this));
        //     if (rewardBal > 0) {
        //         //Use safe transfer in case bad reward token is added
        //         IERC20(rewardToken).safeTransfer(to, rewardBal);
        //     }
        // }
    }

    /**
    @notice Claims reward tokens to the message sender. Only callable by beneficiary and allowlisted addresses
    */
    function claim() external onlyBeneficiary {
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
        if (yearn.balanceOf(address(this)) > 0)
            revert CannotDepositToConvex(yearn.balanceOf(address(this)));
        uint tokenBal = token.balanceOf(address(this));
        stakedBalance += tokenBal;
        booster.deposit(pid, tokenBal, true);
    }

    function depositToYearn() external onlyBeneficiary {
        if (stakedBalance > 0) revert CannotDepositToYearn(stakedBalance);
        yearn.deposit(token.balanceOf(address(this)), address(this));
    }

    function withdrawFromYearn() external onlyBeneficiary {
        yearn.withdraw(yearn.balanceOf(address(this)), address(this));
    }

    function withdrawFromConvex() external onlyBeneficiary {
        uint256 amount = stakedBalance;
        stakedBalance = 0;
        rewardPool.withdrawAndUnwrap(amount, false);
    }
}
