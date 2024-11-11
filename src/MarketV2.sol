// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "src/interfaces/IERC20.sol";

// Caution. We assume all failed transfers cause reverts and ignore the returned bool.
interface IOracle {
    function getPrice(address,uint) external returns (uint);
    function viewPrice(address,uint) external view returns (uint);
}

interface IEscrow {
    function initialize(IERC20 _token, address beneficiary) external;
    function onDeposit() external;
    function onDepositCallBack() external returns(uint);
    function pay(address recipient, uint amount) external;
    function balance() external view returns (uint);
}

interface IDolaBorrowingRights {
    function onBorrow(address user, uint additionalDebt) external;
    function onRepay(address user, uint repaidDebt) external;
    function onForceReplenish(address user, address replenisher, uint amount, uint replenisherReward) external;
    function balanceOf(address user) external view returns (uint);
    function deficitOf(address user) external view returns (uint);
    function replenishmentPriceBps() external view returns (uint);
}

interface IBorrowController {
    function borrowAllowed(address msgSender, address borrower, uint amount) external returns (bool);
    function onRepay(uint amount) external;
}

interface IDebtManager {
	function debt(address borrower) external view returns(uint);
	function totalDebt() external view returns(uint);
	function dbrDeficit(address borrower) external view returns(uint);
	function increaseDebt(address borrower, uint amount) external;
	function decreaseDebt(address borrower, uint amount) external returns(uint);
	function replenish(address borrower, uint amount) external;
}

