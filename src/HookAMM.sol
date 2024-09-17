// SPDX-License-Identifier: MIT License
pragma solidity 0.8.20;

interface IERC20 {
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
}

interface Mintable is IERC20 {
    function burn(uint) external;
    function mint(address, uint) external;
}

interface IVariableDebtManager {
    function buyHook() external returns (bool);
}

/**
 * @title HookAMM
 * @dev Limited access xy=k AMM designed to be maximally manipulation resistant on behalf of the DebtManager and FiRMv2 markets
*/
contract HookAMM {
    
    Mintable public immutable dbr;
    IERC20 public immutable dola;
    IVariableDebtManager public variableDebtManager;
    address public gov;
    address public pendingGov;
    address public feeRecipient;
    uint public prevK;
    uint public targetK;
    uint public lastKUpdate;
    uint public maxDbrPrice;
    uint public dbrBuyFee;
    uint public feesAccrued;

    error Invariant();

    /**
     * @dev Constructor for sDola contract.
     * WARNING: MIN_SHARES will always be unwithdrawable from the vault. Deployer should deposit enough to mint MIN_SHARES to avoid causing user grief.
     * @param _dola Address of the DOLA token.
     * @param _gov Address of the governance.
     * @param _K Initial value for the K variable used in calculations.
     */
    constructor(
        address _dola,
        address _dbr,
        address _gov,
        address _feeRecipient,
        uint _K
    ) {
        require(_K > 0, "_K must be positive");
        dbr = Mintable(_dbr);
        dola = IERC20(_dola);
        gov = _gov;
        feeRecipient = _feeRecipient;
        targetK = _K;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "ONLY GOV");
        _;
    }

    modifier buyHook() {
        variableDebtManager.buyHook();
        _;
    }

    /**
     * @dev Returns the current value of K, which is a weighted average between prevK and targetK.
     * @return The current value of K.
     */
    function getK() public view returns (uint) {
        uint duration = 7 days;
        uint timeElapsed = block.timestamp - lastKUpdate;
        if(timeElapsed > duration) {
            return targetK;
        }
        uint targetWeight = timeElapsed;
        uint prevWeight = duration - timeElapsed;
        return (prevK * prevWeight + targetK * targetWeight) / duration;
    }

    /**
     * @dev Calculates the DOLA reserve based on the current DBR reserve.
     * @return The calculated DOLA reserve.
     */
    function getDolaReserve() public view returns (uint) {
        return dola.balanceOf(address(this));
    }

    /**
     * @dev Returns the current DBR reserve as the sum of dbr balance and claimable dbr
     * @return The current DBR reserve.
     */
    function getDbrReserve() public view returns (uint) {
        return getK() / getDolaReserve();
    }

    /**
     * @dev Sets a new target K value.
     * @param _K The new target K value.
     */
    function setTargetK(uint _K) external onlyGov {
        require(_K > getDbrReserve(), "K must be larger than dbr reserve");
        prevK = getK();
        targetK = _K;
        lastKUpdate = block.timestamp;
        emit SetTargetK(_K);
    }

    /**
     * @dev Allows users to buy DBR with DOLA.
     * WARNING: Never expose this directly to a UI as it's likely to cause a loss unless a transaction is executed immediately.
     * Instead use the sDolaHelper function or custom smart contract code.
     * @param exactDolaIn The exact amount of DOLA to spend.
     * @param exactDbrOut The exact amount of DBR to receive.
     * @param to The address that will receive the DBR.
     */
    function buyDBR(uint exactDolaIn, uint exactDbrOut, address to) external buyHook {
        require(to != address(0), "Zero address");
        _invariantCheck(exactDolaIn, exactDbrOut, getDbrReserve());
        dola.transferFrom(msg.sender, address(this), exactDolaIn);
        uint dbrBal = dbr.balanceOf(address(this));
        if(exactDbrOut > dbrBal)
            dbr.mint(address(this), exactDbrOut - dbrBal);
        uint exactDbrOutAfterFee = exactDbrOut * (1e18 - dbrBuyFee) / 1e18;
        feesAccrued += exactDbrOut - exactDbrOutAfterFee;
        dbr.transfer(to, exactDbrOutAfterFee);
        emit BuyDBR(msg.sender, to, exactDolaIn, exactDbrOut);
    }

    function burnDBR(uint exactDolaIn, uint exactDbrBurn) external buyHook {
        _invariantCheck(exactDolaIn, exactDbrBurn, getDbrReserve());
        dola.transferFrom(msg.sender, address(this), exactDolaIn);
        dbr.burn(exactDbrBurn);
        emit Burn(msg.sender, exactDolaIn, exactDbrBurn);
    }

    function buyDola(uint exactDbrIn, uint exactDolaOut, address to) external buyHook {
        require(to != address(0), "Zero address");
        _invariantCheck(exactDbrIn, exactDolaOut, getDolaReserve());
        dbr.transferFrom(msg.sender, address(this), exactDolaOut);
        dola.transfer(to, exactDbrIn);
        emit BuyDOLA(msg.sender, to, exactDbrIn, exactDolaOut);
    }

    function _invariantCheck(uint exactIn, uint exactOut, uint outBalance) internal view {
        //TODO: Add max dbr price check
        uint k = getK();
        uint reserveOut = outBalance - exactOut;
        uint reserveIn = k / outBalance + exactIn;
        if(reserveOut * reserveIn < k) revert Invariant();
    }

    /**
     * @dev Sets a new pending governance address.
     * @param _gov The address of the new pending governance.
     */
    function setPendingGov(address _gov) external onlyGov {
        pendingGov = _gov;
    }

    /**
     * @dev Allows the pending governance to accept its role.
     */
    function acceptGov() external {
        require(msg.sender == pendingGov, "ONLY PENDINGGOV");
        gov = pendingGov;
        pendingGov = address(0);
    }

    /**
     * @dev Allows governance to sweep any ERC20 token from the contract.
     * @dev Excludes the ability to sweep DBR tokens.
     * @param token The address of the ERC20 token to sweep.
     * @param amount The amount of tokens to sweep.
     * @param to The recipient address of the swept tokens.
     */
    function sweep(address token, uint amount, address to) public onlyGov {
        require(address(dbr) != token, "Not authorized");
        IERC20(token).transfer(to, amount);
    }

    function harvest() public {
        uint dbrBalance = dbr.balanceOf(address(this));
        if(dbrBalance < feesAccrued){
            dbr.mint(address(this), feesAccrued - dbrBalance);
        }
        dbr.transfer(feeRecipient, feesAccrued);
        feesAccrued = 0;
    }

    event BuyDBR(address indexed caller, address indexed to, uint exactDolaIn, uint exactDbrOut);
    event BuyDOLA(address indexed caller, address indexed to, uint exactDbrIn, uint exactDolaOut);
    event Burn(address indexed caller, uint exactDolaIn, uint exactDbrBurn);
    event SetTargetK(uint newTargetK);
}
