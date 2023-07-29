// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "../interfaces/IERC20.sol";

// @dev Caution: We assume all failed transfers cause reverts and ignore the returned bool.
interface DSR {
    function daiBalance(address usr) external returns (uint wad);
    function join(address dst, uint wad) external;
    function exit(address dst, uint wad) external;
    function pot() external view returns (address);
}

interface Pot {
    function chi() external view returns (uint);
    function drip() external;
    function pie(address) external view returns (uint slice);
}

/**
 * @title DAI Escrow
 * @notice Collateral is stored in unique escrow contracts for every user and every market.
 * This escrow allows user to deposit DAI collateral directly into the DSR contract, earning DAI yyield
 * @dev Caution: This is a proxy implementation. Follow proxy pattern best practices
 */
contract DAIEscrow {

    address public market;
    IDelegateableERC20 public token;
    DSR public constant DSR_MANAGER = DSR(0x373238337Bfe1146fb49989fc222523f83081dDb);
    Pot public constant POT = Pot(0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7);
    address public beneficiary;

    /**
     * @notice Initialize escrow with a token
     * @dev Must be called right after proxy is created.
     * @param _token The IERC20 token representing DAI
     * @param _beneficiary The beneficiary
     */
    function initialize(IDelegateableERC20 _token, address _beneficiary) public {
        require(market == address(0), "ALREADY INITIALIZED");
        market = msg.sender;
        token = _token;
        beneficiary = _beneficiary;
        _token.approve(address(DSR_MANAGER), type(uint).max);
    }
    
    /**
     * @notice Transfers the associated ERC20 token to a recipient.
     * @param recipient The address to receive payment from the escrow
     * @param amount The amount of ERC20 token to be transferred.
     */
    function pay(address recipient, uint amount) public {
        require(msg.sender == market, "ONLY MARKET");
        //If trying to pay full balance, update DSR amount and pay full amount
        //This avoids dust being left over
        if(balance() == amount) amount = DSR_MANAGER.daiBalance(address(this));
        DSR_MANAGER.exit(recipient, amount);
    }

    /**
    * @notice Get the token balance of the escrow
    * @return The balance accrued in the DSR up until the last `drip` function call
    */
    function balance() public view returns (uint) {
        return rmul(POT.chi(), POT.pie(address(this)));
    }
    
    /**
     * @notice Function called by market on deposit. Will deposit DAI into the DSR
     * @dev This function should remain callable by anyone to handle direct inbound transfers.
     */
    function onDeposit() public {
        uint daiBalance = token.balanceOf(address(this));
        if(daiBalance > 0) {
            DSR_MANAGER.join(address(this), daiBalance);
        }
    }

    function rmul(uint x, uint y) internal pure returns(uint){
        uint256 RAY = 10 ** 27;
        // always rounds down
        return x * y / RAY;
    }
}
