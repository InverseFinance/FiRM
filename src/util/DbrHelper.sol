pragma solidity ^0.8.20;

import "src/interfaces/IERC20.sol";
import "src/interfaces/IMarket.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

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

interface IDbr {
    function markets(address) external view returns (bool);
}

/// @title DbrHelper
/// @notice Helper contract to claim DBR, sell it for DOLA and optionally repay debt or sell it for INV and deposit into INV market
/// @dev Require approving DbrHelper to claim on behalf of the user (via setClaimer function in INVEscrow)
contract DbrHelper is Ownable, ReentrancyGuard {
    error NoEscrow(address user);
    error ReceiverAddressZero(address token);
    error RepayParamsNotCorrect(
        uint256 percentage,
        address to,
        address market,
        uint256 sellForDola
    );
    error SellPercentageTooHigh();
    error RepayPercentageTooHigh();
    error MarketNotFound(address market);

    IMarket public constant INV_MARKET =
        IMarket(0xb516247596Ca36bf32876199FBdCaD6B3322330B);
    ICurvePool public constant CURVE_POOL =
        ICurvePool(0xC7DE47b9Ca2Fc753D6a2F167D8b3e19c6D18b19a);
    IERC20 public constant DOLA =
        IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public constant DBR =
        IERC20(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
    IERC20 public constant INV =
        IERC20(0x41D5D79431A913C4aE7d69a668ecdfE5fF9DFB68);

    uint256 public constant DOLA_INDEX = 0;
    uint256 public constant DBR_INDEX = 1;
    uint256 public constant INV_INDEX = 2;
    uint256 public constant DENOMINATOR = 10000; // 100% in basis points

    event Sell(
        address indexed claimer,
        uint amountIn,
        uint amountOut,
        uint indexOut,
        address indexed receiver
    );
    event RepayDebt(
        address indexed claimer,
        address indexed market,
        address indexed to,
        uint dolaAmount
    );
    event DepositInv(
        address indexed claimer,
        address indexed to,
        uint invAmount
    );
    event MarketApproved(address indexed market);

    constructor() Ownable(msg.sender) {
        DBR.approve(address(CURVE_POOL), type(uint).max);
        INV.approve(address(INV_MARKET), type(uint).max);
    }

    struct ClaimAndSell {
        address toDbr; // Address to receive leftover DBR
        address toDola; // Address to receive DOLA
        address toInv; // Address to receive INV deposit
        uint256 minOutDola;
        uint256 sellForDola; // Percentage of claimed DBR swapped for DOLA (in basis points)
        uint256 minOutInv;
        uint256 sellForInv; // Percentage of claimed DBR swapped for INV (in basis points)
    }

    struct Repay {
        address market;
        address to;
        uint256 percentage; // Percentage of DOLA swapped from claimed DBR to use for repaying debt (in basis points)
    }

    /// @notice Approve market to be used for repaying debt
    /// @dev Must be an active market
    /// @param market Address of the market
    function approveMarket(address market) external {
        if(!IDbr(address(DBR)).markets(market)) revert MarketNotFound(market); 
        DOLA.approve(market, type(uint).max);
        emit MarketApproved(market);
    }

    /// @notice Claim DBR, sell it for DOLA and/or INV and/or repay debt
    /// @param params ClaimAndSell struct with parameters for claiming and selling
    /// @param repay Repay struct with parameters for repaying debt
    /// @return dolaAmount Amount of DOLA received after the sell (includes repaid DOLA)
    /// @return invAmount Amount of INV deposited into the escrow
    /// @return repaidAmount Amount of DOLA repaid
    /// @return dbrAmount Amount of DBR left after selling
    function claimAndSell(
        ClaimAndSell calldata params,
        Repay calldata repay
    )
        external
        nonReentrant
        returns (
            uint256 dolaAmount,
            uint256 invAmount,
            uint256 repaidAmount,
            uint256 dbrAmount
        )
    {
        _checkInputs(params, repay);

        uint256 amount = _claimDBR();

        (dolaAmount, invAmount, repaidAmount, dbrAmount) = _sell(
            params,
            repay,
            amount
        );
    }

    /// @notice  Sell DBR for DOLA and/or INV and/or repay debt
    /// @param params ClaimAndSell struct with parameters for selling
    /// @param repay Repay struct with parameters for repaying debt
    /// @param amount Amount of DBR available to sell
    /// @return dolaAmount Amount of DOLA received after the sell (includes repaid DOLA)
    /// @return invAmount Amount of INV deposited into the escrow
    /// @return repaidAmount Amount of DOLA repaid
    /// @return dbrLeft Amount of DBR left after selling
    function _sell(
        ClaimAndSell calldata params,
        Repay calldata repay,
        uint256 amount
    )
        internal
        returns (
            uint256 dolaAmount,
            uint256 invAmount,
            uint256 repaidAmount,
            uint256 dbrLeft
        )
    {
        if (params.sellForDola > 0) {
            uint256 sellAmountForDola = (amount * params.sellForDola) /
                DENOMINATOR;

            if (repay.percentage != 0) {
                (dolaAmount, repaidAmount) = _sellAndRepay(
                    sellAmountForDola,
                    params.minOutDola,
                    repay
                );
            } else {
                dolaAmount = _sellDbr(
                    sellAmountForDola,
                    params.minOutDola,
                    DOLA_INDEX,
                    params.toDola
                );
            }
        }

        if (params.sellForInv > 0) {
            uint256 sellAmountForInv = (amount * params.sellForInv) /
                DENOMINATOR;
            invAmount = _sellAndDeposit(
                sellAmountForInv,
                params.minOutInv,
                params.toInv
            );
        }

        // Send leftover DBR to the receiver
        dbrLeft = DBR.balanceOf(address(this));
        if (dbrLeft > 0) DBR.transfer(params.toDbr, dbrLeft);
        // Send leftover DOLA to the receiver
        uint256 dolaLeft = DOLA.balanceOf(address(this));
        if (dolaLeft > 0) DOLA.transfer(params.toDola, dolaLeft);
    }

    /// @notice Sell DBR amount for INV and deposit into the escrow
    /// @param amount Amount of DBR to sell
    /// @param minOutInv Minimum amount of INV to receive
    /// @param to Address to receive INV deposit
    /// @return invAmount Amount of INV deposited
    function _sellAndDeposit(
        uint256 amount,
        uint256 minOutInv,
        address to
    ) internal returns (uint256 invAmount) {
        // Sell DBR for INV
        _sellDbr(amount, minOutInv, INV_INDEX, address(this));
        // Deposit INV
        invAmount = INV.balanceOf(address(this));
        INV_MARKET.deposit(to, invAmount);

        emit DepositInv(msg.sender, to, invAmount);
    }

    /// @notice Sell DBR amount for DOLA and repay debt
    /// @param amount Amount of DBR to sell
    /// @param minOutDola Minimum amount of DOLA to receive
    /// @param repay Repay struct with parameters for repaying debt
    /// @return dolaAmount Amount of DOLA received after selling DBR
    /// @return repaidAmount Actual amount of DOLA repaid
    function _sellAndRepay(
        uint amount,
        uint minOutDola,
        Repay calldata repay
    ) internal returns (uint256 dolaAmount, uint256 repaidAmount) {
        // Sell DBR for DOLA
        dolaAmount = _sellDbr(amount, minOutDola, DOLA_INDEX, address(this));
        // Repay debt
        repaidAmount = _repay(repay, dolaAmount);
    }

    /// @notice Repay debt
    /// @dev Must transfer any remaining DOLA out of contract after being called
    /// @param repay Repay struct with parameters for repaying debt
    /// @param dolaAmount Amount of DOLA available to repay
    /// @return repaidAmount Actual amount of DOLA repaid
    function _repay(
        Repay calldata repay,
        uint256 dolaAmount
    ) internal returns (uint256 repaidAmount) {
        uint256 debt = IMarket(repay.market).debts(repay.to);
        repaidAmount = (dolaAmount * repay.percentage) / DENOMINATOR;
        // If repaidAmount is higher than debt, use debt instead
        if (repaidAmount > debt) {
            repaidAmount = debt;
        }
        // Repay debt
        IMarket(repay.market).repay(repay.to, repaidAmount);

        emit RepayDebt(msg.sender, repay.market, repay.to, repaidAmount);
    }

    /// @notice Claim DBR
    /// @return amount of DBR claimed
    function _claimDBR() internal returns (uint amount) {
        IINVEscrow escrow = _getEscrow();
        escrow.claimDBRTo(address(this));
        amount = DBR.balanceOf(address(this));
    }

    /// @notice Get escrow for the user
    /// @return escrow Escrow for the user
    function _getEscrow() internal view returns (IINVEscrow escrow) {
        escrow = IINVEscrow(address(INV_MARKET.escrows(msg.sender)));
        if (address(escrow) == address(0)) revert NoEscrow(msg.sender);
    }

    /// @notice Sell DBR for DOLA or INV
    /// @param amountIn Amount of DBR to sell
    /// @param minOut Minimum amount of DOLA or INV to receive
    /// @param indexOut Index of the token to receive (0 for DOLA, 2 for INV)
    /// @param receiver Address to receive DOLA or INV
    /// @return amountOut Amount of DOLA or INV received
    function _sellDbr(
        uint amountIn,
        uint minOut,
        uint indexOut,
        address receiver
    ) internal returns (uint256 amountOut) {
        amountOut = CURVE_POOL.exchange(
            DBR_INDEX,
            indexOut,
            amountIn,
            minOut,
            false,
            receiver
        );
        emit Sell(msg.sender, amountIn, amountOut, indexOut, receiver);
    }

    /// @notice Check inputs
    /// @param params ClaimAndSell struct with parameters for claiming and selling
    /// @param repay Repay struct with parameters for repaying debt
    function _checkInputs(
        ClaimAndSell calldata params,
        Repay calldata repay
    ) internal view {
        if (
            params.toDbr == address(0) &&
            params.sellForDola + params.sellForInv != DENOMINATOR
        ) revert ReceiverAddressZero(address(DBR));
        if (params.toDola == address(0) && params.sellForDola > 0)
            revert ReceiverAddressZero(address(DOLA));
        if (params.toInv == address(0) && params.sellForInv > 0)
            revert ReceiverAddressZero(address(INV));
        if (
            repay.percentage != 0 &&
            (repay.to == address(0) ||
                repay.market == address(0) ||
                params.sellForDola == 0 ||
                !IDbr(address(DBR)).markets(repay.market)
            ))
            revert RepayParamsNotCorrect(
                repay.percentage,
                repay.to,
                repay.market,
                params.sellForDola
            );
        if (params.sellForDola + params.sellForInv > DENOMINATOR)
            revert SellPercentageTooHigh();
        if (repay.percentage > DENOMINATOR) revert RepayPercentageTooHigh();
    }
}
