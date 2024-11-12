//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.20;

interface IDebtManager {
    function increaseDebt(address user, uint amount) external;
    function decreaseDebt(address user, uint amount) external returns(uint);
    function debt(address market, address user) external view returns (uint);
    function marketDebt(address market) external view returns(uint);
}

interface IDbrAMM {
    function burnDbr(uint exactDolaIn, uint exactDbrBurn) external returns (uint dolaIn);
}

interface IHelper {
    function dolaNeededForDbr(uint dbrOut) external view returns (uint dolaIn);
}

interface IDBR {
    function markets(address) external view returns (bool);
}

interface IDOLA {
    function approve(address, uint) external returns (bool);
    function mint(address, uint) external;
}


contract VariableDebtManager is IDebtManager {

    IDbrAMM public immutable amm; //TODO: Doesn't necessarily have to be immutable. Can consider making mutable.
    IDBR public immutable dbr;
    IDOLA public immutable dola;
    IHelper public helper; //Should this functionality be a part of the AMM?
    mapping(address => mapping(address => uint)) public debtShares;
    mapping(address => uint) public marketDebtShares;
    uint public constant MANTISSA = 10 ** 36;
    uint public totalDebt;
    uint public totalDebtShares;
    uint public lastUpdate;

    constructor(address _amm, address _helper, address _dbr, address _dola) {
        lastUpdate = block.timestamp;
        helper = IHelper(_helper);
        amm = IDbrAMM(_amm);
        dbr = IDBR(_dbr);
        dola = IDOLA(_dola);
    }

    modifier onlyMarket() {
        if(!dbr.markets(msg.sender)){
            revert OnlyMarket();
        } 
        _;
    }

    modifier updateDebt() {
        _burnDbrDeficit();
        _;
    }

    error OnlyMarket();
    
    //Should be called when switching fixed rate debt to variable debt and when borrowing variable debt
    function increaseDebt(address user, uint additionalDebt) external onlyMarket updateDebt {
        address market = msg.sender;
        totalDebt += additionalDebt;
        uint additionalDebtShares;
        if(totalDebt == 0){
            additionalDebtShares = additionalDebt * MANTISSA; //Minting a high amount of initial debt shares, as debt per share will increase exponentially over the lifetime of the contract
        } else {
            additionalDebtShares = additionalDebt * totalDebtShares / totalDebt; //TODO: Consider rounding up in favour of other users
        }
        totalDebtShares += additionalDebtShares;
        marketDebtShares[market] += additionalDebtShares;
        debtShares[market][user] += additionalDebtShares;
    }

    //Should be called when switching variable debt with fixed rate debt, when repaying and when a user is liquidated
    function decreaseDebt(address user, uint amount) external onlyMarket updateDebt returns(uint){
        address market = msg.sender;
        uint userDebt = _debt(market, user);
        if(userDebt <= amount){
            totalDebtShares -= debtShares[market][user];
            marketDebtShares[market] -= debtShares[market][user];
            debtShares[market][user] = 0;
            totalDebt -= userDebt;
            return userDebt;
        } else {
            uint removedDebtShares = totalDebtShares * amount / totalDebt;
            totalDebt -= amount;
            totalDebtShares -= removedDebtShares; //TODO: Make sure this doesn't underflow
            marketDebtShares[market] -= removedDebtShares; //TODO: Make sure this doesn't underflow
            debtShares[market][user] -= removedDebtShares; //TODO: Make sure this doesn't underflow
            return amount;
        }
    }

    function buyHook() external {
        _burnDbrDeficit();
    }

    function _burnDbrDeficit() internal {
        if(lastUpdate < block.timestamp){
            uint _dbrDeficit = dbrDeficit();
            uint dolaNeeded = helper.dolaNeededForDbr(_dbrDeficit);
            totalDebt += dolaNeeded;
            lastUpdate = block.timestamp;
            dola.mint(address(this), dolaNeeded);
            amm.burnDbr(dolaNeeded, _dbrDeficit);
        }
    }

    function dbrDeficit() public view returns (uint){
        return (block.timestamp - lastUpdate) * totalDebt / 365 days;
    }

    function debt(address market, address user) public view returns (uint) {
        uint dolaNeeded = helper.dolaNeededForDbr(dbrDeficit());
        return (totalDebt + dolaNeeded) * debtShares[market][user] / totalDebtShares;
    }

    function marketDebt(address market) public view returns (uint) {
        uint dolaNeeded = helper.dolaNeededForDbr(dbrDeficit());
        return (totalDebt + dolaNeeded) * marketDebtShares[market] / totalDebtShares;
    }

    //Only safe to use if DBR deficit is 0
    function _debt(address market, address user) internal view returns (uint){
        return totalDebt * debtShares[market][user] / totalDebtShares;
    }
}
