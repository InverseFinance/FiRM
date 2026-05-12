// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMarket} from "src/interfaces/IMarket.sol";

interface IRewardVault is IERC20 {
    function deposit(uint256 assets, address receiver, address referrer) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function claim(address[] calldata tokens, address receiver) external returns (uint256[] memory amounts);
    function previewRedeem(uint256 shares) external view returns (uint256);
    function asset() external view returns (address);
    function ACCOUNTANT() external view returns (address);
    function gauge() external view returns (address);
}

interface IAccountant {
    function REWARD_TOKEN() external view returns (address);
    function claim(address[] calldata gauges, bytes[] calldata harvestData, address receiver) external;
}

contract StakeDaoEscrow {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error OnlyMarket();
    error OnlyBeneficiary();
    error OnlyBeneficiaryOrAllowlist();
    error WrongCollateral();
    error InvalidReceiver();

    IRewardVault public immutable rewardVault;
    IAccountant public immutable accountant;
    address public immutable gauge;
    address public immutable baseRewardToken;
    address public immutable treasury;

    address public market;
    IERC20 public token;
    address public beneficiary;

    mapping(address => bool) public allowlist;

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

    event SetClaimer(address indexed claimer, bool isAllowed);
    event Claim(address caller, address receiver, address[] tokens, address baseRewardToken, uint256[] amounts);

    constructor(address _rewardVault, address _treasury) {
        rewardVault = IRewardVault(_rewardVault);
        accountant = IAccountant(rewardVault.ACCOUNTANT());
        gauge = rewardVault.gauge();
        baseRewardToken = accountant.REWARD_TOKEN();
        treasury = _treasury;
    }

    /**
     * @notice Initialize escrow with a token
     * @dev Must be called right after proxy is created.
     * @param _token The market asset
     * @param _beneficiary The beneficiary who the token is staked on behalf
     */
    function initialize(IERC20 _token, address _beneficiary) public {
        if (market != address(0)) revert AlreadyInitialized();
        if (address(_token) != rewardVault.asset()) revert WrongCollateral();
        market = msg.sender;
        if (address(_token) != IMarket(market).collateral()) revert WrongCollateral();
        token = _token;
        token.approve(address(rewardVault), type(uint256).max);
        beneficiary = _beneficiary;
    }

    /**
     * @notice Withdraws the wrapped token from the reward pool and transfers the associated ERC20 token to a recipient.
     * @param recipient The address to receive payment from the escrow
     * @param amount The amount of ERC20 token to be transferred.
     */
    function pay(address recipient, uint256 amount) public {
        if (msg.sender != market) revert OnlyMarket();
        uint256 tokenBal = token.balanceOf(address(this));

        if (tokenBal < amount) {
            //Withdraw needed amount of tokens to this address
            rewardVault.withdraw(amount - tokenBal, address(this), address(this));
        }

        token.safeTransfer(recipient, amount);
    }

    /**
     * @notice Get the token balance of the escrow
     * @return Uint representing the token balance of the escrow
     */
    function balance() public view returns (uint256) {
        return rewardVault.previewRedeem(rewardVault.balanceOf(address(this))) + token.balanceOf(address(this));
    }

    /**
     * @notice Function called by market on deposit. Stakes deposited collateral into Stake DAO reward vault
     * @dev This function should remain callable by anyone to handle direct inbound transfers.
     */
    function onDeposit() public {
        uint256 tokenBal = token.balanceOf(address(this));
        if (tokenBal == 0) return;
        rewardVault.deposit(tokenBal, address(this), treasury);
    }

    /**
     * @notice Claims reward tokens to the specified address. Only callable by beneficiary and allowlisted addresses
     * @param tokens Array of reward token address to claim to `to` address
     * @param to Address to send claimed rewards to
     */
    function claim(address[] calldata tokens, address to) public onlyBeneficiaryOrAllowlist {
        _claim(tokens, to);
    }

    /**
     * @notice Claims reward tokens to the specified address. Only callable by beneficiary and allowlisted addresses
     * @param tokens Array of reward token address to claim to `to` address
     */
    function claim(address[] calldata tokens) public onlyBeneficiary {
        _claim(tokens, msg.sender);
    }

    /**
     * @notice Claims reward tokens to the message sender. Only callable by beneficiary
     * @param tokens Array of reward token addresses to claim
     */
    function _claim(address[] calldata tokens, address to) internal {
        if (to == address(0) || to == address(this)) revert InvalidReceiver();
        //Claim base reward token (crv, bal, etc.) when available.
        try accountant.claim(_gaugeArray(), new bytes[](0), to) {} catch {}
        //Claim extra reward tokens (cvx, etc.)
        uint256[] memory amounts = rewardVault.claim(tokens, to);
        emit Claim(msg.sender, to, tokens, baseRewardToken, amounts);
    }

    function _gaugeArray() internal view returns (address[] memory gauges) {
        gauges = new address[](1);
        gauges[0] = gauge;
    }

    /**
     * @notice Allow address to claim on behalf of the beneficiary to any address
     * @param claimer Address that is allowed or disallowed to claim
     * @param isAllowed whether `claimer` address is allowed to claim or not
     * @dev Can be used to build contracts for auto-compounding or auto-claiming
     */
    function setClaimer(address claimer, bool isAllowed) external onlyBeneficiary {
        allowlist[claimer] = isAllowed;
        emit SetClaimer(claimer, isAllowed);
    }
}
