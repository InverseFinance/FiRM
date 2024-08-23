//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "./interfaces/IERC3156FlashBorrower.sol";
import "./interfaces/IERC3156FlashLender.sol";
import "./utils/Ownable.sol";
import "./utils/Address.sol";
import "./ERC20/IERC20.sol";
import "./ERC20/SafeERC20.sol";

/**
 * @title Dola Flash Minter
 * @notice Allow users to mint an arbitrary amount of DOLA without collateral
 *         as long as this amount is repaid within a single transaction.
 * @dev This contract is abstract, any concrete implementation must have the DOLA
 *      token address hardcoded in the contract to facilitate code auditing.
 */
abstract contract DolaFlashMinter is Ownable, IERC3156FlashLender {
    using SafeERC20 for IERC20;
    using Address for address;
    using Address for address payable;
    event FlashLoan(address receiver, address token, uint256 value);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event MaxFlashLimitUpdated(uint256 oldLimit, uint256 newLimit);

    IERC20 public immutable dola;
    uint256 public constant fee = 0;
    address public treasury;
    uint256 public flashMinted;
    uint256 public maxFlashLimit;

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(address _dola, address _treasury) {
        require(_dola.isContract(), "FLASH_MINTER:INVALID_DOLA");
        require(_treasury != address(0), "FLASH_MINTER:INVALID_TREASURY");
        dola = IERC20(_dola);
        treasury = _treasury;
    }

    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 value,
        bytes calldata data
    ) external override returns (bool) {
        require(token == address(dola), "FLASH_MINTER:NOT_DOLA");
        require(value <= maxFlashLimit, "FLASH_MINTER:INDIVIDUAL_LIMIT_BREACHED");
        flashMinted = flashMinted + value;
        require(flashMinted <= maxFlashLimit, "total loan limit exceeded");

        // Step 1: Mint Dola to receiver
        dola.mint(address(receiver), value);
        emit FlashLoan(address(receiver), token, value);

        // Step 2: Make flashloan callback
        require(
            receiver.onFlashLoan(msg.sender, token, value, fee, data) == CALLBACK_SUCCESS,
            "FLASH_MINTER:CALLBACK_FAILURE"
        );
        // Step 3: Retrieve minted Dola from receiver
        dola.safeTransferFrom(address(receiver), address(this), value);

        // Step 4: Burn minted Dola (and leave accrued fees in contract)
        dola.burn(value);

        flashMinted = flashMinted - value;
        return true;
    }

    // Collect fees and retrieve any tokens sent to this contract by mistake
    function collect(address _token) external {
        if (_token == address(0)) {
            payable(treasury).sendValue(address(this).balance);
        } else {
            uint256 balance = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(treasury, balance);
        }
    }

    function setTreasury(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0), "FLASH_MINTER:INVALID_TREASURY");
        emit TreasuryUpdated(treasury, _newTreasury);
        treasury = _newTreasury;
    }

    function setMaxFlashLimit(uint256 _newLimit) external onlyOwner {
        emit MaxFlashLimitUpdated(maxFlashLimit, _newLimit);
        maxFlashLimit = _newLimit;
    }

    function maxFlashLoan(address _token) external view override returns (uint256) {
        return _token == address(dola) ? maxFlashLimit - flashMinted : 0;
    }

    function flashFee(address _token, uint256) public view override returns (uint256) {
        require(_token == address(dola), "FLASH_MINTER:NOT_DOLA");
        return fee;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
