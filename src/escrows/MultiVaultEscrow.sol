// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "src/escrows/VaultAllowlist.sol";

/**
 * @title Multi Vault Escrow
 * @notice Collateral is stored in unique escrow contracts for every user and every market.
 * @dev Caution: This is a proxy implementation. Follow proxy pattern best practices
 */
abstract contract MultiVaultEscrow {
    address public market;
    IERC20 public token;
    IERC4626 public activeVault;
    VaultAllowlist public immutable vaultAllowlist;
    address public beneficiary;

    modifier onlyBeneficiary {
        require(msg.sender == beneficiary, "ONLY BENEFICIARY");
        _; 
    }

    modifier onlyBeneficiaryOrAllowlist {
        require(msg.sender == beneficiary, "ONLY BENEFICIARY OR ALLOWED");
        _; 
    }

    event AllowClaim(address indexed allowedAddress, bool allowed);

    constructor(address _vaultAllowlist){
        vaultAllowlist = VaultAllowlist(_vaultAllowlist);
    }

    /**
     * @notice Initialize escrow with a token
     * @dev Must be called right after proxy is created.
     * @param _token The IERC20 token representing the governance token
     * @param _beneficiary The beneficiary who cvxCRV is staked on behalf
     */
    function initialize(IERC20 _token, address _beneficiary) public {
        require(market == address(0), "ALREADY INITIALIZED");
        market = msg.sender;

        if(address(vaultAllowlist.defaultVault(_beneficiary, _token)) != address(0)){
            _token.approve(address(activeVault), type(uint).max);
            activeVault = vaultAllowlist.defaultVault(_beneficiary, _token);
        }
        token = _token;
        beneficiary = _beneficiary;
        _initializeBase(_token, _beneficiary);
    }

    /**
     * @notice Withdraws the wrapped token from the reward pool and transfers the associated ERC20 token to a recipient.
     * @param recipient The address to receive payment from the escrow
     * @param amount The amount of ERC20 token to be transferred.
     */
    function pay(address recipient, uint amount) public {
        require(msg.sender == market, "ONLY MARKET");
        if(activeVault != IERC4626(address(0))){
            activeVault.withdraw(amount, recipient, address(this));
        } else {
            _withdrawBase(recipient, amount);
        }
    }

    /**
     * @notice Get the token balance of the escrow
     * @return Uint representing the staked balance of the escrow
     */
    function balance() public view returns (uint) {
        if(address(activeVault) == address(0)){
            return _balanceBase();
        }
        return activeVault.convertToAssets(activeVault.balanceOf(address(this))) + token.balanceOf(address(this));
    }

    /**
     * @notice Function called by market on deposit. Will deposit collateral into vault if one is active.
     * @dev This function should remain callable by anyone to handle direct inbound transfers.
     */
    function onDeposit() public {
        if(address(activeVault) != address(0)){
            uint tokenBal = token.balanceOf(address(this));
            activeVault.deposit(tokenBal, address(this));
        } else {
            _depositBase();
        }

    }

    /**
     * @notice Migrates assets from current `activeVault` to allowlisted `newVault`
     * @param newVault Address of the new vault to migrate collateral to. If address 0, collateral tokens will be stored directly in PCE
     */
    function changeVault(IERC4626 newVault) public onlyBeneficiary {
        require(vaultAllowlist.allowlist(token, newVault) || address(newVault) == address(0), "UNAUTHORIZED VAULT");
        //If there is an active, redeem assets
        if(address(activeVault) != address(0)){
            uint shares = activeVault.balanceOf(address(this));
            uint tokens = activeVault.redeem(shares, address(this), address(this));
            token.approve(address(activeVault), 0);
        } else {
            _withdrawBase(address(this), _balanceBase());
        }
        activeVault = newVault;
        //If the newVault is a vault
        if(address(activeVault) != address(0)){
            token.approve(address(activeVault), type(uint).max);
            activeVault.deposit(token.balanceOf(address(this)), address(this));
        } else {
            _depositBase();
        }
    }

    function _initializeBase(IERC20 token, address beneficiary) internal virtual;
    function _balanceBase() internal view virtual returns(uint);
    function _withdrawBase(address to, uint amount) internal virtual;
    function _depositBase() internal virtual;
    
}