contract MarketV2 {

    struct MarketParams {
        uint16 collateralFactorBps;
        uint16 maxLiquidationIncentiveThresholdBps;
        uint16 maxLiquidationIncentiveBps;
        uint16 maxLiquidationFeeBps;
        uint16 zeroLiquidationFeeThresholdBps;
        uint128 maxLiquidationAmount;
        bool borrowPaused;
    }

    address public gov;
    address public lender;
    address public pauseGuardian;
    address public defaultEscrowImplementation;
    address public defaultDebtManager;
    IDolaBorrowingRights public immutable dbr;
    IBorrowController public borrowController;
    IERC20 public immutable dola = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public immutable collateral;
    IOracle public oracle;
    MarketParams marketParameters;
    //TODO: Change to decimals factor
    uint256 public immutable decimals;
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;
    mapping (address => IEscrow) public escrows; // user => escrow
    mapping(address => uint256) public nonces; // user => nonce
    mapping(address => bool) isEscrowImplementation; // escrow implementation => bool
    mapping(address => bool) isDebtManager; // debt manager => bool
    mapping(address => IDebtManager) debtManagers; // user => debt manager

    constructor (
        address _gov,
        address _lender,
        address _pauseGuardian,
        address _defaultEscrowImplementation,
        address _defaultDebtManager,
        IDolaBorrowingRights _dbr,
        IERC20 _collateral,
        IOracle _oracle,
        MarketParams memory _marketParameters
    ) {
        checkParameters(_marketParameters);
        gov = _gov;
        lender = _lender;
        pauseGuardian = _pauseGuardian;
        defaultEscrowImplementation = _defaultEscrowImplementation;
        defaultDebtManager = _defaultDebtManager;
        dbr = _dbr;
        collateral = _collateral;
        decimals = 10**uint(IERC20(_collateral).decimals());
        oracle = _oracle;
        marketParameters = _marketParameters;
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    function checkParameters(MarketParams memory mp) public pure {
        //Collateral factor must be below 100%
        require(mp.collateralFactorBps < 10000, "Invalid collateral factor");
        //Max liquidation incentive must be between 0 and 100% 
        require(mp.maxLiquidationIncentiveBps > 0 && mp.maxLiquidationIncentiveBps < 10000, "Invalid liquidation incentive");
        //The incentive paid out at the max liquidation incentive threshold must never exceed the liquidators ability to liquidate fully
        require(mp.maxLiquidationIncentiveThresholdBps + uint(mp.maxLiquidationIncentiveThresholdBps) * mp.maxLiquidationIncentiveBps / 10000 < 10000, "Unsafe max liquidation parameter");
        //The CF threshold for max liquidations should never be below the safe
        require(mp.maxLiquidationIncentiveThresholdBps >= mp.collateralFactorBps && mp.maxLiquidationIncentiveThresholdBps <= 10000, "Invalid liquidation incentive");
        //Its fine to let fees exceed 10000 as maximum fee is always borrowers remaining collateral, but lets keep things sensical
        require(mp.maxLiquidationFeeBps < 10000, "Invalid liquidation fee"); 
        //Fees should always be 0 at max liquidation incentive
        require(mp.zeroLiquidationFeeThresholdBps <= mp.maxLiquidationIncentiveThresholdBps, "Invalid liquidation fee threshold");
    }
    
    modifier onlyGov {
        require(msg.sender == gov, "Only gov can call this function");
        _;
    }

    modifier marketParamChecker {
        _;
        checkParameters(marketParameters);
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

    /**
     * @notice sets the oracle to a new oracle. Only callable by governance.
     * @param _oracle The new oracle conforming to the IOracle interface.
    */
    function setOracle(IOracle _oracle) public onlyGov { oracle = _oracle; }

    /**
     * @notice sets the borrow controller to a new borrow controller. Only callable by governance.
     * @param _borrowController The new borrow controller conforming to the IBorrowController interface.
    */
    function setBorrowController(IBorrowController _borrowController) public onlyGov { borrowController = _borrowController; }

    /**
     * @notice sets the address of governance. Only callable by governance.
     * @param _gov Address of the new governance.
    */
    function setGov(address _gov) public onlyGov { gov = _gov; }

    /**
     * @notice sets the lender to a new lender. The lender is allowed to recall dola from the contract. Only callable by governance.
     * @param _lender Address of the new lender.
    */
    function setLender(address _lender) public onlyGov { lender = _lender; }

    /**
     * @notice sets the pause guardian. The pause guardian can pause borrowing. Only callable by governance.
     * @param _pauseGuardian Address of the new pauseGuardian.
    */
    function setPauseGuardian(address _pauseGuardian) public onlyGov { pauseGuardian = _pauseGuardian; }
    
    /**
     * @notice sets the Collateral Factor requirement of the market as measured in basis points. 1 = 0.01%. Only callable by governance.
     * @dev Collateral factor must be set below 100%
     * @param _collateralFactorBps The new collateral factor as measured in basis points. 
    */
    function setCollateralFactorBps(uint16 _collateralFactorBps) public onlyGov marketParamChecker {
        require(_collateralFactorBps < 10000, "Invalid collateral factor");
        marketParameters.collateralFactorBps = _collateralFactorBps;
    }

    /**
     * @notice sets the maxLiquidationAmount for the market in DOLA terms. Only callable by governance.
     * @param _maxLiquidationAmount The maximum amount of debt that can be liquidated.
    */
    function setMaxLiquidationAmount(uint128 _maxLiquidationAmount) public onlyGov marketParamChecker {
        marketParameters.maxLiquidationAmount = _maxLiquidationAmount;
    }

    /**
     * @notice sets the Liquidation Incentive of the market as denoted in basis points.
     The Liquidation Incentive is the percentage paid out to liquidators of a borrower's debt when successfully liquidated.
     * @dev Must be set between 0 and 10000 - liquidation fee.
     * @param _maxLiquidationIncentiveBps The new liqudation incentive set in basis points. 1 = 0.01% 
    */
    function setMaxLiquidationIncentiveBps(uint16 _maxLiquidationIncentiveBps) public onlyGov marketParamChecker {
        require(_maxLiquidationIncentiveBps > 0 && _maxLiquidationIncentiveBps <= 10000, "Invalid liquidation incentive");
        marketParameters.maxLiquidationIncentiveBps = _maxLiquidationIncentiveBps;
    }

    /**
     * @notice sets the Liquidation Incentive of the market as denoted in basis points.
     The Liquidation Incentive is the percentage paid out to liquidators of a borrower's debt when successfully liquidated.
     * @dev Must be set between 0 and 10000 - liquidation fee.
     * @param _maxLiquidationIncentiveThresholdBps The new liqudation incentive set in basis points. 1 = 0.01% 
    */
    function setMaxLiquidationIncentiveThresholdBps(uint16 _maxLiquidationIncentiveThresholdBps) public onlyGov marketParamChecker {
        require(_maxLiquidationIncentiveThresholdBps >= marketParameters.collateralFactorBps && _maxLiquidationIncentiveThresholdBps <= 10000, "Invalid liquidation incentive");
        marketParameters.maxLiquidationIncentiveThresholdBps = _maxLiquidationIncentiveThresholdBps;
    }

    /**
     * @notice sets the Liquidation Fee of the market as denoted in basis points.
     The Liquidation Fee is the percentage paid out to governance of a borrower's debt when successfully liquidated.
     * @dev Must be set between 0 and 10000 - liquidation factor.
     * @param _maxLiquidationFeeBps The new liquidation fee set in basis points. 1 = 0.01%
    */
    function setMaxLiquidationFeeBps(uint16 _maxLiquidationFeeBps) public onlyGov marketParamChecker {
        require(_maxLiquidationFeeBps < 10000, "Invalid liquidation fee");
        marketParameters.maxLiquidationFeeBps = _maxLiquidationFeeBps;
    }

    /**
     * @notice sets the Liquidation Fee of the market as denoted in basis points.
     The Liquidation Fee is the percentage paid out to governance of a borrower's debt when successfully liquidated.
     * @dev Must be set between 0 and 10000 - liquidation factor.
     * @param _zeroLiquidationFeeThresholdBps The new liquidation fee set in basis points. 1 = 0.01%
    */
    function setZeroLiquidationFeeThresholdBps(uint16 _zeroLiquidationFeeThresholdBps) public onlyGov marketParamChecker {
        require(_zeroLiquidationFeeThresholdBps <= marketParameters.maxLiquidationIncentiveThresholdBps, "Invalid liquidation fee threshold");
        marketParameters.zeroLiquidationFeeThresholdBps = _zeroLiquidationFeeThresholdBps;
    }

    function setEscrowImplementation(address escrow, bool isAllowed) public onlyGov {
        isEscrowImplementation[escrow] = isAllowed;
    }

    function setDebtManager(address debtManager, bool isAllowed) public onlyGov {
        isDebtManager[debtManager] = isAllowed;
    }

    /**
     * @notice Recalls amount of DOLA to the lender.
     * @param amount The amount od DOLA to recall to the the lender.
    */
    function recall(uint amount) public {
        require(msg.sender == lender, "Only lender can recall");
        dola.transfer(msg.sender, amount);
    }

    /**
     * @notice Pauses or unpauses borrowing for the market. Only gov can unpause a market, while gov and pauseGuardian can pause it.
     * @param _value Boolean representing the state pause state of borrows. true = paused, false = unpaused.
    */
    function pauseBorrows(bool _value) public {
        if(_value) {
            require(msg.sender == pauseGuardian || msg.sender == gov, "Only pause guardian or governance can pause");
        } else {
            require(msg.sender == gov, "Only governance can unpause");
        }
        marketParameters.borrowPaused = _value;
    }

    /**
     * @notice Internal function for creating an escrow for users to deposit collateral in.
     * @dev Uses create2 and minimal proxies to create the escrow at a deterministic address
     * @param user The address of the user to create an escrow for.
    */
    function createEscrow(address user, address implementation) internal returns (IEscrow instance) {
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

    /**
     * @notice Internal function for getting the escrow of a user.
     * @dev If the escrow doesn't exist, an escrow contract is deployed.
     * @param user The address of the user owning the escrow.
    */
    function getEscrow(address user) internal returns (IEscrow) {
        if(escrows[user] != IEscrow(address(0))) return escrows[user];
        IEscrow escrow = createEscrow(user, defaultEscrowImplementation);
        escrow.initialize(collateral, user);
        escrows[user] = escrow;
        return escrow;
    }

    function switchEscrow(address user, address escrowImplementation) external {
        require(msg.sender == user, "Must own escrow or be debt manager");
        require(isEscrowImplementation[escrowImplementation], "Must be allowed escrow implementation");
        IEscrow escrow = getEscrow(user);
        IEscrow newEscrow = predictEscrow(user, escrowImplementation);
        if(address(newEscrow).code.length == 0)
            newEscrow = createEscrow(user, escrowImplementation);
        escrow.pay(address(newEscrow), escrow.balance());
        newEscrow.onDeposit();
        escrows[user] = newEscrow;
        /*TODO: Consider making sure
            1. Balance remains the same or greater
            2. CreditLimit remains the same or greater
        */
    }

    function switchDebtManager(address user, IDebtManager newDebtManager) external {
        require(msg.sender == user || msg.sender == address(debtManagers[user]), "Must own escrow or be debt manager");
        require(isDebtManager[address(newDebtManager)], "Must be allowed debt manager");
        IDebtManager debtManager = debtManagers[user];
        if(debtManager.dbrDeficit(user) == 0){
            uint debt = debtManager.debt(user);
            debtManager.decreaseDebt(user, debt);
            newDebtManager.increaseDebt(user, debt);
            debtManagers[user] = newDebtManager;
        }
    }

    /**
     * @notice Deposit amount of collateral into escrow
     * @dev Will deposit the amount into the escrow contract.
     * @param amount Amount of collateral token to deposit.
    */
    function deposit(uint amount) public {
        deposit(msg.sender, amount);
    }

    /**
     * @notice Deposit and borrow in a single transaction.
     * @param amountDeposit Amount of collateral token to deposit into escrow.
     * @param amountBorrow Amount of DOLA to borrow.
    */
    function depositAndBorrow(uint amountDeposit, uint amountBorrow) public {
        deposit(amountDeposit);
        borrow(amountBorrow);
    }

    /**
     * @notice Deposit amount of collateral into escrow on behalf of msg.sender
     * @dev Will deposit the amount into the escrow contract.
     * @param user User to deposit on behalf of.
     * @param amount Amount of collateral token to deposit.
    */
    function deposit(address user, uint amount) public {
        IEscrow escrow = getEscrow(user);
        collateral.transferFrom(msg.sender, address(escrow), amount);
        escrow.onDeposit();
        emit Deposit(user, amount);
    }

    /**
     * @notice View function for predicting the deterministic escrow address of a user.
     * @dev Only use deposit() function for deposits and NOT the predicted escrow address unless you know what you're doing
     * @param borrower Address of the user owning the escrow.
    */
    function predictEscrow(address borrower, address implementation) public view returns (IEscrow predicted) {
        address deployer = address(this);
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf3ff00000000000000000000000000000000)
            mstore(add(ptr, 0x38), shl(0x60, deployer))
            mstore(add(ptr, 0x4c), borrower)
            mstore(add(ptr, 0x6c), keccak256(ptr, 0x37))
            predicted := keccak256(add(ptr, 0x37), 0x55)
        }
    }

    function getLiquidationIncentiveBps(uint borrowerCollateralFactorBps) public view returns (uint) {
        MarketParams memory mp = marketParameters; //Cache marketParameters
        return calcLiquidationIncentiveBps(mp, borrowerCollateralFactorBps);
    }

    function calcLiquidationIncentiveBps(MarketParams memory mp, uint borrowerCollateralFactorBps) internal pure returns (uint) {
        if(borrowerCollateralFactorBps <= mp.collateralFactorBps) return 0;
        if(borrowerCollateralFactorBps >= mp.maxLiquidationIncentiveThresholdBps) return mp.maxLiquidationIncentiveBps;
        return mp.maxLiquidationIncentiveBps * (borrowerCollateralFactorBps - mp.collateralFactorBps) / (mp.maxLiquidationIncentiveThresholdBps - mp.collateralFactorBps);
    }

    function getLiquidationFeeBps(uint borrowerCollateralFactorBps) public view returns (uint) {
        MarketParams memory mp = marketParameters; //Cache marketParameters
        return calcLiquidationFeeBps(mp, borrowerCollateralFactorBps);
    }

    function calcLiquidationFeeBps(MarketParams memory mp, uint borrowerCollateralFactorBps) public pure returns (uint) {
        if(mp.maxLiquidationFeeBps == 0) return 0;
        if(borrowerCollateralFactorBps < mp.collateralFactorBps) return 0;
        if(borrowerCollateralFactorBps >= mp.zeroLiquidationFeeThresholdBps) return 0;
        uint distBps = 10000 * (borrowerCollateralFactorBps - mp.collateralFactorBps) / (mp.zeroLiquidationFeeThresholdBps - mp.collateralFactorBps);
        return mp.maxLiquidationFeeBps * (10000 - distBps) / 10000;
    }

    /**
     * @notice View function for getting the dollar value of the user's collateral in escrow for the market.
     * @param user Address of the user.
    */
    function getCollateralValue(address user) public view returns (uint) {
        uint collateralBalance = escrows[user].balance();
        return calcCollateralValue(collateralBalance, oracle.viewPrice(address(collateral), marketParameters.collateralFactorBps));
    }

    /**
     * @notice Internal function for getting the dollar value of the user's collateral in escrow for the market.
     * @dev Updates the lowest price comparisons of the pessimistic oracle
     * @param user Address of the user.
    */
    function getCollateralValueInternal(address user) internal returns (uint) {
        uint collateralBalance = escrows[user].balance();
        return calcCollateralValue(collateralBalance, oracle.getPrice(address(collateral), marketParameters.collateralFactorBps));
    }

    function calcCollateralValue(uint collateralBalance, uint price) internal pure returns (uint) {
        return collateralBalance * price / 1 ether;
    }

    /**
     * @notice View function for getting the credit limit of a user.
     * @dev To calculate the available credit, subtract user debt from credit limit.
     * @param user Address of the user.
    */
    function getCreditLimit(address user) public view returns (uint) {
        uint collateralValue = getCollateralValue(user);
        return calcCreditLimit(collateralValue, marketParameters.collateralFactorBps);
    }

    /**
     * @notice Internal function for getting the credit limit of a user.
     * @dev To calculate the available credit, subtract user debt from credit limit. Updates the pessimistic oracle.
     * @param user Address of the user.
    */
    function getCreditLimitInternal(address user) internal returns (uint) {
        uint collateralValue = getCollateralValueInternal(user);
        return calcCreditLimit(collateralValue, marketParameters.collateralFactorBps);
    }

    function calcCreditLimit(uint collateralValue, uint collateralFactorBps) internal pure returns (uint) {
        return collateralValue * collateralFactorBps / 10000;
    }

    /**
     * @notice Internal function for getting the withdrawal limit of a user.
     * @dev Updates oracle state
     The withdrawal limit is how much collateral a user can withdraw before their loan would be underwater. Updates the pessimistic oracle.
     * @param user Address of the user.
    */
    function getWithdrawalLimitInternal(address user) internal returns (uint) {
        return _withdrawalLimit(user, oracle.getPrice(address(collateral), marketParameters.collateralFactorBps));
    }

    /**
     * @notice View function for getting the withdrawal limit of a user.
     The withdrawal limit is how much collateral a user can withdraw before their loan would be underwater.
     * @param user Address of the user.
    */
    function getWithdrawalLimit(address user) public view returns (uint) {
        return _withdrawalLimit(user, oracle.viewPrice(address(collateral), marketParameters.collateralFactorBps));
    }

    function _withdrawalLimit(address user, uint price) internal view returns (uint) {
        uint collateralBalance = escrows[user].balance();
        if(collateralBalance == 0) return 0;
        uint collateralFactorBps = marketParameters.collateralFactorBps;
        if(collateralFactorBps == 0) return 0;
        uint debt = debtManagers[user].debt(user);
        if(debt == 0) return collateralBalance;
        uint minimumCollateral = debt * 1 ether / price * 10000 / collateralFactorBps;
        if(collateralBalance <= minimumCollateral) return 0;
        return collateralBalance - minimumCollateral;
    }

    /**
     * @notice Internal function for borrowing DOLA against collateral.
     * @dev This internal function is shared between the borrow and borrowOnBehalf function
     * @param borrower The address of the borrower that debt will be accrued to.
     * @param to The address that will receive the borrowed DOLA
     * @param amount The amount of DOLA to be borrowed
    */
    function borrowInternal(address borrower, address to, uint amount) internal {
        IDebtManager debtManager = debtManagers[borrower];
        require(!marketParameters.borrowPaused, "Borrowing is paused");
        if(borrowController != IBorrowController(address(0))) {
            require(borrowController.borrowAllowed(msg.sender, borrower, amount), "Denied by borrow controller");
        }
        uint credit = getCreditLimitInternal(borrower);
        debtManager.increaseDebt(borrower, amount);
        require(credit >= debtManager.debt(borrower), "Exceeded credit limit");
        dola.transfer(to, amount);
        emit Borrow(borrower, amount);
    }

    /**
     * @notice Function for borrowing DOLA.
     * @dev Will borrow to msg.sender
     * @param amount The amount of DOLA to be borrowed.
    */
    function borrow(uint amount) public {
        borrowInternal(msg.sender, msg.sender, amount);
    }

    /**
     * @notice Function for using a signed message to borrow on behalf of an address owning an escrow with collateral.
     * @dev Signed messaged can be invalidated by incrementing the nonce. Will always borrow to the msg.sender.
     * @param from The address of the user being borrowed from
     * @param amount The amount to be borrowed
     * @param deadline Timestamp after which the signed message will be invalid
     * @param v The v param of the ECDSA signature
     * @param r The r param of the ECDSA signature
     * @param s The s param of the ECDSA signature
    */
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

    /**
     * @notice Internal function for withdrawing from the escrow
     * @dev The internal function is shared by the withdraw function and withdrawOnBehalf function
     * @param from The address owning the escrow to withdraw from.
     * @param to The address receiving the tokens
     * @param amount The amount being withdrawn.
    */
    function withdrawInternal(address from, address to, uint amount) internal {
        uint limit = getWithdrawalLimitInternal(from);
        require(limit >= amount, "Insufficient withdrawal limit");
        require(dbr.deficitOf(from) == 0, "Can't withdraw with DBR deficit");
        IEscrow escrow = getEscrow(from);
        escrow.pay(to, amount);
        emit Withdraw(from, to, amount);
    }

    /**
     * @notice Function for withdrawing to msg.sender.
     * @param amount Amount to withdraw.
    */
    function withdraw(uint amount) public {
        withdrawInternal(msg.sender, msg.sender, amount);
    }

    /**
     * @notice Function for withdrawing maximum allowed to msg.sender.
     * @dev Useful for use with escrows that continously compound tokens, so there won't be dust amounts left
     * @dev Dangerous to use when the user has any amount of debt!
    */
    function withdrawMax() public {
        withdrawInternal(msg.sender, msg.sender, getWithdrawalLimitInternal(msg.sender));
    }

    /**
     * @notice Function for using a signed message to withdraw on behalf of an address owning an escrow with collateral.
     * @dev Signed messaged can be invalidated by incrementing the nonce. Will always withdraw to the msg.sender.
     * @param from The address of the user owning the escrow being withdrawn from
     * @param amount The amount to be withdrawn
     * @param deadline Timestamp after which the signed message will be invalid
     * @param v The v param of the ECDSA signature
     * @param r The r param of the ECDSA signature
     * @param s The s param of the ECDSA signature
    */
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

    /**
     * @notice Function for using a signed message to withdraw on behalf of an address owning an escrow with collateral.
     * @dev Signed messaged can be invalidated by incrementing the nonce. Will always withdraw to the msg.sender.
     * @dev Useful for use with escrows that continously compound tokens, so there won't be dust amounts left
     * @dev Dangerous to use when the user has any amount of debt!
     * @param from The address of the user owning the escrow being withdrawn from
     * @param deadline Timestamp after which the signed message will be invalid
     * @param v The v param of the ECDSA signature
     * @param r The r param of the ECDSA signature
     * @param s The s param of the ECDSA signature
    */
    function withdrawMaxOnBehalf(address from, uint deadline, uint8 v, bytes32 r, bytes32 s) public {
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
                                    "WithdrawMaxOnBehalf(address caller,address from,uint256 nonce,uint256 deadline)"
                                ),
                                msg.sender,
                                from,
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
            withdrawInternal(from, msg.sender, getWithdrawalLimitInternal(from));
        }
    }

    /**
     * @notice Function for incrementing the nonce of the msg.sender, making their latest signed message unusable.
    */
    function invalidateNonce() public {
        nonces[msg.sender]++;
    }
    
    /**
     * @notice Function for repaying debt on behalf of user. Debt must be repaid in DOLA.
     * @dev If the user has a DBR deficit, they risk initial debt being accrued by forced replenishments.
     * @param borrower Address of the borrower whose debt is being repaid
     * @param amount DOLA amount to be repaid. If set to max uint debt will be repaid in full.
    */
    function repay(address borrower, uint amount) public {
        IDebtManager debtManager = debtManagers[borrower];
        amount = debtManager.decreaseDebt(borrower, amount);

        if(address(borrowController) != address(0)){
            borrowController.onRepay(amount);
        }

        dola.transferFrom(msg.sender, address(this), amount);
        emit Repay(borrower, msg.sender, amount);
    }

    /**
     * @notice Bundles repayment and withdrawal into a single function call.
     * @param repayAmount Amount of DOLA to be repaid
     * @param withdrawAmount Amount of underlying to be withdrawn from the escrow
    */
    function repayAndWithdraw(uint repayAmount, uint withdrawAmount) public {
        repay(msg.sender, repayAmount);
        withdraw(withdrawAmount);
    }

    /**
     * @notice Function for liquidating a user's under water debt. Debt is under water when the value of a user's debt is above their collateral factor.
     * @param borrower The user to be liquidated
     * @param repaidDebt Th amount of user user debt to liquidate.
    */
    function liquidate(address borrower, uint repaidDebt) public {
        MarketParams memory mp = marketParameters; //cache MarketParameters
        uint price = oracle.getPrice(address(collateral), mp.collateralFactorBps);
        IEscrow escrow = escrows[borrower];
        uint balance = escrow.balance();
        uint collateralValue = calcCollateralValue(balance, price);
        IDebtManager debtManager = debtManagers[borrower];
        require(repaidDebt > 0, "Must repay positive debt");
        uint debt = debtManager.debt(borrower);
        uint borrowerCollateralFactorBps = 10000 * debt / collateralValue;
        require(calcCreditLimit(collateralValue, mp.collateralFactorBps) < debt, "User debt is healthy");
        uint maxLiquidationAmount = mp.maxLiquidationAmount < debt ? mp.maxLiquidationAmount : debt;
        repaidDebt = debtManager.decreaseDebt(borrower, repaidDebt);
        require(repaidDebt < maxLiquidationAmount, "Repaid debt exceeds max liquidation amount");
        uint liquidatorReward = repaidDebt * 1 ether / price;
        liquidatorReward += liquidatorReward * calcLiquidationIncentiveBps(mp, borrowerCollateralFactorBps) / 10000;
        if(address(borrowController) != address(0)){
            borrowController.onRepay(repaidDebt);
        }
        dola.transferFrom(msg.sender, address(this), repaidDebt);
        escrow.pay(msg.sender, liquidatorReward);
        if(calcLiquidationFeeBps(mp, borrowerCollateralFactorBps) > 0) {
            uint liquidationFee = repaidDebt * 1 ether / price * calcLiquidationFeeBps(mp, borrowerCollateralFactorBps) / 10000;
            uint remainingBalance = balance - liquidatorReward;
            if(remainingBalance >= liquidationFee) {
                escrow.pay(gov, liquidationFee);
            } else if(remainingBalance > 0) {
                escrow.pay(gov, remainingBalance);
            }
        }
        emit Liquidate(borrower, msg.sender, repaidDebt, liquidatorReward);
    }
    
    event Deposit(address indexed account, uint amount);
    event Borrow(address indexed account, uint amount);
    event Withdraw(address indexed account, address indexed to, uint amount);
    event Repay(address indexed account, address indexed repayer, uint amount);
    event Liquidate(address indexed account, address indexed liquidator, uint repaidDebt, uint liquidatorReward);
    event CreateEscrow(address indexed user, address escrow);
}
