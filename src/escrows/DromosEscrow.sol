// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

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
 *      Clone-safe under ReentrancyGuard: a clone never runs the constructor, so `_status` starts at 0,
 *      which `nonReentrant` treats as not-entered.
 * @dev INVARIANT: this escrow must never grant a gauge withdrawal allowance to anyone, i.e. it must never
 *      call the gauge's `approve` or `setApprovalForAll`. `Gauge.withdrawFrom(_lp, _account)` sends the
 *      unstaked principal to `msg.sender`, so any operator holding such an allowance could withdraw this
 *      escrow's staked collateral directly to itself. The only approval this contract ever grants is the
 *      collateral ERC20 allowance to the gauge, set in `initialize`.
 */
contract DromosEscrow is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error AlreadyInitialized();
    error CannotSweepCollateral();
    error InvalidGauge();
    error InvalidReceiver();
    error OnlyBeneficiary();
    error OnlyBeneficiaryOrAllowlist();
    error OnlyMarket();
    error OnlyMarketOrBeneficiary();
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
    event Stake(address indexed caller, uint256 amount);

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

    modifier onlyMarketOrBeneficiary() {
        if (msg.sender != market && msg.sender != beneficiary) {
            revert OnlyMarketOrBeneficiary();
        }
        _;
    }

    /**
     * @param _gauge The Dromos V2 gauge this implementation stakes into.
     * @param _rewardToken The gauge's emission token, minted by the voter.
     * @dev `_rewardToken != stakingToken` is security-critical, not hygiene: `pay` forwards the escrow's
     *      entire `rewardToken` balance to the beneficiary, so if the two were the same that forward would
     *      hand over the borrower's collateral.
     */
    constructor(address _gauge, address _rewardToken) {
        if (_gauge.code.length == 0) revert InvalidGauge();

        gauge = IDromosGauge(_gauge);

        address _token = gauge.stakingToken();
        if (_token == address(0)) revert InvalidGauge();

        if (_rewardToken == address(0) || _rewardToken == _token) revert UnsafeRewardToken();

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
        if (_beneficiary == address(0) || _beneficiary == address(this)) {
            revert InvalidReceiver();
        }

        market = msg.sender;
        beneficiary = _beneficiary;

        token.forceApprove(address(gauge), type(uint256).max);
    }

    /**
     * @notice Transfers collateral to a recipient, unstaking only the amount required.
     * @dev Only the market may call this function. The gauge force-claims emissions to `msg.sender` (this
     *      escrow) on withdrawal, so the emissions it delivers are forwarded straight to the beneficiary
     *      afterwards. No separate claim is made: that would be a second, redundant trip through the
     *      gauge's voter settlement chain for the same emissions.
     * @dev The forward sends the escrow's entire `rewardToken` balance, so it also picks up anything left
     *      here by a donation or an earlier transfer that never happened.
     * @dev ACCEPTED RISK: the forward is not fault-tolerant. `rewardToken` is assumed transferable, so a
     *      beneficiary that cannot receive it would block its own withdrawal and liquidation. The Dromos
     *      emission token is protocol-controlled and has no blocklist, which is what makes this safe.
     * @dev `pay` is not independent of the gauge's voter either: `gauge.withdraw` runs the settlement chain
     *      and cannot be tolerated, because its result is the collateral.
     */
    function pay(address recipient, uint256 amount) external nonReentrant {
        if (msg.sender != market) revert OnlyMarket();

        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance < amount) {
            gauge.withdraw(amount - tokenBalance);

            uint256 rewardBalance = rewardToken.balanceOf(address(this));
            if (rewardBalance != 0) {
                rewardToken.safeTransfer(beneficiary, rewardBalance);
                emit Claim(msg.sender, beneficiary, rewardBalance);
            }
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
     * @notice Stakes collateral held by the escrow, but only into an empty gauge position.
     * @dev A Dromos deposit resets the early-unstake penalty timer across the escrow's entire stake, and the
     *      penalty is applied retroactively to emissions banked before the reset. Staking is therefore
     *      restricted to an empty position, which the gauge guarantees has nothing to lose: `_withdraw`
     *      claims emissions (clearing `rewards`) before decrementing, and deletes `depositBlock` once the
     *      balance reaches zero. With a live position this is a no-op, and the beneficiary opts into the
     *      reset explicitly through `depositAndStake`.
     * @dev Never reverts on the skip path: the market invokes this inside `deposit`, so a revert here would
     *      block deposits entirely.
     */
    function onDeposit() external onlyMarketOrBeneficiary {
        if (gauge.balanceOf(address(this)) != 0) return;

        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance == 0) return;

        gauge.deposit(tokenBalance);
        emit Stake(msg.sender, tokenBalance);
    }

    /**
     * @notice Pulls collateral from the beneficiary and stakes the escrow's entire balance.
     * @dev Resets the gauge's early-unstake penalty timer over the whole position, which retroactively
     *      penalises emissions already banked. Call `claim` first when past the penalty window; while inside
     *      it, banked emissions stay recoverable by waiting the window out, so the choice is the
     *      beneficiary's to make.
     * @dev Collateral moves escrow-side, so no `Market.Deposit` event is emitted.
     * @param amount Collateral to pull from the beneficiary. Pass 0 to stake only what the escrow holds.
     */
    function depositAndStake(uint256 amount) external onlyBeneficiary nonReentrant {
        if (amount != 0) {
            token.safeTransferFrom(msg.sender, address(this), amount);
        }

        uint256 tokenBalance = token.balanceOf(address(this));
        if (tokenBalance == 0) return;

        gauge.deposit(tokenBalance);
        emit Stake(msg.sender, tokenBalance);
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

    /**
     * @notice Recovers tokens held by this escrow that are not collateral.
     * @dev Covers emissions left here by a failed claim in `pay`, and any token sent here by mistake.
     *      Refusing the collateral token is the security-critical invariant, and is the successor to the
     *      `rewardToken != stakingToken` check the original design carried: the sweep must never be able to
     *      reach the borrower's collateral.
     * @param stuck The token to recover. Must not be the collateral token.
     * @param receiver The address receiving the recovered tokens.
     */
    function sweep(IERC20 stuck, address receiver) external onlyBeneficiaryOrAllowlist {
        if (address(stuck) == address(token)) revert CannotSweepCollateral();
        if (receiver == address(0) || receiver == address(this)) {
            revert InvalidReceiver();
        }

        stuck.safeTransfer(receiver, stuck.balanceOf(address(this)));
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
