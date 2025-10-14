// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface IBooster {
    function createVault(
        uint256 _pid
    ) external returns (address);
}

interface IVault {
    function deposit(uint256 _amount) external;
    function withdraw(uint256 _shares) external;
    function stakingToken() external view returns (address);
    function gaugeAddress() external view returns (address);
    function getReward() external;
}

interface IGauge {
    function getActiveRewardTokens() external view returns (address[] memory);
}
/**
 * @notice Escrow contract implementation to stake Curve LP tokens in FXN Convex and claim FXN and other rewards
 */

contract FXNConvexEscrow {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error OnlyMarket();
    error OnlyBeneficiary();
    error OnlyBeneficiaryOrAllowlist();

    uint256 public immutable pid;

    IBooster public immutable booster;
    IERC20 public immutable fxn;

    IERC20 public gauge;
    IVault public vault;
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
        address _booster,
        address _fxn,
        uint256 _pid
    ) {
        booster = IBooster(_booster);
        fxn = IERC20(_fxn);
        pid = _pid;
    }

    /**
    @notice Initialize escrow with a token
    @dev Must be called right after proxy is created.
    @param _token The IERC20 token representing LP token to be staked
    @param _beneficiary The beneficiary who the token is staked on behalf
    */
    function initialize(IERC20 _token, address _beneficiary) public {
        if (market != address(0)) revert AlreadyInitialized();
        market = msg.sender;
        token = _token;
        beneficiary = _beneficiary;
        vault = IVault(booster.createVault(pid));
        token.approve(address(vault), type(uint).max);
        require(token == IERC20(vault.stakingToken()), "Wrong token");
        gauge = IERC20(vault.gaugeAddress()); // receipt token that goes into the vault
    }

    /**
    @notice Withdraws the receipt token from the vault and transfers the associated ERC20 token to a recipient.
    @dev Will first try to pay from the escrow balance, if not enough or any, will try to pay the missing amount withdrawing from the vault.
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

        
        uint256 gaugeBalance = gauge.balanceOf(address(vault));
        if (gaugeBalance > 0) {
            uint256 missingAmount = amount - tokenBal;
            uint256 withdrawAmount = gaugeBalance > missingAmount
                ? missingAmount
                : gaugeBalance;
            
            vault.withdraw(withdrawAmount);
        }

        token.safeTransfer(recipient, amount);
    }

    /**
    @notice Get the token balance of the escrow
    @return Uint representing the token balance of the escrow
    */
    function balance() public view returns (uint256) {
        return
            gauge.balanceOf(address(vault)) +
            token.balanceOf(address(this));
    }

    /**
    @notice Function called by market on deposit. Stakes deposited collateral into FXN Convex gauge via vault
    @dev This function should remain callable by anyone to handle direct inbound transfers.
    */
    function onDeposit() public {
        uint256 tokenBal = token.balanceOf(address(this));
        if (tokenBal == 0) return;
        vault.deposit(tokenBal);
    }

    /**
    @notice Claims reward tokens to the specified address. Only callable by beneficiary and allowlisted addresses
    @param to Address to send claimed rewards to
    */
    function claimTo(address to) public onlyBeneficiaryOrAllowlist {
        //Claim rewards
        vault.getReward();
        //Send fxn balance
        uint256 fxnBal = fxn.balanceOf(address(this));
        if (fxnBal != 0) fxn.safeTransfer(to, fxnBal);

        //Send contract balance of extra rewards (including CRV and CVX)
        IGauge fxnGauge = IGauge(address(gauge));
        address[] memory extraRewards = fxnGauge.getActiveRewardTokens();
        if (extraRewards.length == 0) return;
        for (uint256 i; i < extraRewards.length; ++i) {
            // Avoid sending collateral token if it is added as a reward
            if (extraRewards[i] == address(token)) continue;
            uint256 rewardBal = IERC20(extraRewards[i]).balanceOf(address(this));
            if (rewardBal > 0) {
                //Use safe transfer in case bad reward token is added
                IERC20(extraRewards[i]).safeTransfer(to, rewardBal);
            }
        }
    }
    

    /**
    @notice Claims reward tokens to the message sender. Only callable by beneficiary
    */
    function claim() external onlyBeneficiary {
        claimTo(msg.sender);
    }

    /**
    @notice Allow address to claim on behalf of the beneficiary to any address
    @param allowee Address that are allowed to claim on behalf of the beneficiary
    @dev Can only be called by the beneficiary
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
