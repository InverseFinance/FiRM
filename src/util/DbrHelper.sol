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
    function claimable() external returns (uint); // TODO: should we use this?
}

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

    constructor() {
        dbr.approve(address(curvePool), type(uint).max);
        inv.approve(address(invMarket), type(uint).max);
    }

    function claimAndSellDbr(uint minOut, address receiver) public nonReentrant {
        uint256 amount = _claimDBR();

        _sellDbr(amount, minOut, dolaIndex, receiver);
    }

    function claimSellAndRepay(uint minOut, address market, address to) external {
        claimAndSellDbr(minOut, address(this));

        uint256 dolaAmount = dola.balanceOf(address(this));
        uint256 debt = IMarket(market).debts(to);

        if(dolaAmount > debt) {
            uint256 extraDola = dolaAmount - debt;
            dolaAmount = debt;
            dola.transfer(to, extraDola);
        }

        dola.approve(market, dolaAmount);
        IMarket(market).repay(to, dolaAmount);
    }

    function claimSellAndDepositInv(uint minOut, address to) external nonReentrant {
        uint256 amount = _claimDBR();

        _sellDbr(amount, minOut, invIndex, address(this));

        uint256 invAmount = inv.balanceOf(address(this));

        invMarket.deposit(to, invAmount);
    }

    function _claimDBR() internal returns (uint amount) {
        IINVEscrow escrow = _getEscrow();

        uint256 dbrClaimable = escrow.claimable();
        if(dbrClaimable == 0)revert NoDbrToClaim();
        
        escrow.claimDBRTo(address(this));
        amount = dbr.balanceOf(address(this));
    }

    function _getEscrow() internal view returns (IINVEscrow escrow)  {
        escrow = IINVEscrow(address(invMarket.escrows(msg.sender)));
        if (address(escrow) == address(0)) revert NoEscrow(msg.sender);
    }

    function _sellDbr(uint amount, uint minOut, uint indexOut, address receiver) internal {
        if (amount > 0) {
            curvePool.exchange(
                dbrIndex,
                indexOut,
                amount,
                minOut,
                false,
                receiver
            );
        }
    }
}