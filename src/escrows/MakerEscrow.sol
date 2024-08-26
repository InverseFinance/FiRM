// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IERC20.sol";

///  * @dev Caution: We assume all failed transfers cause reverts and ignore the returned bool.
interface IVoteDelegate {
    function lock(uint) external;
    function free(uint) external;
    function stake(address) external returns(uint);
    function delegate() external returns(address);
}

interface IVoteDelegateFactory {
    function isDelegate(address) external returns(bool);
    function delegates(address) external returns(address);
}

/**
 * @title Simple ERC20 Escrow
 * @notice Collateral is stored in unique escrow contracts for every user and every market.
 * @dev Caution: This is a proxy implementation. Follow proxy pattern best practices
 */
contract MakerEscrow {
    address public market;
    address public beneficiary;
    IVoteDelegate public voteDelegate;
    IVoteDelegateFactory public constant voteDelegateFactory = IVoteDelegateFactory(0xD897F108670903D1d6070fcf818f9db3615AF272);
    address public constant chief = 0x0a3f6849f78076aefaDf113F5BED87720274dDC0;
    IERC20 public constant iou = IERC20(0xA618E54de493ec29432EbD2CA7f14eFbF6Ac17F7);
    IERC20 public constant token = IERC20(0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2);
   
    error OnlyBeneficiary();

    /**
     * @notice Initialize escrow with a token
     * @dev Must be called right after proxy is created
     * @param _beneficiary Address of the owner of the escrow
     */
    function initialize(IERC20, address _beneficiary) public {
        require(market == address(0), "ALREADY INITIALIZED");
        market = msg.sender;
        beneficiary = _beneficiary;
    }
    
    /**
     * @notice Transfers the associated ERC20 token to a recipient.
     * @param recipient The address to receive payment from the escrow
     * @param amount The amount of ERC20 token to be transferred.
     */
    function pay(address recipient, uint amount) public {
        require(msg.sender == market, "ONLY MARKET");
        uint mkrBal = token.balanceOf(address(this));
        if(amount > mkrBal){
            voteDelegate.free(amount - mkrBal);
        }
        token.transfer(recipient, amount);
    }

    /**
     * @notice Get the token balance of the escrow
     * @return Uint representing the token balance of the escrow
     */
    function balance() public view returns (uint) {
        return token.balanceOf(address(this)) + iou.balanceOf(address(this));
    }

    /**
     * @notice Function called by market on deposit. Function is empty for this escrow.
     * @dev This function should remain callable by anyone to handle direct inbound transfers.
     */
    function onDeposit() external {
        uint mkrBal = token.balanceOf(address(this));
        if(address(voteDelegate) != address(0)){
            uint staked = voteDelegate.stake(address(this));
            voteDelegate.lock(mkrBal - staked);
        } else if(voteDelegateFactory.isDelegate(beneficiary)){
            _setVoteDelegate(
                IVoteDelegate(voteDelegateFactory.delegates(beneficiary))
            );
            voteDelegate.lock(mkrBal);
        }
    }

    /**
     * @notice Delegates all voting power to the address `_newDelegate`
     * @dev `_newDelegate` is not the address of a `VoteDelegate` contract but the owner of such a contract.
     * @param _newDelegate Address of the new delegate to delegate to
     */
    function delegateTo(address _newDelegate) external {
        if(msg.sender != beneficiary) revert OnlyBeneficiary();
        if(address(voteDelegate) != address(0)){
            uint stake = voteDelegate.stake(address(this));
            iou.approve(address(voteDelegate), stake);
            voteDelegate.free(stake);
        }
        uint mkrBal = token.balanceOf(address(this));
        _setVoteDelegate(
            IVoteDelegate(voteDelegateFactory.delegates(_newDelegate))
        );
        voteDelegate.lock(mkrBal);
    }

    function _setVoteDelegate(IVoteDelegate newVoteDelegate) internal {
        voteDelegate = newVoteDelegate;
        iou.approve(address(newVoteDelegate), type(uint).max);
        token.approve(address(newVoteDelegate), type(uint).max);
    }

    /**
     * @notice Undelegates from the current delegate
     */
    function undelegate() external {
        if(msg.sender != beneficiary) revert OnlyBeneficiary();
        if(address(voteDelegate) != address(0)){
            uint stake = voteDelegate.stake(address(this));
            voteDelegate.free(stake);
            voteDelegate = IVoteDelegate(address(0));
        }
    }

    /**
     * @notice Get the owner of the `voteDelegate` contract that is being delegated to.
     */
    function delegate() external returns(address){
        if(address(voteDelegate) != address(0)){
            return voteDelegate.delegate();
        } else {
            return address(0);
        }
    }
}
