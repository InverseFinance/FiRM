pragma solidity ^0.8.13;

import {L2DbrDistributor} from "src/crossChain/L2DbrDistributor.sol";

interface ICrossDomainMessenger {
    function xDomainMessageSender() external returns(address);
}

contract OptiDbrDistributor is L2DbrDistributor {
    
    ICrossDomainMessenger public immutable ovmL2CrossDomainMessenger;


    constructor(address _dbr, address _gov, address _operator, address _messenger, address crossDomainMessenger)
    L2DbrDistributor(_dbr, _gov, _operator, _messenger) {
        ovmL2CrossDomainMessenger = ICrossDomainMessenger(crossDomainMessenger);
    }

    function isL1Sender(address l1Address) internal override returns(bool){
        return msg.sender != address(ovmL2CrossDomainMessenger) || ovmL2CrossDomainMessenger.xDomainMessageSender() != l1Address;
    }
}
