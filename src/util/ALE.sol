//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "src/interfaces/IMarket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/ITransformHelper.sol";
import "src/util/CurveDBRHelper.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";

// Accelerated leverage engine
contract ALE is Ownable, ReentrancyGuard, CurveDBRHelper {
    error CollateralNotSet();
    error MarketNotSetForCollateral(address collateral);
    error SwapFailed();
    error DOLAInvalidBorrow();
    error DOLAInvalidRepay();
    error InvalidProxyAddress();
    error InvalidHelperAddress();
    error NothingToDeposit();
    error DepositFailed();
    error WithdrawFailed();

    // 0x ExchangeProxy address.
    // See https://docs.0x.org/developer-resources/contract-addresses
    address payable public exchangeProxy;

    struct Market {
        IMarket market;
        ITransformHelper helper;
        IERC20 collateral;
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
    }

    // Mapping of sellToken/buyToken to Market structs
    // NOTE: in normal cases sellToken/buyToken is the collateral token,
    // in other cases it could be different (eg. st-yCRV is collateral, yCRV is the token to be swapped from/to DOLA)
    mapping(address => Market) public markets;

    constructor(
        address _exchangeProxy,
        address _pool
    ) Ownable(msg.sender) CurveDBRHelper(_pool) {
        exchangeProxy = payable(address(_exchangeProxy));
    }

    function setExchangeProxy(address _exchangeProxy) external onlyOwner {
        if (_exchangeProxy == address(0)) revert InvalidProxyAddress();
        exchangeProxy = payable(_exchangeProxy);
    }

    /// @notice Set the market for a collateral token
    /// @param _buySelltoken The token which will be bought/sold (usually the collateral token), probably underlying if there's an helper
    /// @param _market The market contract
    /// @param _collateral The collateral token
    /// @param _helper Optional helper contract to transform collateral to buySelltoken and viceversa
    function setMarket(
        address _buySelltoken,
        IMarket _market,
        address _collateral,
        address _helper
    ) external onlyOwner {
        markets[_buySelltoken].market = _market;
        markets[_buySelltoken].collateral = IERC20(_collateral);
        IERC20(_buySelltoken).approve(address(_market), type(uint256).max);

        if (_buySelltoken != _collateral) {
            IERC20(_collateral).approve(address(_market), type(uint256).max);
        }

        if (_helper != address(0)) {
            markets[_buySelltoken].helper = ITransformHelper(_helper);
            IERC20(_buySelltoken).approve(_helper, type(uint256).max);
            IERC20(_collateral).approve(_helper, type(uint256).max);
        }
    }

    /// @notice Update the helper contract
    /// @param _helper The helper contract
    /// @param _buySelltoken The token used as key in the markets mapping probably the underlying since there's an helper
    function updateMarketHelper(
        address _helper,
        address _buySelltoken
    ) external onlyOwner {
        if (_helper == address(0)) revert InvalidHelperAddress();
        markets[_buySelltoken].helper = ITransformHelper(_helper);
        IERC20(_buySelltoken).approve(_helper, type(uint256).max);
    }

    /// @notice Leverage user position by minting DOLA, buying collateral, deposting into the user escrow and borrow DOLA on behalf to repay the minted DOLA
    /// @dev Requires user to sign message to permit the contract to borrow DOLA on behalf
    /// @param _value Amount of DOLA to borrow
    /// @param _buyTokenAddress The `buyTokenAddress` field from the API response.
    /// @param _spender The `allowanceTarget` field from the API response.
    /// @param _swapCallData The `data` field from the API response.
    /// @param _permit Permit data
    /// @param _helperData Optional helper data in case the collateral needs to be transformed
    function leveragePosition(
        uint256 _value,
        address _buyTokenAddress,
        address _spender,
        bytes calldata _swapCallData,
        Permit calldata _permit,
        bytes calldata _helperData,
        DBRHelper calldata _dbrData
    ) external payable nonReentrant {
        _leveragePosition(
            _value,
            _buyTokenAddress,
            _spender,
            _swapCallData,
            _permit,
            _helperData,
            _dbrData
        );
    }

    /// @notice Deposit collateral and instantly leverage user position by minting DOLA, buying collateral, deposting into the user escrow and borrow DOLA on behalf to repay the minted DOLA
    /// @dev Requires user to sign message to permit the contract to borrow DOLA on behalf
    /// @param _initialDeposit Amount of collateral or underlying (in case of helper) to deposit
    /// @param _value Amount of DOLA to borrow
    /// @param _buyTokenAddress The `buyTokenAddress` field from the API response.
    /// @param _spender The `allowanceTarget` field from the API response.
    /// @param _swapCallData The `data` field from the API response.
    /// @param _permit Permit data
    /// @param _helperData Optional helper data in case the collateral needs to be transformed
    function depositAndLeveragePosition(
        uint256 _initialDeposit,
        uint256 _value,
        address _buyTokenAddress,
        address _spender,
        bytes calldata _swapCallData,
        Permit calldata _permit,
        bytes calldata _helperData,
        DBRHelper calldata _dbrData
    ) external payable nonReentrant {
        if (_initialDeposit == 0) revert NothingToDeposit();
        IERC20 buyToken = IERC20(_buyTokenAddress);
        buyToken.transferFrom(msg.sender, address(this), _initialDeposit);
        _leveragePosition(
            _value,
            _buyTokenAddress,
            _spender,
            _swapCallData,
            _permit,
            _helperData,
            _dbrData
        );
    }

    /// @notice Repay a DOLA loan and withdraw collateral from the escrow
    /// @dev Requires user to sign message to permit the contract to withdraw collateral from the escrow
    /// @param _value Amount of DOLA to repay
    /// @param _sellTokenAddress The `sellTokenAddress` field from the API response.
    /// @param _collateralAmount Collateral amount to withdraw from the escrow
    /// @param _spender The `allowanceTarget` field from the API response.
    /// @param _swapCallData The `data` field from the API response.
    /// @param _permit Permit data
    /// @param _helperData Optional helper data in case collateral needs to be transformed
    function deleveragePosition(
        uint256 _value,
        address _sellTokenAddress,
        uint256 _collateralAmount,
        address _spender,
        bytes calldata _swapCallData,
        Permit calldata _permit,
        bytes calldata _helperData,
        DBRHelper calldata _dbrData
    ) external payable nonReentrant {
        if (address(markets[_sellTokenAddress].market) == address(0))
            revert MarketNotSetForCollateral(_sellTokenAddress);

        IMarket market = markets[_sellTokenAddress].market;

        dola.mint(address(this), _value);
        dola.approve(address(market), _value);

        market.repay(msg.sender, _value);

        // withdraw amount from ZERO EX quote
        market.withdrawOnBehalf(
            msg.sender,
            _collateralAmount,
            _permit.deadline,
            _permit.v,
            _permit.r,
            _permit.s
        );

        // If there's an helper contract, the collateral has to be transformed
        if (address(markets[_sellTokenAddress].helper) != address(0)) {
            uint256 estimateAmount = markets[_sellTokenAddress]
                .helper
                .collateralToAsset(_collateralAmount);

            // Collateral amount is now transformed into sellToken
            _collateralAmount = markets[_sellTokenAddress]
                .helper
                .transformFromCollateral(_collateralAmount, _helperData);

            if (
                _collateralAmount + 1 < estimateAmount &&
                IERC20(_sellTokenAddress).balanceOf(address(this)) <
                _collateralAmount
            ) revert WithdrawFailed();
        }

        // Approve sellToken for spender
        IERC20(_sellTokenAddress).approve(_spender, 0);
        IERC20(_sellTokenAddress).approve(_spender, _collateralAmount);

        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        // NOTE: This will swap the collateral or helperCollateral for DOLA
        (bool success, ) = exchangeProxy.call{value: msg.value}(_swapCallData);
        if (!success) revert SwapFailed();

        uint256 collateralAvailable = markets[_sellTokenAddress]
            .collateral
            .balanceOf(address(this));
        if (collateralAvailable != 0) {
            markets[_sellTokenAddress].collateral.transfer(
                msg.sender,
                collateralAvailable
            );
        }

        uint256 sellTokenBal = IERC20(_sellTokenAddress).balanceOf(address(this));
        // Send any leftover sellToken to the sender
        if (sellTokenBal != 0 ) {
            IERC20(_sellTokenAddress).transfer(
                msg.sender,
                sellTokenBal
            );
        }

        if (dola.balanceOf(address(this)) < _value) revert DOLAInvalidRepay();

        dola.burn(_value);

        // Send any DOLA leftover to the sender after burning (in case the collateral withdrawn and swapped exceeds the value to burn)
        dola.transfer(msg.sender, dola.balanceOf(address(this)));

        if (_dbrData.amountIn != 0) {
            dbr.transferFrom(msg.sender, address(this), _dbrData.amountIn);
            _sellDbr(_dbrData.amountIn, _dbrData.minOut, msg.sender);
        }

        // Refund any unspent protocol fees to the sender.
        if (address(this).balance > 0)
            payable(msg.sender).transfer(address(this).balance);
    }

    function _leveragePosition(
        uint256 _value,
        address _buyTokenAddress,
        address _spender,
        bytes calldata _swapCallData,
        Permit calldata _permit,
        bytes calldata _helperData,
        DBRHelper calldata _dbrData
    ) internal {
        if (address(markets[_buyTokenAddress].market) == address(0))
            revert MarketNotSetForCollateral(_buyTokenAddress);

        IMarket market = markets[_buyTokenAddress].market;

        // Mint and approve
        dola.mint(address(this), _value);
        dola.approve(_spender, _value);

        IERC20 buyToken = IERC20(_buyTokenAddress);

        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        (bool success, ) = exchangeProxy.call{value: msg.value}(_swapCallData);
        if (!success) revert SwapFailed();

        // Actual collateral/buyToken bought
        uint256 collateralAmount = buyToken.balanceOf(address(this));

        // If there's an helper contract, the buyToken has to be transformed
        if (address(markets[_buyTokenAddress].helper) != address(0)) {
            uint256 estimateAmount = markets[_buyTokenAddress]
                .helper
                .assetToCollateral(collateralAmount);

            // Collateral amount is now transformed
            collateralAmount = markets[_buyTokenAddress]
                .helper
                .transformToCollateral(collateralAmount, _helperData);

            if (
                collateralAmount + 1 < estimateAmount &&
                markets[_buyTokenAddress].collateral.balanceOf(address(this)) <
                collateralAmount
            ) revert DepositFailed();
        }

        // Deposit and borrow on behalf
        market.deposit(msg.sender, collateralAmount);

        uint256 dolaToBorrow = _value;

        if (_dbrData.amountIn != 0) {
            dolaToBorrow += _dbrData.amountIn;
        }
        // We borrow the amount of DOLA we minted before plus the amount for buying DBR if any
        market.borrowOnBehalf(
            msg.sender,
            dolaToBorrow,
            _permit.deadline,
            _permit.v,
            _permit.r,
            _permit.s
        );

        if (dola.balanceOf(address(this)) < dolaToBorrow)
            revert DOLAInvalidBorrow();

        // Burn the dola minted previously
        dola.burn(_value);

        if (_dbrData.amountIn != 0) {
            _buyDbr(_dbrData.amountIn, _dbrData.minOut, msg.sender);
        }

        // Refund any possible unspent 0x protocol fees to the sender.
        if (address(this).balance > 0)
            payable(msg.sender).transfer(address(this).balance);
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
