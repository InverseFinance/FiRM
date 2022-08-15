// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Caution. We assume all failed transfers cause reverts and ignore the returned bool.
interface IERC20 {
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
}

interface IOracle {
    function getPrice(address) external view returns (uint);
}

interface IEscrow {
    function initialize(IERC20 _token) external;
    function onDeposit() external;
    function pay(address recipient, uint amount) external;
}

interface IDolaBorrowingRights {
    function onBorrow(address user, uint additionalDebt) external;
    function onRepay(address user, uint repaidDebt) external;
    function onForceReplenish(address user) external;
    function balanceOf(address user) external view returns (uint);
    function deficitOf(address user) external view returns (uint);
    function replenishmentPriceBps() external view returns (uint);
}

interface IBorrowController {
    function borrowAllowed(address borrower, uint amount) external returns (bool);
}

contract Market {

    address public gov;
    address public lender;
    address public pauseGuardian;
    address public immutable escrowImplementation;
    IDolaBorrowingRights public immutable dbr;
    IBorrowController public borrowController;
    IERC20 public immutable dola;
    IERC20 public immutable collateral;
    IOracle public oracle;
    uint public collateralFactorBps;
    uint public replenishmentIncentiveBps;
    uint public liquidationIncentiveBps;
    bool immutable callOnDepositCallback;
    bool public borrowPaused;
    uint public constant SHUTDOWN_DELAY = 7 days;
    uint public scheduledShutdownTimestamp;
    mapping (address => IEscrow) public escrows; // user => escrow
    mapping (address => uint) public debts; // user => debt

    constructor (
        address _gov,
        address _lender,
        address _pauseGuardian,
        address _escrowImplementation,
        IDolaBorrowingRights _dbr,
        IERC20 _dola,
        IERC20 _collateral,
        IOracle _oracle,
        uint _collateralFactorBps,
        uint _replenishmentIncentiveBps,
        uint _liquidationIncentiveBps,
        bool _callOnDepositCallback
    ) {
        require(_collateralFactorBps > 0 && _collateralFactorBps < 10000, "Invalid collateral factor");
        require(_liquidationIncentiveBps > 0 && _liquidationIncentiveBps < 10000, "Invalid liquidation incentive");
        require(_replenishmentIncentiveBps < 10000, "Replenishment incentive must be less than 100%");
        gov = _gov;
        lender = _lender;
        pauseGuardian = _pauseGuardian;
        escrowImplementation = _escrowImplementation;
        dbr = _dbr;
        dola = _dola;
        collateral = _collateral;
        oracle = _oracle;
        collateralFactorBps = _collateralFactorBps;
        replenishmentIncentiveBps = _replenishmentIncentiveBps;
        liquidationIncentiveBps = _liquidationIncentiveBps;
        callOnDepositCallback = _callOnDepositCallback;
    }

    modifier onlyGov {
        require(msg.sender == gov, "Only gov can call this function");
        _;
    }

    function setOracle(IOracle _oracle) public onlyGov { oracle = _oracle; }

    function setBorrowController(IBorrowController _borrowController) public onlyGov { borrowController = _borrowController; }

    function setGov(address _gov) public onlyGov { gov = _gov; }

    function setLender(address _lender) public onlyGov { lender = _lender; }

    function setPauseGuardian(address _pauseGuardian) public onlyGov { pauseGuardian = _pauseGuardian; }

    function setCollateralFactorBps(uint _collateralFactorBps) public onlyGov {
        require(_collateralFactorBps > 0 && _collateralFactorBps < 10000, "Invalid collateral factor");
        collateralFactorBps = _collateralFactorBps;
    }

    function setReplenismentIncentiveBps(uint _replenishmentIncentiveBps) public onlyGov {
        require(_replenishmentIncentiveBps > 0 && _replenishmentIncentiveBps < 10000, "Invalid replenishment incentive");
        replenishmentIncentiveBps = _replenishmentIncentiveBps;
    }

    function setLiquidationIncentiveBps(uint _liquidationIncentiveBps) public onlyGov {
        require(_liquidationIncentiveBps > 0 && _liquidationIncentiveBps < 10000, "Invalid liquidation incentive");
        liquidationIncentiveBps = _liquidationIncentiveBps;
    }

    // if shutdown is false, it cancels a pending shutdown or restarts the market after a successful shutdown
    function shutdown(bool _value) public onlyGov {
        if(_value) {
            scheduledShutdownTimestamp = block.timestamp + SHUTDOWN_DELAY;
        } else {
            scheduledShutdownTimestamp = 0;
        }
        emit ScheduleShutdown(_value, scheduledShutdownTimestamp);
    }

    function isShutdown() public view returns (bool) {
        if(scheduledShutdownTimestamp == 0) return false;
        return scheduledShutdownTimestamp > block.timestamp;
    }

    function recall(uint amount) public {
        require(msg.sender == lender, "Only lender can recall");
        dola.transfer(msg.sender, amount);
    }

    function pauseBorrows(bool _value) public {
        if(_value) {
            require(msg.sender == pauseGuardian || msg.sender == gov, "Only pause guardian or governance can pause");
        } else {
            require(msg.sender == gov, "Only governance can unpause");
        }
        borrowPaused = _value;
    }

    function createEscrow(address user) internal returns (IEscrow instance) {
        address implementation = escrowImplementation;
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create2(0, ptr, 0x37, user)
        }
        require(instance != IEscrow(address(0)), "ERC1167: create2 failed");
        emit CreateEscrow(user, address(instance));
    }

    function getEscrow(address user) internal returns (IEscrow) {
        if(escrows[user] != IEscrow(address(0))) return escrows[user];
        IEscrow escrow = createEscrow(user);
        escrow.initialize(collateral);
        escrows[user] = escrow;
        return escrow;
    }

    function deposit(uint amount) public {
        IEscrow escrow = getEscrow(msg.sender);
        collateral.transferFrom(msg.sender, address(escrow), amount);
        if(callOnDepositCallback) {
            escrow.onDeposit();
        }
    }

    function predictEscrow(address user) public view returns (IEscrow predicted) {
        address implementation = escrowImplementation;
        address deployer = address(this);
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf3ff00000000000000000000000000000000)
            mstore(add(ptr, 0x38), shl(0x60, deployer))
            mstore(add(ptr, 0x4c), user)
            mstore(add(ptr, 0x6c), keccak256(ptr, 0x37))
            predicted := keccak256(add(ptr, 0x37), 0x55)
        }
    }

    function getCreditLimit(address user) public view returns (uint) {
        IEscrow escrow = predictEscrow(user);
        uint collateralBalance = collateral.balanceOf(address(escrow));
        uint collateralValue = collateralBalance * oracle.getPrice(address(collateral)) / 1 ether;
        return collateralValue * collateralFactorBps / 10000;
    }

    function getWithdrawalLimit(address user) public view returns (uint) {
        IEscrow escrow = predictEscrow(user);
        uint collateralBalance = collateral.balanceOf(address(escrow));
        if(collateralBalance == 0) return 0;
        uint debt = debts[user];
        if(debt == 0) return collateralBalance;
        uint minimumCollateral = debt * 1 ether / oracle.getPrice(address(collateral)) * 10000 / collateralFactorBps;
        if(collateralBalance <= minimumCollateral) return 0;
        return collateralBalance - minimumCollateral;
    }

    function borrow(uint amount) public {
        require(!borrowPaused, "Borrowing is paused");
        if(borrowController != IBorrowController(address(0))) {
            require(borrowController.borrowAllowed(msg.sender, amount), "Denied by borrow controller");
        }
        uint credit = getCreditLimit(msg.sender);
        require(credit >= amount, "Insufficient credit limit");
        debts[msg.sender] += amount;
        dbr.onBorrow(msg.sender, amount);
        dola.transfer(msg.sender, amount);
        emit Borrow(msg.sender, amount);
    }

    function withdraw(address to, uint amount) public {
        uint limit = getWithdrawalLimit(msg.sender);
        require(limit >= amount, "Insufficient withdrawal limit");
        IEscrow escrow = getEscrow(msg.sender);
        escrow.pay(to, amount);
        emit Withdraw(msg.sender, to, amount);
    }

    function repay(address user, uint amount) public {
        uint debt = debts[user];
        require(debt >= amount, "Insufficient debt");
        debts[user] -= amount;
        dbr.onRepay(user, amount);
        dola.transferFrom(msg.sender, address(this), amount);
        emit Repay(user, msg.sender, amount);
    }

    function forceReplenish(address user) public {
        uint deficit = dbr.deficitOf(user);
        require(deficit > 0, "No DBR deficit");
        uint replenishmentCost = deficit * dbr.replenishmentPriceBps() / 10000;
        uint replenisherReward = replenishmentCost * replenishmentIncentiveBps / 10000;
        debts[user] += replenishmentCost;
        dbr.onForceReplenish(user);
        dola.transfer(msg.sender, replenisherReward);
        emit ForceReplenish(user, msg.sender, deficit, replenishmentCost, replenisherReward);
    }

    function liquidate(address user, uint repaidDebt) public {
        require(repaidDebt > 0, "Must repay positive debt");
        uint debt = debts[user];
        require(repaidDebt <= debt, "Insufficient user debt");
        require(getCreditLimit(user) < debt || isShutdown(), "User debt is healthy. Market was not shutdown");
        uint liquidatorReward = repaidDebt * 1 ether / oracle.getPrice(address(collateral));
        liquidatorReward += liquidatorReward * liquidationIncentiveBps / 10000;
        debts[user] -= repaidDebt;
        dbr.onRepay(user, repaidDebt);
        dola.transferFrom(msg.sender, address(this), repaidDebt);
        IEscrow escrow = predictEscrow(user);
        escrow.pay(msg.sender, liquidatorReward);
        emit Liquidate(user, msg.sender, repaidDebt, liquidatorReward);
    }

    event Borrow(address indexed account, uint amount);
    event Withdraw(address indexed account, address indexed to, uint amount);
    event Repay(address indexed account, address indexed repayer, uint amount);
    event ForceReplenish(address indexed account, address indexed replenisher, uint deficit, uint replenishmentCost, uint replenisherReward);
    event Liquidate(address indexed account, address indexed liquidator, uint repaidDebt, uint liquidatorReward);
    event ScheduleShutdown(bool value, uint scheduledTimestamp);
    event CreateEscrow(address indexed user, address escrow);
}
