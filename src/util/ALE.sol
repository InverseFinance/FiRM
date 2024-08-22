//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "src/interfaces/IMarket.sol";
import "src/interfaces/ITransformHelper.sol";
import {CurveDBRHelper} from "src/util/CurveDBRHelper.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface IDBR {
    function markets(address) external view returns (bool);
}

interface IERC3156FlashBorrower {
    /**
     * @dev Receive a flash loan.
     * @param initiator The initiator of the loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param fee The additional amount of tokens to repay.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     * @return The keccak256 hash of "ERC3156FlashBorrower.onFlashLoan"
     */
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32);
}

interface IERC3156FlashLender {
    /**
     * @dev Initiate a flash loan.
     * @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
     * @param token The loan currency.
     * @param value The amount of tokens lent.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 value,
        bytes calldata data
    ) external returns (bool);
}

// Accelerated leverage engine
contract ALE is
    Ownable,
    ReentrancyGuard,
    CurveDBRHelper,
    IERC3156FlashBorrower
{
    using SafeERC20 for IERC20;
    error CollateralNotSet();
    error MarketNotSet(address market);
    error SwapFailed();
    error DOLAInvalidBorrow(uint256 expected, uint256 actual);
    error DOLAInvalidRepay(uint256 expected, uint256 actual);
    error InvalidProxyAddress();
    error InvalidHelperAddress();
    error InvalidAction(bytes32 action);
    error NotFlashMinter(address caller);
    error NotALE(address caller);
    error NothingToDeposit();
    error DepositFailed(uint256 expected, uint256 actual);
    error WithdrawFailed(uint256 expected, uint256 actual);
    error TotalSupplyChanged(uint256 expected, uint256 actual);
    error CollateralIsZero();
    error NoMarket(address market);
    error MarketSetupFailed(
        address market,
        address buySellToken,
        address collateral,
        address helper
    );

    // 1Inch ExchangeProxy address.
    address payable public exchangeProxy;

    IDBR public constant DBR = IDBR(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);

    IERC3156FlashLender public constant flash =
        IERC3156FlashLender(0x6112818d0c0d75448551b76EC80F14de10F4E054);

    bytes32 public constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    bytes32 public constant LEVERAGE = keccak256("LEVERAGE");
    bytes32 public constant DELEVERAGE = keccak256("DELEVERAGE");

    struct Market {
        IERC20 buySellToken;
        IERC20 collateral;
        ITransformHelper helper;
        bool useProxy;
    }

    struct Permit {
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct DBRHelper {
        uint256 amountIn; // DOLA or DBR
        uint256 minOut; // DOLA or DBR
        uint256 dola; // DOLA to extra borrow or extra repay
    }

    event LeverageUp(
        address indexed market,
        address indexed account,
        uint256 dolaFlashMinted, // DOLA flash minted for buying collateral only
        uint256 collateralDeposited, // amount of collateral deposited into the escrow
        uint256 dolaBorrowed, // amount of DOLA borrowed on behalf of the user
        uint256 dolaForDBR // amount of DOLA used for buying DBR
    );

    event LeverageDown(
        address indexed market,
        address indexed account,
        uint256 dolaFlashMinted, // Flash minted DOLA for repaying leverage only
        uint256 collateralSold, // amount of collateral/underlying sold
        uint256 dolaUserRepaid, // amount of DOLA deposited by the user as part of the repay
        uint256 dbrSoldForDola // amount of DBR sold for DOLA
    );

    event Deposit(
        address indexed market,
        address indexed account,
        address indexed token, // token used for initial deposit (could be collateral or buySellToken)
        uint256 depositAmount
    );

    event NewMarket(
        address indexed market,
        address indexed buySellToken,
        address collateral,
        address indexed helper
    );

    event NewHelper(address indexed market, address indexed helper);

    // Mapping of market to Market structs
    // NOTE: in normal cases sellToken/buyToken is the collateral token,
    // in other cases it could be different (eg. st-yCRV is collateral, yCRV is the token to be swapped from/to DOLA)
    // or with DOLA curve LPs, LP token is the collateral and DOLA is the token to be swapped from/to
    mapping(address => Market) public markets;

    modifier dolaSupplyUnchanged() {
        uint256 totalSupply = dola.totalSupply();
        _;
        if (totalSupply != dola.totalSupply())
            revert TotalSupplyChanged(totalSupply, dola.totalSupply());
    }

    constructor(
        address _exchangeProxy,
        address _pool
    ) Ownable(msg.sender) CurveDBRHelper(_pool) {
        exchangeProxy = payable(address(_exchangeProxy));
        _approveDola(address(flash), type(uint).max);
    }

    function setExchangeProxy(address _exchangeProxy) external onlyOwner {
        if (_exchangeProxy == address(0)) revert InvalidProxyAddress();
        exchangeProxy = payable(_exchangeProxy);
    }

    /// @notice Set the market for a collateral token
    /// @param _buySellToken The token which will be bought/sold (usually the collateral token), probably underlying if there's a helper
    /// @param _market The market contract
    /// @param _helper Optional helper contract to transform collateral to buySelltoken and viceversa
    /// @param useProxy Whether to use the Exchange Proxy or not
    function setMarket(
        address _market,
        address _buySellToken,
        address _helper,
        bool useProxy
    ) external onlyOwner {
        if (!DBR.markets(_market)) revert NoMarket(_market);

        if (_helper == address(0)) {
            if (_buySellToken != IMarket(_market).collateral()) {
                revert MarketSetupFailed(
                    _market,
                    _buySellToken,
                    IMarket(_market).collateral(),
                    _helper
                );
            }
        }

        address collateral = IMarket(_market).collateral();
        markets[_market].buySellToken = IERC20(_buySellToken);
        markets[_market].collateral = IERC20(collateral);
        markets[_market].buySellToken.approve(_market, type(uint256).max);

        if (_buySellToken != collateral) {
            markets[_market].collateral.approve(_market, type(uint256).max);
        }

        if (_helper != address(0)) {
            markets[_market].helper = ITransformHelper(_helper);

            markets[_market].buySellToken.approve(_helper, type(uint256).max);
            markets[_market].collateral.approve(_helper, type(uint256).max);
        }

        markets[_market].useProxy = useProxy;
        emit NewMarket(_market, _buySellToken, collateral, _helper);
    }

    /// @notice Update the helper contract
    /// @param _market The market we want to update the helper contract for
    /// @param _helper The helper contract
    function updateMarketHelper(
        address _market,
        address _helper
    ) external onlyOwner {
        if (address(markets[_market].buySellToken) == address(0))
            revert MarketNotSet(_market);

        address oldHelper = address(markets[_market].helper);
        if (oldHelper != address(0)) {
            markets[_market].buySellToken.approve(oldHelper, 0);
            markets[_market].collateral.approve(oldHelper, 0);
        }

        markets[_market].helper = ITransformHelper(_helper);

        if (_helper != address(0)) {
            markets[_market].buySellToken.approve(_helper, type(uint256).max);
            markets[_market].collateral.approve(_helper, type(uint256).max);
        }

        emit NewHelper(_market, _helper);
    }

    /// @notice Leverage user position by minting DOLA, buying collateral, deposting into the user escrow and borrow DOLA on behalf to repay the minted DOLA
    /// @dev Requires user to sign message to permit the contract to borrow DOLA on behalf
    /// @param value Amount of DOLA to flash mint/burn
    /// @param market The market contract
    /// @param spender The `allowanceTarget` field from the API response.
    /// @param swapCallData The `data` field from the API response.
    /// @param permit Permit data
    /// @param helperData Optional helper data in case the collateral needs to be transformed
    /// @param dbrData Optional data in case the user wants to buy DBR and also withdraw some DOLA
    function leveragePosition(
        uint256 value,
        address market,
        address spender,
        bytes calldata swapCallData,
        Permit calldata permit,
        bytes calldata helperData,
        DBRHelper calldata dbrData
    ) public payable nonReentrant dolaSupplyUnchanged {
        if (address(markets[market].buySellToken) == address(0))
            revert MarketNotSet(market);

        bytes memory data = abi.encode(
            LEVERAGE,
            msg.sender,
            market,
            0, // unused
            spender,
            swapCallData,
            permit,
            helperData,
            dbrData
        );

        flash.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(dola),
            value,
            data
        );
    }

    /// @notice Deposit collateral and instantly leverage user position by minting DOLA, buying collateral, deposting into the user escrow and borrow DOLA on behalf to repay the minted DOLA
    /// @dev Requires user to sign message to permit the contract to borrow DOLA on behalf
    /// @param initialDeposit Amount of collateral or underlying (in case of helper) to deposit
    /// @param value Amount of DOLA to borrow
    /// @param market The market address
    /// @param spender The `allowanceTarget` field from the API response.
    /// @param swapCallData The `data` field from the API response.
    /// @param permit Permit data
    /// @param helperData Optional helper data in case the collateral needs to be transformed
    /// @param dbrData Optional data in case the user wants to buy DBR and also withdraw some DOLA
    /// @param depositCollateral Whether the initialDeposit is the collateral or the underlying entry asset
    function depositAndLeveragePosition(
        uint256 initialDeposit,
        uint256 value,
        address market,
        address spender,
        bytes calldata swapCallData,
        Permit calldata permit,
        bytes calldata helperData,
        DBRHelper calldata dbrData,
        bool depositCollateral
    ) external payable {
        if (initialDeposit == 0) revert NothingToDeposit();

        IERC20 depositToken;

        if (depositCollateral) {
            depositToken = markets[market].collateral;
        } else {
            depositToken = markets[market].buySellToken;
        }

        depositToken.safeTransferFrom(
            msg.sender,
            address(this),
            initialDeposit
        );
        emit Deposit(market, msg.sender, address(depositToken), initialDeposit);

        leveragePosition(
            value,
            market,
            spender,
            swapCallData,
            permit,
            helperData,
            dbrData
        );
    }

    /// @notice Repay a DOLA loan and withdraw collateral from the escrow
    /// @dev Requires user to sign message to permit the contract to withdraw collateral from the escrow
    /// @param value Amount of DOLA to repay
    /// @param market The market contract
    /// @param collateralAmount Collateral amount to withdraw from the escrow
    /// @param spender The `allowanceTarget` field from the API response.
    /// @param swapCallData The `data` field from the API response.
    /// @param permit Permit data
    /// @param helperData Optional helper data in case collateral needs to be transformed
    /// @param dbrData Optional data in case the user wants to sell DBR
    function deleveragePosition(
        uint256 value,
        address market,
        uint256 collateralAmount,
        address spender,
        bytes calldata swapCallData,
        Permit calldata permit,
        bytes calldata helperData,
        DBRHelper calldata dbrData
    ) external payable nonReentrant dolaSupplyUnchanged {
        if (address(markets[market].buySellToken) == address(0))
            revert MarketNotSet(market);

        bytes memory data = abi.encode(
            DELEVERAGE,
            msg.sender,
            market,
            collateralAmount,
            spender,
            swapCallData,
            permit,
            helperData,
            dbrData
        );

        flash.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(dola),
            value,
            data
        );
    }

    function onFlashLoan(
        address initiator,
        address,
        uint256 amount,
        uint256,
        bytes calldata data
    ) external returns (bytes32) {
        if (initiator != address(this)) revert NotALE(initiator);
        if (msg.sender != address(flash)) revert NotFlashMinter(msg.sender);

        (bytes32 ACTION, , , , , , , , ) = abi.decode(
            data,
            (
                bytes32,
                address,
                address,
                uint256,
                address,
                bytes,
                Permit,
                bytes,
                DBRHelper
            )
        );

        if (ACTION == LEVERAGE) _onFlashLoanLeverage(amount, data);
        else if (ACTION == DELEVERAGE) _onFlashLoanDeleverage(amount, data);
        else revert InvalidAction(bytes32(ACTION));

        return CALLBACK_SUCCESS;
    }

    function _onFlashLoanLeverage(uint256 _value, bytes memory data) internal {
        (
            ,
            address _user,
            address _market,
            ,
            address _spender,
            bytes memory _swapCallData,
            Permit memory _permit,
            bytes memory _helperData,
            DBRHelper memory _dbrData
        ) = abi.decode(
                data,
                (
                    bytes32,
                    address,
                    address,
                    uint256,
                    address,
                    bytes,
                    Permit,
                    bytes,
                    DBRHelper
                )
            );
        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        if (markets[_market].useProxy) {
            _approveDola(_spender, _value);
            (bool success, ) = exchangeProxy.call{value: msg.value}(
                _swapCallData
            );
            if (!success) revert SwapFailed();
        }

        // Actual collateral/buyToken bought
        uint256 collateralAmount = markets[_market].buySellToken.balanceOf(
            address(this)
        );
        if (collateralAmount == 0) revert CollateralIsZero();

        // If there's a helper contract, the buyToken has to be transformed
        if (address(markets[_market].helper) != address(0)) {
            collateralAmount = _convertToCollateral(
                collateralAmount,
                _market,
                _helperData
            );
        }

        // Deposit and borrow on behalf
        IMarket(_market).deposit(
            _user,
            markets[_market].collateral.balanceOf(address(this))
        );

        _borrowDola(_user, _value, _permit, _dbrData, IMarket(_market));

        if (_dbrData.dola != 0) dola.transfer(_user, _dbrData.dola);

        if (_dbrData.amountIn != 0)
            _buyDbr(_dbrData.amountIn, _dbrData.minOut, _user);
        // Scope to avoid stack too deep error
        {
            uint256 balance = dola.balanceOf(address(this));

            if (balance > _value) dola.transfer(_user, balance - _value);
        }

        // Refund any possible unspent fees to the sender.
        if (address(this).balance > 0)
            payable(_user).transfer(address(this).balance);

        emit LeverageUp(
            _market,
            _user,
            _value,
            collateralAmount,
            _dbrData.dola,
            _dbrData.amountIn
        );
    }

    function _onFlashLoanDeleverage(
        uint256 _value,
        bytes memory data
    ) internal {
        (
            ,
            address _user,
            address _market,
            uint256 _collateralAmount,
            address _spender,
            bytes memory _swapCallData,
            Permit memory _permit,
            bytes memory _helperData,
            DBRHelper memory _dbrData
        ) = abi.decode(
                data,
                (
                    bytes32,
                    address,
                    address,
                    uint256,
                    address,
                    bytes,
                    Permit,
                    bytes,
                    DBRHelper
                )
            );

        _repayAndWithdraw(
            _user,
            _value,
            _collateralAmount,
            _permit,
            _dbrData,
            IMarket(_market)
        );

        IERC20 sellToken = markets[_market].buySellToken;

        // If there's a helper contract, the collateral has to be transformed
        if (address(markets[_market].helper) != address(0)) {
            _collateralAmount = _convertToAsset(
                _collateralAmount,
                _market,
                sellToken,
                _helperData
            );
            // Reimburse leftover collateral from conversion if any
            uint256 collateralLeft = markets[_market].collateral.balanceOf(
                address(this)
            );

            if (collateralLeft != 0) {
                markets[_market].collateral.safeTransfer(_user, collateralLeft);
            }
        }

        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        // NOTE: This will swap the collateral or helperCollateral for DOLA
        if (markets[_market].useProxy) {
            // Approve sellToken for spender
            sellToken.approve(_spender, 0);
            sellToken.approve(_spender, _collateralAmount);
            (bool success, ) = exchangeProxy.call{value: msg.value}(
                _swapCallData
            );
            if (!success) revert SwapFailed();
        }

        if (address(markets[_market].helper) == address(0)) {
            uint256 collateralAvailable = markets[_market].collateral.balanceOf(
                address(this)
            );

            if (collateralAvailable != 0) {
                markets[_market].collateral.safeTransfer(
                    _user,
                    collateralAvailable
                );
            }
        } else if (address(sellToken) != address(dola)) {
            uint256 sellTokenBal = sellToken.balanceOf(address(this));
            // Send any leftover sellToken to the sender
            if (sellTokenBal != 0) sellToken.safeTransfer(_user, sellTokenBal);
        }

        // Scope to avoid stack too deep error
        {
            uint256 balance = dola.balanceOf(address(this));
            if (balance < _value) revert DOLAInvalidRepay(_value, balance);
            // Send any extra DOLA to the sender (in case the collateral withdrawn and swapped exceeds the value to burn)
            if (balance > _value) dola.transfer(_user, balance - _value);
        }

        if (_dbrData.amountIn != 0) {
            dbr.transferFrom(_user, address(this), _dbrData.amountIn);
            _sellDbr(_dbrData.amountIn, _dbrData.minOut, _user);
        }

        // Refund any unspent protocol fees to the sender.
        if (address(this).balance > 0)
            payable(_user).transfer(address(this).balance);

        emit LeverageDown(
            _market,
            _user,
            _value,
            _collateralAmount,
            _dbrData.dola,
            _dbrData.amountIn
        );
    }

    /// @notice Mint DOLA to this contract and approve the spender
    /// @param spender The spender address
    /// @param _value Amount of DOLA to mint and approve
    function _approveDola(address spender, uint256 _value) internal {
        dola.approve(spender, _value);
    }

    /// @notice Borrow DOLA on behalf of the user
    /// @param _value Amount of DOLA to borrow
    /// @param _permit Permit data
    /// @param _dbrData DBR data
    /// @param market The market contract
    function _borrowDola(
        address _user,
        uint256 _value,
        Permit memory _permit,
        DBRHelper memory _dbrData,
        IMarket market
    ) internal {
        uint256 dolaToBorrow = _value;

        if (_dbrData.dola != 0) {
            dolaToBorrow += _dbrData.dola;
        }

        if (_dbrData.amountIn != 0) {
            dolaToBorrow += _dbrData.amountIn;
        }
        // We borrow the amount of DOLA we minted before plus the amount for buying DBR if any
        market.borrowOnBehalf(
            _user,
            dolaToBorrow,
            _permit.deadline,
            _permit.v,
            _permit.r,
            _permit.s
        );

        if (dola.balanceOf(address(this)) < dolaToBorrow)
            revert DOLAInvalidBorrow(
                dolaToBorrow,
                dola.balanceOf(address(this))
            );
    }

    /// @notice Repay DOLA loan and withdraw collateral from the escrow
    /// @param _value Amount of DOLA to repay
    /// @param _collateralAmount Collateral amount to withdraw from the escrow
    /// @param _permit Permit data
    /// @param _dbrData DBR data
    /// @param market The market contract
    function _repayAndWithdraw(
        address _user,
        uint256 _value,
        uint256 _collateralAmount,
        Permit memory _permit,
        DBRHelper memory _dbrData,
        IMarket market
    ) internal {
        if (_dbrData.dola != 0) {
            dola.transferFrom(_user, address(this), _dbrData.dola);
            _approveDola(address(market), _value + _dbrData.dola);
            market.repay(_user, _value + _dbrData.dola);
        } else {
            _approveDola(address(market), _value);
            market.repay(_user, _value);
        }

        // withdraw amount from ZERO EX quote
        market.withdrawOnBehalf(
            _user,
            _collateralAmount,
            _permit.deadline,
            _permit.v,
            _permit.r,
            _permit.s
        );
    }

    /// @notice convert a collateral amount into the underlying asset
    /// @param _collateralAmount Collateral amount to convert
    /// @param _market The market contract
    /// @param sellToken The sell token (the underlying asset)
    /// @param _helperData Optional helper data
    /// @return assetAmount The amount of sellToken/underlying after the conversion
    function _convertToAsset(
        uint256 _collateralAmount,
        address _market,
        IERC20 sellToken,
        bytes memory _helperData
    ) internal returns (uint256) {
        // Collateral amount is now transformed into sellToken
        uint256 assetAmount = markets[_market].helper.transformFromCollateral(
            _collateralAmount,
            _helperData
        );
        uint256 actualAssetAmount = sellToken.balanceOf(address(this));

        if (actualAssetAmount < assetAmount)
            revert WithdrawFailed(assetAmount, actualAssetAmount);

        return actualAssetAmount;
    }

    /// @notice convert the underlying asset amount into the collateral
    /// @param _assetAmount The amount of sellToken/underlying to convert
    /// @param _market The market contract
    /// @param _helperData Optional helper data
    /// @return collateralAmount The amount of collateral after the conversion
    function _convertToCollateral(
        uint256 _assetAmount,
        address _market,
        bytes memory _helperData
    ) internal returns (uint256) {
        // Collateral amount is now transformed
        uint256 collateralAmount = markets[_market]
            .helper
            .transformToCollateral(_assetAmount, _helperData);

        uint256 actualCollateralAmount = markets[_market].collateral.balanceOf(
            address(this)
        );
        if (actualCollateralAmount < collateralAmount)
            revert DepositFailed(collateralAmount, actualCollateralAmount);

        return actualCollateralAmount;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
