// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract DolaBorrowingRights {

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public _totalSupply;
    address public operator;
    address public pendingOperator;
    uint public totalDueTokensAccrued;
    uint public replenishmentPriceBps;
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;
    mapping(address => uint256) public nonces;
    mapping (address => bool) public minters;
    mapping (address => bool) public markets;
    mapping (address => uint) public debts; // user => debt across all tracked markets
    mapping (address => uint) public dueTokensAccrued; // user => amount of due tokens accrued
    mapping (address => uint) public lastUpdated; // user => last update timestamp

    constructor(
        uint _replenishmentPriceBps,
        string memory _name,
        string memory _symbol,
        address _operator
    ) {
        replenishmentPriceBps = _replenishmentPriceBps;
        name = _name;
        symbol = _symbol;
        operator = _operator;
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    modifier onlyOperator {
        require(msg.sender == operator, "ONLY OPERATOR");
        _;
    }

    function setPendingOperator(address newOperator_) public onlyOperator {
        pendingOperator = newOperator_;
    }

    function setReplenishmentPriceBps(uint newReplenishmentPriceBps) public onlyOperator {
        require(newReplenishmentPriceBps > 0, "replenishment price must be over 0");
        replenishmentPriceBps = newReplenishmentPriceBps;
    }

    function claimOperator() public {
        require(msg.sender == pendingOperator, "ONLY PENDING OPERATOR");
        operator = pendingOperator;
        pendingOperator = address(0);
        emit ChangeOperator(operator);
    }

    function addMinter(address minter_) public onlyOperator {
        minters[minter_] = true;
        emit AddMinter(minter_);
    }

    function removeMinter(address minter_) public onlyOperator {
        minters[minter_] = false;
        emit RemoveMinter(minter_);
    }

    // markets can be added but cannot be removed. A removed market would result in unrepayable debt for some users.
    function addMarket(address market_) public onlyOperator {
        markets[market_] = true;
        emit AddMarket(market_);
    }

    function totalSupply() public view returns (uint) {
        if(totalDueTokensAccrued > _totalSupply) return 0;
        return _totalSupply - totalDueTokensAccrued;
    }

    function balanceOf(address user) public view returns (uint) {
        uint debt = debts[user];
        uint accrued = (block.timestamp - lastUpdated[user]) * debt / 365 days;
        if(dueTokensAccrued[user] + accrued > balances[user]) return 0;
        return balances[user] - dueTokensAccrued[user] - accrued;
    }

    function deficitOf(address user) public view returns (uint) {
        uint debt = debts[user];
        uint accrued = (block.timestamp - lastUpdated[user]) * debt / 365 days;
        if(dueTokensAccrued[user] + accrued < balances[user]) return 0;
        return dueTokensAccrued[user] + accrued - balances[user];
    }

    function signedBalanceOf(address user) public view returns (int) {
        uint debt = debts[user];
        uint accrued = (block.timestamp - lastUpdated[user]) * debt / 365 days;
        return int(balances[user]) - int(dueTokensAccrued[user]) - int(accrued);
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        unchecked {
            balances[to] += amount;
        }
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        require(balanceOf(from) >= amount, "Insufficient balance");
        balances[from] -= amount;
        unchecked {
            balances[to] += amount;
        }
        emit Transfer(from, to, amount);
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );
            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");
            allowance[recoveredAddress][spender] = value;
        }
        emit Approval(owner, spender, value);
    }

    function invalidateNonce() public {
        nonces[msg.sender]++;
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes(name)),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    function accrueDueTokens(address user) public {
        uint debt = debts[user];
        if(lastUpdated[user] == block.timestamp) return;
        uint accrued = (block.timestamp - lastUpdated[user]) * debt / 365 days;
        dueTokensAccrued[user] += accrued;
        totalDueTokensAccrued += accrued;
        lastUpdated[user] = block.timestamp;
        emit Transfer(user, address(0), accrued);
    }

    function onBorrow(address user, uint additionalDebt) public {
        require(markets[msg.sender], "Only markets can call onBorrow");
        accrueDueTokens(user);
        require(balanceOf(user) > 0, "Insufficient balance");
        debts[user] += additionalDebt;
    }

    function onRepay(address user, uint repaidDebt) public {
        require(markets[msg.sender], "Only markets can call onRepay");
        accrueDueTokens(user);
        debts[user] -= repaidDebt;
    }

    function onForceReplenish(address user, uint amount) public {
        require(markets[msg.sender], "Only markets can call onForceReplenish");
        uint deficit = deficitOf(user);
        require(deficit > 0, "No deficit");
        require(deficit >= amount, "Amount > deficit");
        uint replenishmentCost = amount * replenishmentPriceBps / 10000;
        accrueDueTokens(user);
        debts[user] += replenishmentCost;
        _mint(user, amount);
    }

    function burn(uint amount) public {
        _burn(msg.sender, amount);
    }

    function mint(address to, uint amount) public {
        require(minters[msg.sender] == true || msg.sender == operator, "ONLY MINTERS OR OPERATOR");
        _mint(to, amount);
    }

    function _mint(address to, uint256 amount) internal virtual {
        _totalSupply += amount;
        unchecked {
            balances[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        require(balanceOf(from) >= amount, "Insufficient balance");
        balances[from] -= amount;
        unchecked {
            _totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event AddMinter(address indexed minter);
    event RemoveMinter(address indexed minter);
    event AddMarket(address indexed market);
    event ChangeOperator(address indexed newOperator);
}
