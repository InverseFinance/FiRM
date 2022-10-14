// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Caution. We assume all failed transfers cause reverts and ignore the returned bool.
interface IERC20 {
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
}

interface IOracle {
    function getPrice(address,uint) external returns (uint);
    function viewPrice(address,uint) external view returns (uint);
}

interface IEscrow {
    function initialize(IERC20 _token, address beneficiary) external;
    function onDeposit() external;
    function pay(address recipient, uint amount) external;
    function balance() external view returns (uint);
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
    function borrowAllowed(address msgSender, address borrower, uint amount) external returns (bool);
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
    uint public liquidationFeeBps;
    uint public liquidationFactorBps = 5000; // 50% by default
    bool immutable callOnDepositCallback;
    bool public borrowPaused;
    uint public totalDebt;
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;
    mapping (address => IEscrow) public escrows; // user => escrow
    mapping (address => uint) public debts; // user => debt
    mapping(address => uint256) public nonces; // user => nonce

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
        require(_collateralFactorBps < 10000, "Invalid collateral factor");
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
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    modifier onlyGov {
        require(msg.sender == gov, "Only gov can call this function");
        _;
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes("DBR MARKET")),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    function setOracle(IOracle _oracle) public onlyGov { oracle = _oracle; }

    function setBorrowController(IBorrowController _borrowController) public onlyGov { borrowController = _borrowController; }

    function setGov(address _gov) public onlyGov { gov = _gov; }

    function setLender(address _lender) public onlyGov { lender = _lender; }

    function setPauseGuardian(address _pauseGuardian) public onlyGov { pauseGuardian = _pauseGuardian; }

    function setCollateralFactorBps(uint _collateralFactorBps) public onlyGov {
        require(_collateralFactorBps < 10000, "Invalid collateral factor");
        collateralFactorBps = _collateralFactorBps;
    }

    function setLiquidationFactorBps(uint _liquidationFactorBps) public onlyGov {
        require(_liquidationFactorBps > 0 && _liquidationFactorBps <= 10000, "Invalid liquidation factor");
        liquidationFactorBps = _liquidationFactorBps;
    }

    function setReplenismentIncentiveBps(uint _replenishmentIncentiveBps) public onlyGov {
        require(_replenishmentIncentiveBps > 0 && _replenishmentIncentiveBps < 10000, "Invalid replenishment incentive");
        replenishmentIncentiveBps = _replenishmentIncentiveBps;
    }

    function setLiquidationIncentiveBps(uint _liquidationIncentiveBps) public onlyGov {
        require(_liquidationIncentiveBps > 0 && _liquidationIncentiveBps + liquidationFeeBps < 10000, "Invalid liquidation incentive");
        liquidationIncentiveBps = _liquidationIncentiveBps;
    }

