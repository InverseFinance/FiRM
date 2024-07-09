// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYearnVaultV2} from "src/interfaces/IYearnVaultV2.sol";
import {YearnVaultV2Helper} from "src/util/YearnVaultV2Helper.sol";
import {IRewardPool} from "src/interfaces/IRewardPool.sol";
import {IConvexBooster} from "src/interfaces/IConvexBooster.sol";
import {IVirtualBalanceRewardPool} from "src/interfaces/IVirtualBalanceRewardPool.sol";

// StakingWrapper interface for pools with pid 151+
interface IStakingWrapper {
    function token() external returns (address);
}

contract LPCurveYearnV2Escrow {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error OnlyMarket();
    error OnlyBeneficiary();
    error OnlyBeneficiaryOrAllowlist();
    error LpToPayDeltaExceed();

    uint256 public immutable pid;

    IRewardPool public immutable rewardPool;
    IConvexBooster public immutable booster;
    IYearnVaultV2 public immutable yearn;
    IERC20 public immutable cvx;
    IERC20 public immutable crv;
    /// @dev Wei delta for Yearn Vault V2 withdrawals
    uint256 public constant weiDelta = 2;

    address public market;
    IERC20 public token;
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

    constructor(
        address _rewardPool,
        address _booster,
        address _yearn,
        address _cvx,
        address _crv,
        uint256 _pid
    ) {
        rewardPool = IRewardPool(_rewardPool);
        booster = IConvexBooster(_booster);
        yearn = IYearnVaultV2(_yearn);
        cvx = IERC20(_cvx);
        crv = IERC20(_crv);
        pid = _pid;
    }

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

        if (tokenBal >= amount) {
            token.safeTransfer(recipient, amount);
            return;
        }

        uint256 missingAmount = amount - tokenBal;
        uint256 convexBalance = IERC20(address(rewardPool)).balanceOf(
            address(this)
        );
        if (convexBalance > 0 && missingAmount > 0) {
            uint256 withdrawAmount = convexBalance > missingAmount
                ? missingAmount
                : convexBalance;
            missingAmount -= withdrawAmount;
            rewardPool.withdrawAndUnwrap(withdrawAmount, false);
        }

        uint yearnBal = yearn.balanceOf(address(this));
        if (yearnBal > 0 && missingAmount > 0) {
            uint256 maxWithdraw = YearnVaultV2Helper.collateralToAsset(
                yearn,
                yearnBal
            );
            uint256 withdrawAmount = maxWithdraw > missingAmount
                ? missingAmount
                : maxWithdraw;

            uint256 collateralAmount;
            if (withdrawAmount == maxWithdraw) collateralAmount = yearnBal;
            else
                collateralAmount = YearnVaultV2Helper.assetToCollateral(
                    yearn,
                    withdrawAmount + weiDelta
                );
            // Withdraw from Yearn
            yearn.withdraw(collateralAmount, address(this));

            uint256 lpToPay = token.balanceOf(address(this));
            if (lpToPay != amount) {
                _ensureLimitsOrRevert(lpToPay, amount);
                amount = lpToPay;
            }
        }
        token.safeTransfer(recipient, amount);
    }

    /**
    @notice Get the token balance of the escrow
    @return Uint representing the staked balance of the escrow
    */
    function balance() public view returns (uint) {
        return
            rewardPool.balanceOf(address(this)) +
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
            IERC20 rewardToken;
            if (pid >= 151) {
                rewardToken = IERC20(
                    IStakingWrapper(address(virtualReward.rewardToken()))
                        .token()
                );
            } else {
                rewardToken = virtualReward.rewardToken();
            }

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
        if (yearn.balanceOf(address(this)) > 0) withdrawFromYearn();

        uint256 tokenBal = token.balanceOf(address(this));
        booster.deposit(pid, tokenBal, true);
    }

    /**
     * @notice Deposit token balance in the escrow into Yearn
     * @dev Cannot deposit if there are Convex tokens in the escrow (only 1 strategy at a time)
     */
    function depositToYearn() external onlyBeneficiary {
        uint256 convexBalance = IERC20(address(rewardPool)).balanceOf(
            address(this)
        );
        if (convexBalance > 0) withdrawFromConvex();
        yearn.deposit(token.balanceOf(address(this)), address(this));
    }

    /**
     * @notice Withdraw all tokens from Yearn
     * @return lpAmount The amount of tokens withdrawn from Yearn
     */
    function withdrawFromYearn()
        public
        onlyBeneficiary
        returns (uint256 lpAmount)
    {
        return yearn.withdraw(yearn.balanceOf(address(this)), address(this));
    }

    /**
     * @notice Withdraw all tokens from Convex
     * @return lpAmount The amount of tokens withdrawn from Convex
     */
    function withdrawFromConvex()
        public
        onlyBeneficiary
        returns (uint256 lpAmount)
    {
        lpAmount = rewardPool.balanceOf(address(this));
        rewardPool.withdrawAndUnwrap(lpAmount, false);
    }

    /**
     * @notice Ensure the limits are not exceeded, cannot be higher than the amount + weiDelta or lower than the amount
     * @param lpToPay The LP tokens available to pay
     * @param amount The amount asked to be paid
     */
    function _ensureLimitsOrRevert(
        uint256 lpToPay,
        uint256 amount
    ) internal pure {
        // If the LP amount to pay is higher than the amount includind weiDelta or is lower tha amount, revert
        if (lpToPay > amount + weiDelta || lpToPay < amount)
            revert LpToPayDeltaExceed();
    }
}
