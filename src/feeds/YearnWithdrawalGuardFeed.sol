// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {ERC4626Feed} from "src/feeds/ERC4626Feed.sol";

interface IYearnV3WithdrawalVault is IERC4626 {
    function maxWithdraw(address owner, uint256 maxLoss) external view returns (uint256);
}

/// @notice Keeps the ERC4626 feed price and marks its round stale when the staking vault cannot withdraw enough backing.
contract YearnWithdrawalGuardFeed {
    error InvalidShortfallBps();

    uint256 private constant BPS = 10_000;
    uint256 private constant CAPACITY_CHECK_GAS = 300_000;

    ERC4626Feed public immutable feed;
    IERC4626 public immutable vault;
    IYearnV3WithdrawalVault public immutable backingVault;
    uint256 public immutable maxShortfallBps;

    constructor(address _feed, uint256 _maxShortfallBps) {
        if (_maxShortfallBps >= BPS) revert InvalidShortfallBps();
        feed = ERC4626Feed(_feed);
        vault = feed.vault();
        backingVault = IYearnV3WithdrawalVault(vault.asset());
        maxShortfallBps = _maxShortfallBps;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (roundId, price, startedAt, updatedAt, answeredInRound) = feed.latestRoundData();
        if (updatedAt == 0) return (roundId, price, startedAt, updatedAt, answeredInRound);

        // Isolate the capacity reads so a failure cannot suppress the liquidation price.
        try this.hasSufficientWithdrawalCapacity{gas: CAPACITY_CHECK_GAS}() returns (bool sufficient) {
            if (!sufficient) updatedAt = 0;
        } catch {
            updatedAt = 0;
        }
    }

    function hasSufficientWithdrawalCapacity() external view returns (bool) {
        uint256 backingShares = backingVault.balanceOf(address(vault));
        uint256 quotedAssets = backingVault.previewRedeem(backingShares);
        if (quotedAssets == 0) return false;

        uint256 minAssets = Math.mulDiv(quotedAssets, BPS - maxShortfallBps, BPS, Math.Rounding.Ceil);
        return backingVault.maxWithdraw(address(vault), 0) >= minAssets;
    }

    function latestAnswer() external view returns (int256) {
        return feed.latestAnswer();
    }

    function decimals() external view returns (uint8) {
        return feed.decimals();
    }

    function description() external view returns (string memory) {
        return feed.description();
    }
}
