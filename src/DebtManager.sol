pragma solidity ^0.8.20;

interface IDebtManager {
    function onBorrow(address user, uint additionalDebt) external;
    function onRepay(address user, uint repaidDebt) external;
    function onLiquidate(address user, uint liquidatedDebt) external;
    function debt(address market, address user) external view returns (uint);
}

interface IDbrAMM {
    function dolaInDbrOut(uint dolaIn) external view returns (uint dbrOut);
    function dbrNeededForDola(uint dolaOut) external view returns (uint dbrIn);
    function dbrInDolaOut(uint dbrIn) external view returns (uint dolaOut);
    function dolaNeededForDbr(uint dbrOut) external view returns (uint dolaIn);
    function buyDbr(uint dbrAmount) external returns (uint dolaIn);
}


//TODO: Add governance if needed
//TODO: Add streaming logic for DbrAMM
contract DebtManager is IDebtManager {

    IDbrAMM public amm;
    mapping(address => bool) public markets;
    mapping(address => mapping(address => uint)) public debtShares;
    uint public constant DEBT_MULTIPLIER = 1e36;
    uint public totalDebt;
    uint public lastUpdate;

    constructor() {
        lastUpdate = block.timestamp;
    }

    modifier onlyMarket() {
        if(!markets[msg.sender]){
            revert OnlyMarket();
        }
        _;
    }

    modifier updateDebt() {
        uint dbrDeficit = (block.timestamp - lastUpdate) * totalDebt / 365 days;
        uint dolaNeeded = amm.dolaNeededForDbr(dbrDeficit);
        totalDebt += dolaNeeded;
        lastUpdate = block.timestamp;
        amm.buyDbr(dbrDeficit);
        _;
    }

    error OnlyMarket();

    function onBorrow(address user, uint additionalDebt) external onlyMarket updateDebt {
        address market = msg.sender;
        totalDebt += additionalDebt;
        debtShares[market][user] += additionalDebt * DEBT_MULTIPLIER / totalDebt;
        
    }

    function onRepay(address user, uint repaidDebt) external onlyMarket updateDebt {
        address market = msg.sender;
        uint _debt = debt(market, user);
        if(_debt < repaidDebt){
            debtShares[market][user] = 0;
            totalDebt -= _debt;
        } else {
            totalDebt -= repaidDebt;
            debtShares[market][user] = (_debt - repaidDebt) * DEBT_MULTIPLIER / totalDebt;
        }
    }

    function onLiquidate(address user, uint liquidatedDebt) external onlyMarket updateDebt {
        address market = msg.sender;
        uint _debt = debt(market, user);
        if(_debt < liquidatedDebt){
            debtShares[market][user] = 0;
            totalDebt -= _debt;
        } else {
            totalDebt -= liquidatedDebt;
            debtShares[market][user] = (_debt - liquidatedDebt) * DEBT_MULTIPLIER / totalDebt;
        }
    }

    function debt(address market, address user) public view returns (uint) {
        return totalDebt * DEBT_MULTIPLIER / debtShares[market][user];
    }
}
