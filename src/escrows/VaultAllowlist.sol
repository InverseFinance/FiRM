pragma solidity ^0.8.13;
import "openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import "src/Governable.sol";

contract VaultAllowlist is Governable {
    // token => vault => bool
    mapping(IERC20 => mapping(IERC4626 => bool)) public allowlist;
    // token => vault
    mapping(IERC20 => IERC4626) public defaultVaults;
    // user => token => vault
    mapping(address => mapping(IERC20 => IERC4626)) public preferredVault;

    constructor(address _gov) Governable(_gov){}

    function defaultVault(address user, IERC20 token) public returns(IERC4626){
        IERC4626 preferred = preferredVault[user][token];
        if(preferred == IERC4626(address(0))) return defaultVaults[token];
        return preferred;
    }

    function setAllowed(IERC20 token, IERC4626 vault, bool allowed) public onlyGov {
        require(token == IERC20(vault.asset()), "INCOMPATIBLE TOKEN");
        if(!allowed && defaultVaults[token] == vault){
            defaultVaults[token] = IERC4626(address(0));
        }
        allowlist[token][vault] = allowed;
    }

    function setDefault(IERC20 token, IERC4626 vault) public onlyGov {
        require(allowlist[token][vault], "UNAUTHORIZED VAULT");
        defaultVaults[token] = vault;
    }

    function setPreferred(IERC20 token, IERC4626 vault) public {
        require(allowlist[token][vault], "UNAUTHORIZED VAULT");
        preferredVault[msg.sender][token] = vault;
    }
}