    function setLiquidationFeeBps(uint _liquidationFeeBps) public onlyGov {
        require(_liquidationFeeBps > 0 && _liquidationFeeBps + liquidationIncentiveBps < 10000, "Invalid liquidation fee");
        liquidationFeeBps = _liquidationFeeBps;
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
        escrow.initialize(collateral, user);
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

    // Only use deposit() function for deposits and NOT the predicted escrow address unless you know what you're doing
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

    function getCollateralValue(address user) public view returns (uint) {
        IEscrow escrow = predictEscrow(user);
        uint collateralBalance = escrow.balance();
        return collateralBalance * oracle.viewPrice(address(collateral), collateralFactorBps) / 1 ether;
    }

    function getCollateralValueInternal(address user) internal returns (uint) {
        IEscrow escrow = predictEscrow(user);
        uint collateralBalance = escrow.balance();
        return collateralBalance * oracle.getPrice(address(collateral), collateralFactorBps) / 1 ether;
    }

    function getCreditLimit(address user) public view returns (uint) {
        uint collateralValue = getCollateralValue(user);
        return collateralValue * collateralFactorBps / 10000;
    }

    function getCreditLimitInternal(address user) internal returns (uint) {
        uint collateralValue = getCollateralValueInternal(user);
        return collateralValue * collateralFactorBps / 10000;
    }

    function getWithdrawalLimitInternal(address user) internal returns (uint) {
        IEscrow escrow = predictEscrow(user);
        uint collateralBalance = escrow.balance();
        if(collateralBalance == 0) return 0;
        uint debt = debts[user];
        if(debt == 0) return collateralBalance;
        if(collateralFactorBps == 0) return 0;
        uint minimumCollateral = debt * 1 ether / oracle.getPrice(address(collateral), collateralFactorBps) * 10000 / collateralFactorBps;
        if(collateralBalance <= minimumCollateral) return 0;
        return collateralBalance - minimumCollateral;
    }

    function getWithdrawalLimit(address user) public view returns (uint) {
        IEscrow escrow = predictEscrow(user);
        uint collateralBalance = escrow.balance();
        if(collateralBalance == 0) return 0;
        uint debt = debts[user];
        if(debt == 0) return collateralBalance;
        if(collateralFactorBps == 0) return 0;
        uint minimumCollateral = debt * 1 ether / oracle.viewPrice(address(collateral), collateralFactorBps) * 10000 / collateralFactorBps;
        if(collateralBalance <= minimumCollateral) return 0;
        return collateralBalance - minimumCollateral;
    }

    function borrowInternal(address borrower, address to, uint amount) internal {
        require(!borrowPaused, "Borrowing is paused");
        if(borrowController != IBorrowController(address(0))) {
            require(borrowController.borrowAllowed(msg.sender, borrower, amount), "Denied by borrow controller");
        }
        uint credit = getCreditLimitInternal(borrower);
        debts[borrower] += amount;
        require(credit >= debts[borrower], "Exceeded credit limit");
        totalDebt += amount;
        dbr.onBorrow(borrower, amount);
        dola.transfer(to, amount);
        emit Borrow(borrower, amount);
    }

    function borrow(uint amount) public {
        borrowInternal(msg.sender, msg.sender, amount);
    }

    function borrowOnBehalf(address from, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) public {
        require(deadline >= block.timestamp, "DEADLINE_EXPIRED");
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                msg.sender,
                                from,
                                amount,
                                nonces[from]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );
            require(recoveredAddress != address(0) && recoveredAddress == from, "INVALID_SIGNER");
            borrowInternal(from, msg.sender, amount);
        }
    }

    function withdrawInternal(address from, address to, uint amount) internal {
        uint limit = getWithdrawalLimitInternal(from);
        require(limit >= amount, "Insufficient withdrawal limit");
        IEscrow escrow = getEscrow(from);
        escrow.pay(to, amount);
        emit Withdraw(from, to, amount);
    }

    function withdraw(uint amount) public {
        withdrawInternal(msg.sender, msg.sender, amount);
    }

    function withdrawOnBehalf(address from, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) public {
        require(deadline >= block.timestamp, "DEADLINE_EXPIRED");
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                                ),
                                msg.sender,
                                from,
                                amount,
                                nonces[from]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );
            require(recoveredAddress != address(0) && recoveredAddress == from, "INVALID_SIGNER");
            withdrawInternal(from, msg.sender, amount);
        }
    }

    function invalidateNonce() public {
        nonces[msg.sender]++;
    }

    function repay(address user, uint amount) public {
        uint debt = debts[user];
        require(debt >= amount, "Insufficient debt");
        debts[user] -= amount;
        totalDebt -= amount;
        dbr.onRepay(user, amount);
        dola.transferFrom(msg.sender, address(this), amount);
        emit Repay(user, msg.sender, amount);
    }

    function repayAndWithdraw(uint repayAmount, uint withdrawAmount) public {
        repay(msg.sender, repayAmount);
        withdraw(withdrawAmount);
    }

    function forceReplenish(address user) public {
        uint deficit = dbr.deficitOf(user);
        require(deficit > 0, "No DBR deficit");
        uint replenishmentCost = deficit * dbr.replenishmentPriceBps() / 10000;
        uint replenisherReward = replenishmentCost * replenishmentIncentiveBps / 10000;
        debts[user] += replenishmentCost;
        uint collateralValue = getCollateralValueInternal(user);
        require(collateralValue >= debts[user], "Exceeded collateral value");
        totalDebt += replenishmentCost;
        dbr.onForceReplenish(user);
        dola.transfer(msg.sender, replenisherReward);
        emit ForceReplenish(user, msg.sender, deficit, replenishmentCost, replenisherReward);
    }

    function getLiquidatableDebt(address user) public view returns (uint) {
        uint debt = debts[user];
        if (debt == 0) return 0;
        uint credit = getCreditLimit(user);
        if(credit > debt) return 0;
        return debt * liquidationFactorBps / 10000;
    }

    function liquidate(address user, uint repaidDebt) public {
        require(repaidDebt > 0, "Must repay positive debt");
        uint debt = debts[user];
        require(getCreditLimitInternal(user) < debt, "User debt is healthy");
        require(repaidDebt <= debt * liquidationFactorBps / 10000, "Exceeded liquidation factor");
        uint price = oracle.getPrice(address(collateral), collateralFactorBps);
        uint liquidatorReward = repaidDebt * 1 ether / price;
        liquidatorReward += liquidatorReward * liquidationIncentiveBps / 10000;
        debts[user] -= repaidDebt;
        totalDebt -= repaidDebt;
        dbr.onRepay(user, repaidDebt);
        dola.transferFrom(msg.sender, address(this), repaidDebt);
        IEscrow escrow = predictEscrow(user);
        escrow.pay(msg.sender, liquidatorReward);
        if(liquidationFeeBps > 0) {
            uint liquidationFee = repaidDebt * 1 ether / price * liquidationFeeBps / 10000;
            if(escrow.balance() >= liquidationFee) {
                escrow.pay(gov, liquidationFee);
            }
        }
        emit Liquidate(user, msg.sender, repaidDebt, liquidatorReward);
    }

    event Borrow(address indexed account, uint amount);
    event Withdraw(address indexed account, address indexed to, uint amount);
    event Repay(address indexed account, address indexed repayer, uint amount);
    event ForceReplenish(address indexed account, address indexed replenisher, uint deficit, uint replenishmentCost, uint replenisherReward);
    event Liquidate(address indexed account, address indexed liquidator, uint repaidDebt, uint liquidatorReward);
    event CreateEscrow(address indexed user, address escrow);
}
