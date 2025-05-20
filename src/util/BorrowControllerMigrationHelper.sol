pragma solidity ^0.8.20;

interface IBorrowController {
    function operator() external view returns(address);
    function setOperator(address _operator) external;
    function contractAllowlist(address) external view returns(bool);
    function allow(address) external;
    function dailyLimits(address) external view returns(uint);
    function stalenessThreshold(address) external view returns(uint);
    function minDebts(address) external view returns(uint);
    function setDailyLimit(address, uint) external;
    function setStalenessThreshold(address, uint) external;
    function setMinDebt(address, uint) external;
}

contract BorrowControllerMigrationHelper {
    address public immutable gov;
    
    constructor(address _gov){
        gov = _gov;
    }

    function allowlistContracts(IBorrowController oldController, IBorrowController newController, address[] calldata allowlist) external {
        require(msg.sender == gov, "Only gov");
        for(uint i; i < allowlist.length; i++){
            address allowedContract = allowlist[i];
            require(oldController.contractAllowlist(allowedContract));
            newController.allow(allowedContract);
        }
    }

    function migrateMarkets(IBorrowController oldController, IBorrowController newController, address[] calldata markets) external {
        require(msg.sender == gov, "Only gov");
        for(uint i; i < markets.length; i++){
            address market = markets[i];
            newController.setDailyLimit(market, oldController.dailyLimits(market));
            newController.setStalenessThreshold(market, oldController.stalenessThreshold(market));
            newController.setMinDebt(market, oldController.minDebts(market));
        }
    }

    function transferOwnership(IBorrowController newController) external {
        require(msg.sender == gov, "Only gov");
        newController.setOperator(gov);        
    }
}
