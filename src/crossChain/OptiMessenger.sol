pragma solidity ^0.8.13;
import "src/Governable.sol";
import "src/crossChain/L2DbrDistributor.sol";

interface ICrossDomainMessenger {
    function sendMessage(address l2Address, bytes memory message, uint gasLimit) external;
}

contract OptiMessenger is Governable {
    ICrossDomainMessenger public immutable crossDomainMessenger;
    address public masterDistributor;
    address public l2DbrDistributor;
    uint public gasLimit;

    constructor(address _masterDistributor, address _crossChainMessenger, address _gov) Governable(_gov) {
        masterDistributor = _masterDistributor;
        crossDomainMessenger = ICrossDomainMessenger(_crossChainMessenger); 
    }

    error OnlyMasterDistributor();
    error L2DistributorZeroAddress();
    
    function updateStake(address staker, uint newPower) external {
        require(msg.sender == masterDistributor, "Only master distributor can update stake");
        if(msg.sender != masterDistributor) revert OnlyMasterDistributor();
        if(l2DbrDistributor == address(0)) revert L2DistributorZeroAddress();
        bytes memory message = abi.encodeWithSelector(
            L2DbrDistributor.updateStake.selector,
            staker,
            newPower
        );
        crossDomainMessenger.sendMessage(l2DbrDistributor, message, gasLimit);
    }

    function setL2DbrDistributor(address newL2DbrDistributor) external onlyGov {
        l2DbrDistributor = newL2DbrDistributor;
    }

    function setGasLimit(uint newGasLimit) external onlyGov {
        gasLimit = newGasLimit;
    }
}
