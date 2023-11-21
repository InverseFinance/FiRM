pragma solidity ^0.8.20;

import "src/interfaces/IERC20.sol";
import "src/interfaces/IMarket.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

interface ICurvePool {
    function exchange(
        uint i,
        uint j,
        uint dx,
        uint min_dy,
        bool use_eth,
        address receiver
    ) external payable returns (uint);
}

interface IINVEscrow {
    function claimDBRTo(address to) external;
    function claimable() external returns (uint);
}

/// @title DbrHelper
/// @notice Helper contract to claim DBR, sell it for DOLA and optionally repay debt or sell it for INV and deposit into INV market
/// @dev Require approving DbrHelper to claim on behalf of the user (via setClaimer function in INVEscrow)
contract DbrHelper is ReentrancyGuard {
    error NoEscrow(address user);
    error NoDbrToClaim();
    
    IMarket public constant invMarket = IMarket(0xb516247596Ca36bf32876199FBdCaD6B3322330B);
    ICurvePool public constant curvePool = ICurvePool(0xC7DE47b9Ca2Fc753D6a2F167D8b3e19c6D18b19a);
    IERC20 public constant dola = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public constant dbr = IERC20(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
    IERC20 public constant inv = IERC20(0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68);
    
    uint public constant dolaIndex = 0;
    uint public constant dbrIndex = 1;
    uint public constant invIndex = 2;
    
    event ClaimAndSell(address indexed claimer, uint dbrAmount, uint dolaAmount, address receiver);
    event ClaimSellAndRepay(address indexed claimer, address indexed market, address indexed to, uint dolaAmount);
    event ClaimSellAndDepositInv(address indexed claimer, address indexed to, uint invAmount);
    event ExtraDola(address indexed receiver, uint amount);

    constructor() {
        dbr.approve(address(curvePool), type(uint).max);
        inv.approve(address(invMarket), type(uint).max);
    }

    /// @notice Claim DBR, sell it for DOLA, and send DOLA to receiver
    /// @param minOut Minimum amount of DOLA to receive
    /// @param receiver Address to receive DOLA
    /// @return dolaAmount Amount of DOLA received
    function claimAndSellDbr(uint minOut, address receiver) public nonReentrant returns (uint256 dolaAmount) {
        uint256 amount = _claimDBR();

        dolaAmount = _sellDbr(amount, minOut, dolaIndex, receiver);

        emit ClaimAndSell(msg.sender, amount, dolaAmount, receiver);
    }

    /// @notice Claim DBR, sell it for DOLA, and repay DOLA debt
    /// @param minOut Minimum amount of DOLA to receive
    /// @param market Address of the market to repay
    /// @param to Address to receive debt repayment and which is going to receive any extra DOLA
    /// @return dolaAmount Amount of DOLA repaid
    function claimSellAndRepay(uint minOut, address market, address to) external returns (uint256 dolaAmount) {
        claimAndSellDbr(minOut, address(this));

        dolaAmount = dola.balanceOf(address(this));
        uint256 debt = IMarket(market).debts(to);

        if(dolaAmount > debt) {
            uint256 extraDola = dolaAmount - debt;
            dolaAmount = debt;
            dola.transfer(to, extraDola);
            emit ExtraDola(to, extraDola);
        }

        dola.approve(market, dolaAmount);
        IMarket(market).repay(to, dolaAmount);

        emit ClaimSellAndRepay(msg.sender, market, to, dolaAmount);
    }

    /// @notice Claim DBR, sell it for DOLA, and deposit INV
    /// @param minOut Minimum amount of DOLA to receive
    /// @param to Address to receive INV deposit
    /// @return invAmount Amount of INV deposited
    function claimSellAndDepositInv(uint minOut, address to) external nonReentrant returns (uint256 invAmount) {
        uint256 amount = _claimDBR();

        _sellDbr(amount, minOut, invIndex, address(this));

        invAmount = inv.balanceOf(address(this));

        invMarket.deposit(to, invAmount);

        emit ClaimSellAndDepositInv(msg.sender, to, invAmount);
    }

    /// @notice Claim DBR
    /// @return amount of DBR claimed
    function _claimDBR() internal returns (uint amount) {
        IINVEscrow escrow = _getEscrow();

        uint256 dbrClaimable = escrow.claimable();
        if(dbrClaimable == 0)revert NoDbrToClaim();
        
        escrow.claimDBRTo(address(this));
        amount = dbr.balanceOf(address(this));
    }

    /// @notice Get escrow for the user
    /// @return escrow Escrow for the user
    function _getEscrow() internal view returns (IINVEscrow escrow)  {
        escrow = IINVEscrow(address(invMarket.escrows(msg.sender)));
        if (address(escrow) == address(0)) revert NoEscrow(msg.sender);
    }

    /// @notice Sell DBR for DOLA or INV
    /// @param amountIn Amount of DBR to sell
    /// @param minOut Minimum amount of DOLA or INV to receive
    /// @param indexOut Index of the token to receive (0 for DOLA, 2 for INV)
    /// @param receiver Address to receive DOLA or INV
    function _sellDbr(uint amountIn, uint minOut, uint indexOut, address receiver) internal returns (uint256 amountOut){
        if (amountIn > 0) {
            amountOut = curvePool.exchange(
                dbrIndex,
                indexOut,
                amountIn,
                minOut,
                false,
                receiver
            );
        }
    }
}