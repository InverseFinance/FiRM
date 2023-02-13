// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Caution. We assume all failed transfers cause reverts and ignore the returned bool.
interface IERC20 {
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
    function delegate(address delegatee) external;
    function delegates(address delegator) external view returns (address delegatee);
}

interface DelegateRegistry {
    function delegation(address, bytes32) external view returns (address);
    function setDelegate(bytes32 id, address delegate) external;
    function clearDelegate(bytes32 id) external;
}

/**
@title Snapshot Gov Token Escrow
@notice Collateral is stored in unique escrow contracts for every user and every market.
 This specific escrow is meant to allow the beneficiary to delegate votes in the snapshot system, unlike pooled deposit protocols.
@dev Caution: This is a proxy implementation. Follow proxy pattern best practices
*/
contract SnapshotGovTokenEscrow {
    address public market;
    IERC20 public token;
    address public beneficiary;
    DelegateRegistry public constant delegateRegistry = DelegateRegistry(0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446);

    /**
    @notice Initialize escrow with a token
    @dev Must be called right after proxy is created.
    @param _token The IERC20 token representing the governance token
    @param _beneficiary The beneficiary who may delegate snapshot token voting power
    */
    function initialize(IERC20 _token, address _beneficiary) public {
        require(market == address(0), "ALREADY INITIALIZED");
        market = msg.sender;
        token = _token;
        beneficiary = _beneficiary;
        delegateRegistry.setDelegate(bytes32(0), _beneficiary);
    }

    /**
    @notice Transfers the associated ERC20 token to a recipient.
    @param recipient The address to receive payment from the escrow
    @param amount The amount of ERC20 token to be transferred.
    */
    function pay(address recipient, uint amount) public {
        require(msg.sender == market, "ONLY MARKET");
        token.transfer(recipient, amount);
    }

    /**
    @notice Get the token balance of the escrow
    @return Uint representing the INV token balance of the escrow including the additional INV accrued from xINV
    */
    function balance() public view returns (uint) {
        return token.balanceOf(address(this));
    }

    function delegatee() public view returns (address) {
        return delegateRegistry.delegation(address(this), bytes32(0));
    }

    /**
    @notice Function called by market on deposit. Function is empty for this escrow.
    @dev This function should remain callable by anyone to handle direct inbound transfers.
    */
    function onDeposit() public {

    }

    /**
    @notice Delegates voting power of the underlying xINV.
    @param delegatee The address to be delegated voting power
    */
    function delegate(address delegatee) public {
        require(msg.sender == beneficiary);
        delegateRegistry.setDelegate(bytes32(0), delegatee);
    }
}
