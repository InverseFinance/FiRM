//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "src/interfaces/IMarket.sol";
import "src/interfaces/IPendleHelper.sol";
import {CurveHelper} from "src/util/CurveHelper.sol";
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
contract ALEV2 is
    ReentrancyGuard,
    CurveHelper,
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

    mapping(address => bool) public isExchangeProxy;

    IERC3156FlashLender public constant flash =
        IERC3156FlashLender(0x6C5Fdc0c53b122Ae0f15a863C349f3A481DE8f1F);

    bytes32 public constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    bytes32 public constant LEVERAGE = keccak256("LEVERAGE");
    bytes32 public constant DELEVERAGE = keccak256("DELEVERAGE");

    struct Market {
        IERC20 buySellToken;
        IERC20 collateral;
        IPendleHelper helper;
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

    constructor(
        address _pool,
        address _gov
    ) CurveHelper(_pool, _gov) {
        DOLA.approve(address(flash), type(uint).max);
    }

    /// @notice Allow an exchange proxy
    /// @param _proxy The proxy address
    function allowProxy(address _proxy) external onlyGov {
        if (_proxy == address(0)) revert InvalidProxyAddress();
        isExchangeProxy[_proxy] = true;
    }

    /// @notice Deny an exchange proxy
    /// @param _proxy The proxy address
    function denyProxy(address _proxy) external onlyGov {
        if (_proxy == address(0)) revert InvalidProxyAddress();
        isExchangeProxy[_proxy] = false;
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
    ) external onlyGov {
        if (!IDBR(address(DBR)).markets(_market)) revert NoMarket(_market);

        address collateral = IMarket(_market).collateral();
        if (_helper == address(0) && _buySellToken != collateral) {
            revert MarketSetupFailed(
                _market,
                _buySellToken,
                IMarket(_market).collateral(),
                _helper
            );
        }

        markets[_market].buySellToken = IERC20(_buySellToken);
        markets[_market].collateral = IERC20(collateral);
        markets[_market].buySellToken.approve(_market, type(uint256).max);
        
        if ( _buySellToken != collateral) {
            markets[_market].collateral.approve(_market, type(uint256).max);
        }
        
        if (_helper != address(0)) {
            markets[_market].helper = IPendleHelper(_helper);
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
    ) external onlyGov {
        if (address(markets[_market].buySellToken) == address(0))
            revert MarketNotSet(_market);
        if (_helper == address(0)) revert InvalidHelperAddress();

        address oldHelper = address(markets[_market].helper);
        markets[_market].buySellToken.approve(oldHelper, 0);
        markets[_market].collateral.approve(oldHelper, 0);

        markets[_market].helper = IPendleHelper(_helper);
        markets[_market].buySellToken.approve(_helper, type(uint256).max);
        markets[_market].collateral.approve(_helper, type(uint256).max);

        emit NewHelper(_market, _helper);
    }

    /// @notice Leverage user position by minting DOLA, buying collateral, deposting into the user escrow and borrow DOLA on behalf to repay the minted DOLA
    /// @dev Requires user to sign message to permit the contract to borrow DOLA on behalf
    /// @param value Amount of DOLA to flash mint/burn
    /// @param market The market contract
    /// @param exchangeProxy The exchange proxy contract if any
    /// @param swapCallData The `data` field from the API response.
    /// @param permit Permit data
    /// @param helperData Optional helper data in case the collateral needs to be transformed
    /// @param dbrData Optional data in case the user wants to buy DBR and also withdraw some DOLA
    function leveragePosition(
        uint256 value,
        address market,
        address exchangeProxy,
        bytes calldata swapCallData,
        Permit calldata permit,
        bytes calldata helperData,
        DBRHelper calldata dbrData
    ) public payable nonReentrant {
        if (address(markets[market].buySellToken) == address(0))
            revert MarketNotSet(market);

        bytes memory data = abi.encode(
            LEVERAGE,
            msg.sender,
            market,
            exchangeProxy,
            0, // unused
            swapCallData,
            permit,
            helperData,
            dbrData
        );

        flash.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(DOLA),
            value,
            data
        );
    }

    /// @notice Deposit collateral and instantly leverage user position by minting DOLA, buying collateral, deposting into the user escrow and borrow DOLA on behalf to repay the minted DOLA
    /// @dev Requires user to sign message to permit the contract to borrow DOLA on behalf
    /// @param initialDeposit Amount of collateral or underlying (in case of helper) to deposit
    /// @param value Amount of DOLA to borrow
    /// @param market The market address
    /// @param exchangeProxy The exchange proxy contract if any
    /// @param swapCallData The `data` field from the API response.
    /// @param permit Permit data
    /// @param helperData Optional helper data in case the collateral needs to be transformed
    /// @param dbrData Optional data in case the user wants to buy DBR and also withdraw some DOLA
    /// @param depositCollateral Whether the initialDeposit is the collateral or the underlying entry asset
    function depositAndLeveragePosition(
        uint256 initialDeposit,
        uint256 value,
        address market,
        address exchangeProxy,
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
            exchangeProxy,
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
    /// @param exchangeProxy The exchange proxy contract if any
    /// @param collateralAmount Collateral amount to withdraw from the escrow
    /// @param swapCallData The `data` field from the API response.
    /// @param permit Permit data
    /// @param helperData Optional helper data in case collateral needs to be transformed
    /// @param dbrData Optional data in case the user wants to sell DBR
    function deleveragePosition(
        uint256 value,
        address market,
        address exchangeProxy,
        uint256 collateralAmount,
        bytes calldata swapCallData,
        Permit calldata permit,
        bytes calldata helperData,
        DBRHelper calldata dbrData
    ) external payable nonReentrant {
        if (address(markets[market].buySellToken) == address(0))
            revert MarketNotSet(market);

        bytes memory data = abi.encode(
            DELEVERAGE,
            msg.sender,
            market,
            exchangeProxy,
            collateralAmount,
            swapCallData,
            permit,
            helperData,
            dbrData
        );

        flash.flashLoan(
            IERC3156FlashBorrower(address(this)),
            address(DOLA),
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
                address,
                uint256,
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
            address _proxy,
            ,
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
                    address,
                    uint256,
                    bytes,
                    Permit,
                    bytes,
                    DBRHelper
                )
            );
        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        if (markets[_market].useProxy) {
            if(!isExchangeProxy[_proxy]) revert InvalidProxyAddress();
            DOLA.approve(_proxy, _value);
            (bool success, ) = payable(_proxy).call{value: msg.value}(
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
                _user,
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

        if (_dbrData.dola != 0) DOLA.transfer(_user, _dbrData.dola);

        if (_dbrData.amountIn > 0 && _dbrData.minOut > 0)
            _buyDbr(_dbrData.amountIn, _dbrData.minOut, _user);

        _refundExcess(_user, _value);

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
            address _proxy,
            uint256 _collateralAmount,
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
                    address,
                    uint256,
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
                _user,
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
            if(!isExchangeProxy[_proxy]) revert InvalidProxyAddress();
            // Approve sellToken for exchangeProxy
            sellToken.approve(_proxy, 0);
            sellToken.approve(_proxy, _collateralAmount);
            (bool success, ) = payable(_proxy).call{value: msg.value}(
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
        } else if (address(sellToken) != address(DOLA)) {
            uint256 sellTokenBal = sellToken.balanceOf(address(this));
            // Send any leftover sellToken to the sender
            if (sellTokenBal != 0) sellToken.safeTransfer(_user, sellTokenBal);
        }

        if (_dbrData.amountIn > 0 && _dbrData.minOut > 0) {
            DBR.transferFrom(_user, address(this), _dbrData.amountIn);
            _sellDbr(_dbrData.amountIn, _dbrData.minOut, _user);
        }

        _refundExcess(_user, _value);

        emit LeverageDown(
            _market,
            _user,
            _value,
            _collateralAmount,
            _dbrData.dola,
            _dbrData.amountIn
        );
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
        uint256 dolaToBorrow = _value + _dbrData.dola + _dbrData.amountIn;
        // We borrow the amount of DOLA we minted before plus the amount for buying DBR if any
        market.borrowOnBehalf(
            _user,
            dolaToBorrow,
            _permit.deadline,
            _permit.v,
            _permit.r,
            _permit.s
        );

        if (DOLA.balanceOf(address(this)) < dolaToBorrow)
            revert DOLAInvalidBorrow(
                dolaToBorrow,
                DOLA.balanceOf(address(this))
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
            DOLA.transferFrom(_user, address(this), _dbrData.dola);
            _value += _dbrData.dola;
        }
        DOLA.approve(address(market), _value);
        market.repay(_user, _value);

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
    /// @param _user The user address
    /// @param _collateralAmount Collateral amount to convert
    /// @param _market The market contract
    /// @param sellToken The sell token (the underlying asset)
    /// @param _helperData Optional helper data
    /// @return assetAmount The amount of sellToken/underlying after the conversion
    function _convertToAsset(
        address _user,
        uint256 _collateralAmount,
        address _market,
        IERC20 sellToken,
        bytes memory _helperData
    ) internal returns (uint256) {
        // Collateral amount is now converted into sellToken
        uint256 assetAmount = markets[_market].helper.convertFromCollateral(
            _user,
            _collateralAmount,
            _helperData
        );
        uint256 actualAssetAmount = sellToken.balanceOf(address(this));

        if (actualAssetAmount < assetAmount)
            revert WithdrawFailed(assetAmount, actualAssetAmount);

        return actualAssetAmount;
    }

    /// @notice convert the underlying asset amount into the collateral
    /// @param _user The user address
    /// @param _assetAmount The amount of sellToken/underlying to convert
    /// @param _market The market contract
    /// @param _helperData Optional helper data
    /// @return collateralAmount The amount of collateral after the conversion
    function _convertToCollateral(
        address _user,
        uint256 _assetAmount,
        address _market,
        bytes memory _helperData
    ) internal returns (uint256) {
        // Collateral amount is now converted
        uint256 collateralAmount = markets[_market].helper.convertToCollateral(
            _user,
            _assetAmount,
            _helperData
        );

        uint256 actualCollateralAmount = markets[_market].collateral.balanceOf(
            address(this)
        );
        if (actualCollateralAmount < collateralAmount)
            revert DepositFailed(collateralAmount, actualCollateralAmount);

        return actualCollateralAmount;
    }

    /// @notice Send any extra DOLA and ETH to the user
    /// @param _user The user address
    /// @param _value The amount of flash borrowed DOLA to be repaid
    function _refundExcess(address _user, uint256 _value) internal {
        uint256 balance = DOLA.balanceOf(address(this));
        if (balance < _value) revert DOLAInvalidRepay(_value, balance);
        // Send any extra DOLA to the sender
        if (balance > _value) DOLA.transfer(_user, balance - _value);
        // Refund any unspent protocol fees to the sender.
        if (address(this).balance > 0)
            payable(_user).transfer(address(this).balance);
    }
}
