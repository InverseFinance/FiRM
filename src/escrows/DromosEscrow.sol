// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Interface reference: Aerodrome vAMM-WETH/USDC Pool Gauge on Base.
/// https://basescan.org/address/0x519BBD1Dd8C6A94C46080E24f316c14Ee758C025#code
interface IDromosGauge {
    function stakingToken() external view returns (address);
    function rewardToken() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward(address account) external;
}

/**
 * @title Dromos Escrow
 * @notice Stakes a borrower's Solidly-like LP collateral in a Dromos-compatible gauge.
 * @dev This contract is used as a proxy implementation. Each implementation supports one immutable gauge.
 */
contract DromosEscrow {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error InvalidGauge();
    error InvalidReceiver();
    error OnlyBeneficiary();
    error OnlyBeneficiaryOrAllowlist();
    error OnlyMarket();
    error UnsafeRewardToken();
    error WrongCollateral();

    IDromosGauge public immutable gauge;
    IERC20 public immutable token;
    IERC20 public immutable rewardToken;

    address public market;
    address public beneficiary;

    mapping(address claimer => bool isAllowed) public allowlist;

    event Claim(address indexed caller, address indexed receiver, uint256 amount);
    event SetClaimer(address indexed claimer, bool isAllowed);

    modifier onlyBeneficiary() {
        if (msg.sender != beneficiary) revert OnlyBeneficiary();
        _;
    }

    modifier onlyBeneficiaryOrAllowlist() {
        if (msg.sender != beneficiary && !allowlist[msg.sender]) {
            revert OnlyBeneficiaryOrAllowlist();
        }
        _;
    }

    constructor(address _gauge) {
        if (_gauge.code.length == 0) revert InvalidGauge();

        gauge = IDromosGauge(_gauge);

        address _token = gauge.stakingToken();
        address _rewardToken = gauge.rewardToken();
        if (_token == address(0) || _rewardToken == address(0)) {
            revert InvalidGauge();
        }
        if (_token == _rewardToken) revert UnsafeRewardToken();

        token = IERC20(_token);
        rewardToken = IERC20(_rewardToken);
    }

    /**
     * @notice Initializes an escrow clone.
     * @param _token The market's collateral token.
     * @param _beneficiary The borrower entitled to the gauge emissions.
     */
    function initialize(IERC20 _token, address _beneficiary) external {
        if (market != address(0)) revert AlreadyInitialized();
        if (address(_token) != address(token)) revert WrongCollateral();

        market = msg.sender;
        beneficiary = _beneficiary;

        token.forceApprove(address(gauge), type(uint256).max);
    }

    /**
     * @notice Transfers collateral to a recipient, unstaking only the amount required.
     * @dev Only the market may call this function. Gauge emissions are not claimed.
     */
    function pay(address recipient, uint256 amount) external {
        if (msg.sender != market) revert OnlyMarket();

        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance < amount) {
            gauge.withdraw(amount - tokenBalance);
        }

        token.safeTransfer(recipient, amount);
    }

    /**
     * @notice Returns the escrow's total unstaked and gauge-staked collateral.
     */
    function balance() external view returns (uint256) {
        return token.balanceOf(address(this)) + gauge.balanceOf(address(this));
    }

    /**
     * @notice Stakes all collateral currently held by the escrow.
     * @dev Permissionless so direct collateral transfers can subsequently be staked.
     */
    function onDeposit() external {
        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance == 0) return;

        gauge.deposit(tokenBalance);
    }

    /**
     * @notice Claims gauge emissions to the beneficiary.
     */
    function claim() external onlyBeneficiary {
        _claim(beneficiary);
    }

    /**
     * @notice Claims gauge emissions to a specified receiver.
     * @dev Callable by the beneficiary or an allowlisted claimer.
     */
    function claimTo(address receiver) external onlyBeneficiaryOrAllowlist {
        _claim(receiver);
    }

    /**
     * @notice Allows or disallows an address to claim emissions on the beneficiary's behalf.
     */
    function setClaimer(address claimer, bool isAllowed) external onlyBeneficiary {
        allowlist[claimer] = isAllowed;
        emit SetClaimer(claimer, isAllowed);
    }

    function _claim(address receiver) internal {
        if (receiver == address(0) || receiver == address(this)) {
            revert InvalidReceiver();
        }

        gauge.getReward(address(this));

        uint256 amount = rewardToken.balanceOf(address(this));
        if (amount != 0) rewardToken.safeTransfer(receiver, amount);

        emit Claim(msg.sender, receiver, amount);
    }
}
