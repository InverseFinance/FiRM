// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYearnVaultV2} from "src/interfaces/IYearnVaultV2.sol";
import {YearnVaultV2Helper} from "src/util/YearnVaultV2Helper.sol";
import {IRewardPool} from "src/interfaces/IRewardPool.sol";
import {IConvexBooster} from "src/interfaces/IConvexBooster.sol";
import {IVirtualBalanceRewardPool} from "src/interfaces/IVirtualBalanceRewardPool.sol";

contract DolaFraxBPEscrow {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error OnlyMarket();
    error OnlyBeneficiary();
    error OnlyBeneficiaryOrAllowlist();
    error CannotDepositToConvex(uint256 yearnAmount);
    error CannotDepositToYearn(uint256 convexAmount);

    uint256 public constant pid = 115;

    IRewardPool public constant rewardPool =
        IRewardPool(0x0404d05F3992347d2f0dC3a97bdd147D77C85c1c);
    IConvexBooster public constant booster =
        IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    IYearnVaultV2 public constant yearn =
        IYearnVaultV2(0xe5F625e8f4D2A038AE9583Da254945285E5a77a4);
    IERC20 public constant cvx =
        IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 public constant crv =
        IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);

    address public market;
    IERC20 public token;
    uint256 public stakedBalance;
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
        token.approve(address(booster), type(uint).max);
        token.approve(address(yearn), type(uint).max);
        beneficiary = _beneficiary;
    }

    /**
    @notice Withdraws the wrapped token from the reward pool and transfers the associated ERC20 token to a recipient.
    @dev Will first try to pay from the escrow balance, if not enough or any, will try to pay the missing amount from convex, then from yearn if needed
    @param recipient The address to receive payment from the escrow
    @param amount The amount of ERC20 token to be transferred.
    */
    function pay(address recipient, uint amount) public {
        if (msg.sender != market) revert OnlyMarket();
        uint256 tokenBal = token.balanceOf(address(this));
        uint256 missingAmount = amount > tokenBal ? amount - tokenBal : 0;
        // If there are enough tokens in the escrow, transfer the amount
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
                missingAmount
            );
            // Withdraw from Yearn
            uint256 assetAmount = yearn.withdraw(withdrawAmount, address(this));
            // Transfer the amount to the recipient
            token.safeTransfer(recipient, assetAmount + tokenBal);
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
        rewardPool.getReward(address(this), true);
        //Send crv balance
        uint256 crvBal = crv.balanceOf(address(this));
        if (crvBal != 0) crv.safeTransfer(to, crvBal);
        //Send cvx balance
        uint256 cvxBal = cvx.balanceOf(address(this));
        if (cvxBal != 0) cvx.safeTransfer(to, cvxBal);

        //Send contract balance of extra rewards
        uint256 rewardLength = rewardPool.extraRewardsLength();
        if (rewardLength == 0) return;
        for (uint rewardIndex; rewardIndex < rewardLength; ++rewardIndex) {
            IVirtualBalanceRewardPool virtualReward = IVirtualBalanceRewardPool(
                rewardPool.extraRewards(rewardIndex)
            );
            IERC20 rewardToken = virtualReward.rewardToken();
            uint rewardBal = rewardToken.balanceOf(address(this));
            if (rewardBal > 0) {
                //Use safe transfer in case bad reward token is added
                rewardToken.safeTransfer(to, rewardBal);
            }
        }
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

    /**
     * @notice Deposit token balance in the escrow into Convex
     * @dev Cannot deposit if there are Yearn tokens in the escrow (only 1 strategy at a time)
     */
    function depositToConvex() external onlyBeneficiary {
        if (yearn.balanceOf(address(this)) > 0)
            revert CannotDepositToConvex(yearn.balanceOf(address(this)));
        uint256 tokenBal = token.balanceOf(address(this));
        stakedBalance += tokenBal;
        booster.deposit(pid, tokenBal, true);
    }

    /**
     * @notice Deposit token balance in the escrow into Yearn
     * @dev Cannot deposit if there are Convex tokens in the escrow (only 1 strategy at a time)
     */
    function depositToYearn() external onlyBeneficiary {
        if (stakedBalance > 0) revert CannotDepositToYearn(stakedBalance);
        yearn.deposit(token.balanceOf(address(this)), address(this));
    }

    /**
     * @notice Withdraw all tokens from Yearn
     * @return lpAmount The amount of tokens withdrawn from Yearn
     */
    function withdrawFromYearn()
        external
        onlyBeneficiary
        returns (uint256 lpAmount)
    {
        return _fullWithdrawFromYearn();
    }

    /**
     * @notice Withdraw all tokens from Convex
     * @return lpAmount The amount of tokens withdrawn from Convex
     */
    function withdrawFromConvex()
        external
        onlyBeneficiary
        returns (uint256 lpAmount)
    {
        return _fullWithdrawFromConvex();
    }

    /**
     * @notice Move all tokens deposited into Convex to Yearn
     * @dev Will move all tokens from Convex to Yearn, including extra lp tokens that might be in the escrow if useAll is true
     * @param useAll If true, deposit the full balance in the escrow
     * @return lpAmount The amount of tokens deposited into Yearn
     */
    function moveFromConvexToYearn(
        bool useAll
    ) external onlyBeneficiary returns (uint256 lpAmount) {
        lpAmount = _fullWithdrawFromConvex();

        if (useAll) lpAmount = token.balanceOf(address(this));

        yearn.deposit(lpAmount, address(this));
    }

    /**
     * @notice Move all tokens deposited into Yearn to Convex
     * @dev Will move all tokens from Yearn to Convex, including extra lp tokens that might be in the escrow if useAll is true
     * @param useAll If true, deposit the full balance in the escrow
     * @return lpAmount The amount of tokens deposited into Convex
     */
    function moveFromYearnToConvex(
        bool useAll
    ) external onlyBeneficiary returns (uint256 lpAmount) {
        lpAmount = _fullWithdrawFromYearn();

        if (useAll) lpAmount = token.balanceOf(address(this));

        stakedBalance += lpAmount;
        booster.deposit(pid, lpAmount, true);
    }

    function _fullWithdrawFromYearn() internal returns (uint256 lpAmount) {
        lpAmount = yearn.withdraw(
            yearn.balanceOf(address(this)),
            address(this)
        );
    }

    function _fullWithdrawFromConvex() internal returns (uint256 lpAmount) {
        lpAmount = stakedBalance;
        stakedBalance = 0;
        rewardPool.withdrawAndUnwrap(lpAmount, false);
    }
}
