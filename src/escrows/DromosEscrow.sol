// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @dev Interface reference: Dromos V2 gauge.
/// https://github.com/dromos-labs/metadex-public/blob/eb63050a866ac71a98a79095b18496018407aa22/V3/src/interfaces/gauges/IV2Gauge.sol
interface IDromosGauge {
    function stakingToken() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function claimEmissions(address account, address recipient) external;
}

/**
 * @title Dromos Escrow
 * @notice Stakes a borrower's V2 LP collateral in a Dromos gauge.
 * @dev This contract is used as a proxy implementation. Each implementation supports one immutable gauge.
 */
contract DromosEscrow {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error InvalidGauge();
    error InvalidReceiver();
    error OnlyBeneficiary();
    error OnlyBeneficiaryOrigin();
    error OnlyBeneficiaryOrAllowlist();
    error OnlyMarket();
    error OnlyMarketOrBeneficiary();
    error WrongCollateral();

    IDromosGauge public immutable gauge;
    IERC20 public immutable token;

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

    modifier onlyBeneficiaryOrigin() {
        if (tx.origin != beneficiary) revert OnlyBeneficiaryOrigin();
        _;
    }

    modifier onlyMarketOrBeneficiary() {
        if (msg.sender != market && msg.sender != beneficiary) {
            revert OnlyMarketOrBeneficiary();
        }
        _;
    }

    constructor(address _gauge) {
        if (_gauge.code.length == 0) revert InvalidGauge();

        gauge = IDromosGauge(_gauge);

        address _token = gauge.stakingToken();
        if (_token == address(0)) revert InvalidGauge();

        token = IERC20(_token);
    }

    /**
     * @notice Initializes an escrow clone.
     * @param _token The market's collateral token.
     * @param _beneficiary The borrower entitled to the gauge emissions.
     */
    function initialize(IERC20 _token, address _beneficiary) external {
        if (market != address(0)) revert AlreadyInitialized();
        if (address(_token) != address(token)) revert WrongCollateral();
        if (_beneficiary == address(0) || _beneficiary == address(this)) {
            revert InvalidReceiver();
        }

        market = msg.sender;
        beneficiary = _beneficiary;

        token.forceApprove(address(gauge), type(uint256).max);
    }

    /**
     * @notice Transfers collateral to a recipient, unstaking only the amount required.
     * @dev Only the market may call this function. Dromos withdrawals force an emissions claim, so pending
     *      emissions are claimed to the beneficiary before collateral is unstaked.
     */
    function pay(address recipient, uint256 amount) external {
        if (msg.sender != market) revert OnlyMarket();

        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance < amount) {
            _claim(beneficiary);
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
     * @dev Restricted because each Dromos deposit resets the early-penalty timer for the escrow's entire stake.
     *      The beneficiary-origin requirement prevents third parties from resetting the timer through the market's
     *      deposit-on-behalf path. This intentionally limits automatic staking to EOA beneficiary-originated calls.
     */
    function onDeposit() external onlyMarketOrBeneficiary onlyBeneficiaryOrigin {
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

        uint256 amount = gauge.earned(address(this));
        gauge.claimEmissions(address(this), receiver);

        emit Claim(msg.sender, receiver, amount);
    }
}
