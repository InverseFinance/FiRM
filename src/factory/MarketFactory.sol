// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "src/Market.sol";

contract MarketFactory {
    IDolaBorrowingRights public constant DBR = IDolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
    uint256 public constant INITIAL_COLLATERAL_FACTOR_BPS = 5000;
    uint256 public constant INITIAL_REPLENISHMENT_INCENTIVE_BPS = 5000;
    uint256 public constant INITIAL_LIQUIDATION_INCENTIVE_BPS = 100;
    IOracle public oracle;
    address public gov;
    address public fed;
    address public pauseGuardian;
    address public pendingGov;

    mapping(address => bool) public isFromFactory;

    event NewMarket(address indexed collateral, address indexed market);
    event NewOracle(address indexed oldOracle, address indexed newOracle);
    event NewFed(address indexed oldFed, address indexed newFed);
    event NewPauseGuardian(address indexed oldPauseGuardian, address indexed newPauseGuardian);
    event NewPendingGov(address indexed oldPendingGov, address indexed newPendingGov);
    event NewGov(address indexed oldGov, address indexed newGov);

    constructor(address _gov, address _oracle, address _fed, address _pauseGuardian) {
        gov = _gov;
        oracle = IOracle(_oracle);
        fed = _fed;
        pauseGuardian = _pauseGuardian;
        
    }

    modifier onlyGov() {
        require(msg.sender == gov, "Only gov");
        _;
    }

    /**
     * @notice Deploy a new market contract with preset values. 
     * @dev This market then has to be approved and initialized by on-chain vote after deployment.
     * @param collateral collateral for the market
     * @param escrowImpl implementation of the escrow contract
     * @param callbackOnDeposit whether to callback on deposit
     */
    function deployMarket(address collateral, address escrowImpl, bool callbackOnDeposit)
        external
        returns (address market)
    {
        market = address(
            new Market(
                gov,
                fed,
                pauseGuardian,
                escrowImpl,
                DBR,
                IERC20(collateral),
                oracle,
                INITIAL_COLLATERAL_FACTOR_BPS,
                INITIAL_REPLENISHMENT_INCENTIVE_BPS,
                INITIAL_LIQUIDATION_INCENTIVE_BPS,
                callbackOnDeposit
            )
        );
        isFromFactory[market] = true;
        emit NewMarket(collateral, market);
    }

    // Admin functions
    
    /**
     * @notice Set a new pending gov. The new pending gov then has to call `acceptGov`.
     * @dev Can only be called by the gov.
     * @param _pendingGov address of the new pending gov
     */
    function setPendingGov(address _pendingGov) external onlyGov {
        emit NewPendingGov(pendingGov, _pendingGov);
        pendingGov = _pendingGov;
     
    }

    /**
     * @notice Accept the new pending gov.
     * @dev Can only be called by the pending gov.
     */
    function acceptGov() external {
        require(msg.sender == pendingGov, "Only pending gov");
        emit NewGov(gov, pendingGov);
        gov = pendingGov;
        pendingGov = address(0);
    }

    /**
     * @notice Set a new oracle.
     * @dev Can only be called by the gov.
     * @param _oracle address of the new oracle
     */
    function setOracle(address _oracle) external onlyGov {
        emit NewOracle(address(oracle), _oracle);
        oracle = IOracle(_oracle);
    }

    /**
     * @notice Set a new fed.
     * @dev Can only be called by the gov.
     * @param _fed address of the new fed
     */
    function setFed(address _fed) external onlyGov {
        emit NewFed(fed, _fed);
        fed = _fed;
    }

    /**
     * @notice Set a new pause guardian.
     * @dev Can only be called by the gov.
     * @param _pauseGuardian address of the new pause guardian
     */
    function setPauseGuardian(address _pauseGuardian) external onlyGov {
        emit NewPauseGuardian(pauseGuardian, _pauseGuardian);
        pauseGuardian = _pauseGuardian;
    }
}
