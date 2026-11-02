// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract CvxRecoveryToken is ERC20 {
    bool public failTransfers;

    constructor() ERC20("Test token", "TEST") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setFailTransfers(bool fail) external {
        failTransfers = fail;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (failTransfers) return false;
        return super.transfer(to, amount);
    }
}

contract CvxSecondaryPoolMock {
    IERC20 constant CVXCRV = IERC20(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7);
    mapping(address => uint256) public balanceOf;
    bool public failWithdraw;
    bool public lastClaim;
    uint256 public withdrawalCalls;

    function setFailWithdraw(bool fail) external {
        failWithdraw = fail;
    }

    function stakingToken() external pure returns (address) {
        return address(CVXCRV);
    }

    function stakeFor(address account, uint256 amount) external {
        require(amount > 0, "Cannot stake 0");
        require(CVXCRV.transferFrom(msg.sender, address(this), amount));
        balanceOf[account] += amount;
    }

    function withdraw(uint256 amount, bool claim) external returns (bool) {
        require(amount > 0, "Cannot withdraw 0");
        if (failWithdraw) return false;
        balanceOf[msg.sender] -= amount;
        withdrawalCalls++;
        lastClaim = claim;
        require(CVXCRV.transfer(msg.sender, amount));
        return true;
    }
}

contract CvxOuterPoolMock {
    IERC20 constant CVX = IERC20(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    IERC20 constant CVXCRV = IERC20(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7);
    address public constant cvxCrvRewards = 0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public earned;
    address public extraToken;
    bool public lastStake;
    address public lastAccount;

    function setEarned(address account, uint256 amount) external {
        earned[account] = amount;
    }

    function setExtraToken(address token) external {
        extraToken = token;
    }

    function extraRewardsLength() external view returns (uint256) {
        return extraToken == address(0) ? 0 : 1;
    }

    function stake(uint256 amount) external {
        require(amount > 0, "Cannot stake 0");
        require(CVX.transferFrom(msg.sender, address(this), amount));
        balanceOf[msg.sender] += amount;
    }

    function withdraw(uint256 amount, bool) external {
        require(amount > 0, "Cannot withdraw 0");
        balanceOf[msg.sender] -= amount;
        require(CVX.transfer(msg.sender, amount));
    }

    // Matches Convex's permissionless claim-on-behalf and stakeFor behavior.
    function getReward(address account, bool claimExtras, bool stakeReward) external {
        lastStake = stakeReward;
        lastAccount = account;
        uint256 reward = earned[account];
        earned[account] = 0;
        if (reward > 0) {
            if (stakeReward) {
                CVXCRV.approve(cvxCrvRewards, reward);
                CvxSecondaryPoolMock(cvxCrvRewards).stakeFor(account, reward);
            } else {
                require(CVXCRV.transfer(account, reward));
            }
        }
        if (claimExtras && extraToken != address(0)) {
            require(IERC20(extraToken).transfer(account, 1 ether));
        }
    }
}

contract CvxMarketSupportMock {
    function deficitOf(address) external pure returns (uint256) {
        return 0;
    }
    function onBorrow(address, uint256) external {}
    function onRepay(address, uint256) external {}

    function getPrice(address, uint256) external pure returns (uint256) {
        return 1 ether;
    }

    function viewPrice(address, uint256) external pure returns (uint256) {
        return 1 ether;
    }
}
