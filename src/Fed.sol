// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMarket {
    function recall(uint amount) external;
    function totalDebt() external view returns (uint);
    function borrowPaused() external view returns (bool);
}

interface IDola {
    function mint(address to, uint amount) external;
    function burn(uint amount) external;
    function balanceOf(address user) external view returns (uint);
    function transfer(address to, uint amount) external returns (bool);
}

interface IDBR {
    function markets(address) external view returns (bool);
}

contract Fed {

    IDBR public immutable dbr;
    IDola public immutable dola;
    address public gov;
    address public chair;
    uint public supplyCeiling;
    uint public globalSupply;
    mapping (IMarket => uint) public supplies;

    constructor (IDBR _dbr, IDola _dola, address _gov, address _chair, uint _supplyCeiling) {
        dbr = _dbr;
        dola = _dola;
        gov = _gov;
        chair = _chair;
        supplyCeiling = _supplyCeiling;
    }

    function changeGov(address _gov) public {
        require(msg.sender == gov, "ONLY GOV");
        gov = _gov;
    }

    function changeSupplyCeiling(uint _supplyCeiling) public {
        require(msg.sender == gov, "ONLY GOV");
        supplyCeiling = _supplyCeiling;
    }

    function changeChair(address _chair) public {
        require(msg.sender == gov, "ONLY GOV");
        chair = _chair;
    }

    function resign() public {
        require(msg.sender == chair, "ONLY CHAIR");
        chair = address(0);
    }

    function expansion(IMarket market, uint amount) public {
        require(msg.sender == chair, "ONLY CHAIR");
        require(dbr.markets(address(market)), "UNSUPPORTED MARKET");
        require(market.borrowPaused() != true, "CANNOT EXPAND PAUSED MARKETS");
        dola.mint(address(market), amount);
        supplies[market] += amount;
        globalSupply += amount;
        require(globalSupply <= supplyCeiling);
        emit Expansion(market, amount);
    }

    function contraction(IMarket market, uint amount) public {
        require(msg.sender == chair, "ONLY CHAIR");
        require(dbr.markets(address(market)), "UNSUPPORTED MARKET");
        uint supply = supplies[market];
        require(amount <= supply, "AMOUNT TOO BIG"); // can't burn profits
        market.recall(amount);
        dola.burn(amount);
        supplies[market] -= amount;
        globalSupply -= amount;
        emit Contraction(market, amount);
    }

    function getProfit(IMarket market) public view returns (uint) {
        uint marketValue = dola.balanceOf(address(market)) + market.totalDebt();
        uint supply = supplies[market];
        if(supply >= marketValue) return 0;
        return marketValue - supply;
    }

    function takeProfit(IMarket market) public {
        uint profit = getProfit(market);
        if(profit > 0) {
            market.recall(profit);
            dola.transfer(gov, profit);
        }
    }


    event Expansion(IMarket indexed market, uint amount);
    event Contraction(IMarket indexed market, uint amount);

}