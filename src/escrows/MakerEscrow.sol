// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

///  * @dev Caution: We assume all failed transfers cause reverts and ignore the returned bool.
interface IERC20 {
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
}

interface IVoteDelegate {
    function lock(uint) external;
    function free(uint) external;
    function stake(address) external returns(uint);
}

interface IVoteDelegateFactory {
    function isDelegate(address) external returns(bool);
    function delegate(address) external returns(address);
}

/**
 * @title Simple ERC20 Escrow
 * @notice Collateral is stored in unique escrow contracts for every user and every market.
 * @dev Caution: This is a proxy implementation. Follow proxy pattern best practices
 */
contract MakerEscrow {
    address public market;
    address public delegate;
    address public beneficiary;
    IVoteDelegateFactory public constant voteDelegateFactory = IVoteDelegateFactory(0xD897F108670903D1d6070fcf818f9db3615AF272);
    IERC20 public token;
   
    error OnlyBeneficiary();
    error AddressNotDelegate();

    /**
     * @notice Initialize escrow with a token
     * @dev Must be called right after proxy is created
     * @param _token The IERC20 token to be stored in this specific escrow
     * @param _beneficiary Address of the owner of the escrow
     */
    function initialize(IERC20 _token, address _beneficiary) public {
        require(market == address(0), "ALREADY INITIALIZED");
        market = msg.sender;
        token = _token;
        beneficiary = _beneficiary;
    }
    
    /**
     * @notice Transfers the associated ERC20 token to a recipient.
     * @param recipient The address to receive payment from the escrow
     * @param amount The amount of ERC20 token to be transferred.
     */
    function pay(address recipient, uint amount) public {
        require(msg.sender == market, "ONLY MARKET");
        token.transfer(recipient, amount);
    }

    /**
     * @notice Get the token balance of the escrow
     * @return Uint representing the token balance of the escrow
     */
    function balance() public view returns (uint) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Function called by market on deposit. Function is empty for this escrow.
     * @dev This function should remain callable by anyone to handle direct inbound transfers.
     */
    function onDeposit() external {
        uint mkrBal = token.balanceOf(address(this));
        if(delegate != address(0)){
            //TODO: Check if this will fail if some mkr has already been locked/delegated
            IVoteDelegate voteDelegate = IVoteDelegate(voteDelegateFactory.delegate(delegate));
            uint staked = voteDelegate.stake(address(this));
            voteDelegate.lock(mkrBal - staked);
        } else if(voteDelegateFactory.isDelegate(beneficiary)){
            delegate = beneficiary;
            IVoteDelegate voteDelegate = IVoteDelegate(voteDelegateFactory.delegate(beneficiary));
            uint staked = voteDelegate.stake(address(this));
            voteDelegate.lock(mkrBal - staked);
        }
    }

    /**
     * @notice Delegates all voting power to the address `_newDelegate`
     * @dev `_newDelegate` is not the address of a `VoteDelegate` contract but the owner of such a contract.
     * @param _newDelegate Address of the new delegate to delegate to
     */
    function delegateTo(address _newDelegate) external {
        if(msg.sender != beneficiary) revert OnlyBeneficiary();
        if(!voteDelegateFactory.isDelegate(_newDelegate)) revert AddressNotDelegate();
        IVoteDelegate voteDelegate;
        if(delegate != address(0)){
            voteDelegate = IVoteDelegate(voteDelegateFactory.delegate(delegate));
            uint stake = voteDelegate.stake(address(this));
            voteDelegate.free(stake);
        }
        delegate = _newDelegate;
        uint mkrBal = token.balanceOf(address(this));
        voteDelegate = IVoteDelegate(voteDelegateFactory.delegate(delegate));
        voteDelegate.lock(mkrBal);
    }

    /**
     * @notice Undelegates from the current delegate
     */
    function undelegate() external {
        if(msg.sender != beneficiary) revert OnlyBeneficiary();
        if(delegate != address(0)){
            IVoteDelegate voteDelegate = IVoteDelegate(voteDelegateFactory.delegate(delegate));
            uint stake = voteDelegate.stake(address(this));
            voteDelegate.free(stake);
            delegate = address(0);
        }
    }
}
