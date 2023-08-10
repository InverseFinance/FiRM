pragma solidity ^0.8.13;

contract Governable {
    address public gov;
    address public pendingGov;
    
    constructor(address _gov) {
        gov = _gov;
    }

    error OnlyGov();
    error OnlyPendingGov();

    modifier onlyGov {
        if(msg.sender != gov) revert OnlyGov();
        _;
    }

    modifier onlyPendingGov {
        if(msg.sender != pendingGov) revert OnlyPendingGov();
        _;
    }

    function setPendingGov(address _pendingGov) external onlyGov {
        pendingGov = _pendingGov;
    }

    function claimGov() external onlyPendingGov {
        gov = pendingGov;
        pendingGov = address(0);
    }
}
