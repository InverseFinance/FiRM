// SPDX-License-Identifier: MIT License
pragma solidity 0.8.20;

interface IERC20 {
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
    function balanceOf(address) external view returns (uint);
}

interface IERC20Stream {
    function unclaimed() external view returns (uint amountUnclaimed);
    function claimTo(uint amount, address receiver) external;
    function claimTo(address receiver) external returns (uint amountClaimed);
}

/**
 * @title sDola
 * @dev Auto-compounding ERC4626 wrapper for DolaSacings utilizing xy=k auctions.
 * WARNING: While this vault is safe to be used as collateral in lending markets, it should not be allowed as a borrowable asset.
 * Any protocol in which sudden, large and atomic increases in the value of an asset may be a securit risk should not integrate this vault.
 */
contract HookAMM {
    
    IERC20 public immutable dbr;
    IERC20 public immutable dola;
    IERC20Stream public dbrStream;
    IERC20Stream public dolaStream;
    address public gov;
    address public pendingGov;
    uint public prevK;
    uint public targetK;
    uint public lastKUpdate;

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
        uint _K
    ) {
        require(_K > 0, "_K must be positive");
        dbr = _dbr;
        gov = _gov;
        targetK = _K;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "ONLY GOV");
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
        return getK() / getDbrReserve() + dolaStream.claimable();
    }

    /**
     * @dev Calculates the DOLA reserve for a given DBR reserve.
     * @param dbrReserve The DBR reserve value.
     * @return The calculated DOLA reserve.
     */
    function getDolaReserve(uint dbrReserve) public view returns (uint) {
        return getK() / dbrReserve;
    }

    /**
     * @dev Returns the current DBR reserve as the sum of dbr balance and claimable dbr
     * @return The current DBR reserve.
     */
    function getDbrReserve() public view returns (uint) {
        return dbr.balanceOf(address(this)) + dbrStream.claimable();
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
    function buyDBR(uint exactDolaIn, uint exactDbrOut, address to) external {
        require(to != address(0), "Zero address");
        uint dbrBalance = getDbrReserve();
        if(exactDbrOut > dbr.balanceOf(address(this))){
            savings.claim(address(this));
        }
        uint k = getK();
        uint dbrReserve = dbrBalance - exactDbrOut;
        uint dolaReserve = k / dbrBalance + exactDolaIn;
        require(dolaReserve * dbrReserve >= k, "Invariant");
        asset.transferFrom(msg.sender, address(this), exactDolaIn);
        savings.stake(exactDolaIn, address(this));
        weeklyRevenue[block.timestamp / 7 days] += exactDolaIn;
        dbr.transfer(to, exactDbrOut);
        emit Buy(msg.sender, to, exactDolaIn, exactDbrOut);
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
     * @dev Re-approves the DOLA token to be spent by the DolaSavings contract.
     */
    function reapprove() external {
        asset.approve(address(savings), type(uint).max);
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

    event Buy(address indexed caller, address indexed to, uint exactDolaIn, uint exactDbrOut);
    event SetTargetK(uint newTargetK);
}
