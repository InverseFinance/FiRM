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
    error MarketNotSet(address market);
    error SwapFailed();
    error DOLAInvalidBorrow(uint256 expected, uint256 actual);
    error DOLAInvalidRepay(uint256 expected, uint256 actual);
    error InvalidProxyAddress();
    error InvalidHelperAddress();
    error NothingToDeposit();
    error DepositFailed(uint256 expected, uint256 actual);
    error WithdrawFailed(uint256 expected, uint256 actual);
    error TotalSupplyChanged(uint256 expected, uint256 actual);

    // 0x ExchangeProxy address.
    // See https://docs.0x.org/developer-resources/contract-addresses
    address payable public exchangeProxy;

    struct Market {
        IERC20 buySellToken;
        IERC20 collateral;
        ITransformHelper helper;
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

    // Mapping of market to Market structs
    // NOTE: in normal cases sellToken/buyToken is the collateral token,
    // in other cases it could be different (eg. st-yCRV is collateral, yCRV is the token to be swapped from/to DOLA)
    mapping(address => Market) public markets;

    modifier dolaSupplyUnchanged() {
        uint256 totalSupply = dola.totalSupply();
        _;
        if(totalSupply != dola.totalSupply()) revert TotalSupplyChanged(totalSupply, dola.totalSupply());
    }

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
    /// @param _buySellToken The token which will be bought/sold (usually the collateral token), probably underlying if there's a helper
    /// @param _market The market contract
    /// @param _collateral The collateral token
    /// @param _helper Optional helper contract to transform collateral to buySelltoken and viceversa
    function setMarket(
        address _market,
        address _buySellToken,
        address _collateral,
        address _helper
    ) external onlyOwner {
        markets[_market].buySellToken = IERC20(_buySellToken);
        markets[_market].collateral = IERC20(_collateral);
        IERC20(_buySellToken).approve(_market, type(uint256).max);

        if (_buySellToken != _collateral) {
            IERC20(_collateral).approve(_market, type(uint256).max);
        }

        if (_helper != address(0)) {
            markets[_market].helper = ITransformHelper(_helper);
            IERC20(_buySellToken).approve(_helper, type(uint256).max);
            IERC20(_collateral).approve(_helper, type(uint256).max);
        }
    }

    /// @notice Update the helper contract
    /// @param _market The market we want to update the helper contract for
    /// @param _helper The helper contract
    function updateMarketHelper(
        address _market,
        address _helper
    ) external onlyOwner {
        markets[_market].helper = ITransformHelper(_helper);
        markets[_market].buySellToken.approve(_helper, type(uint256).max);
        markets[_market].collateral.approve(_helper, type(uint256).max);
    }

    /// @notice Leverage user position by minting DOLA, buying collateral, deposting into the user escrow and borrow DOLA on behalf to repay the minted DOLA
    /// @dev Requires user to sign message to permit the contract to borrow DOLA on behalf
    /// @param _value Amount of DOLA to borrow
    /// @param _market The market contract
    /// @param _spender The `allowanceTarget` field from the API response.
    /// @param _swapCallData The `data` field from the API response.
    /// @param _permit Permit data
    /// @param _helperData Optional helper data in case the collateral needs to be transformed
    /// @param _dbrData Optional data in case the user wants to buy DBR and also withdraw some DOLA
    function leveragePosition(
        uint256 _value,
        address _market,
        address _spender,
        bytes calldata _swapCallData,
        Permit calldata _permit,
        bytes calldata _helperData,
        DBRHelper calldata _dbrData
    ) public payable nonReentrant dolaSupplyUnchanged {
        if (address(markets[_market].buySellToken) == address(0))
            revert MarketNotSet(_market);

        IMarket market = IMarket(_market);

        // Mint and approve
        _mintAndApproveDola(_spender, _value);

        IERC20 buyToken = markets[_market].buySellToken;

        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        (bool success, ) = exchangeProxy.call{value: msg.value}(_swapCallData);
        if (!success) revert SwapFailed();

        // Actual collateral/buyToken bought
        uint256 collateralAmount = buyToken.balanceOf(address(this));

        // If there's a helper contract, the buyToken has to be transformed
        if (address(markets[_market].helper) != address(0)) {
            collateralAmount = _convertToCollateral(
                collateralAmount,
                _market,
                _helperData
            );
        }

        // Deposit and borrow on behalf
        market.deposit(msg.sender, collateralAmount);

        _borrowDola(_value, _permit, _dbrData, market);

        // Burn the dola minted previously
        dola.burn(_value);

        if (_dbrData.dola != 0) {
            dola.transfer(msg.sender, _dbrData.dola);
        }

        if (_dbrData.amountIn != 0) {
            _buyDbr(_dbrData.amountIn, _dbrData.minOut, msg.sender);
        }

        if (dola.balanceOf(address(this)) != 0) {
            dola.transfer(msg.sender, dola.balanceOf(address(this)));
        }

        // Refund any possible unspent 0x protocol fees to the sender.
        if (address(this).balance > 0)
            payable(msg.sender).transfer(address(this).balance);
    }

    /// @notice Deposit collateral and instantly leverage user position by minting DOLA, buying collateral, deposting into the user escrow and borrow DOLA on behalf to repay the minted DOLA
    /// @dev Requires user to sign message to permit the contract to borrow DOLA on behalf
    /// @param _initialDeposit Amount of collateral or underlying (in case of helper) to deposit
    /// @param _value Amount of DOLA to borrow
    /// @param _market The market address
    /// @param _spender The `allowanceTarget` field from the API response.
    /// @param _swapCallData The `data` field from the API response.
    /// @param _permit Permit data
    /// @param _helperData Optional helper data in case the collateral needs to be transformed
    function depositAndLeveragePosition(
        uint256 _initialDeposit,
        uint256 _value,
        address _market,
        address _spender,
        bytes calldata _swapCallData,
        Permit calldata _permit,
        bytes calldata _helperData,
        DBRHelper calldata _dbrData
    ) external payable {
        if (_initialDeposit == 0) revert NothingToDeposit();
        IERC20 buyToken = markets[_market].buySellToken;
        buyToken.transferFrom(msg.sender, address(this), _initialDeposit);

        leveragePosition(
            _value,
            _market,
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
    /// @param _market The market contract
    /// @param _collateralAmount Collateral amount to withdraw from the escrow
    /// @param _spender The `allowanceTarget` field from the API response.
    /// @param _swapCallData The `data` field from the API response.
    /// @param _permit Permit data
    /// @param _helperData Optional helper data in case collateral needs to be transformed
    /// @param _dbrData Optional data in case the user wants to sell DBR
    function deleveragePosition(
        uint256 _value,
        address _market,
        uint256 _collateralAmount,
        address _spender,
        bytes calldata _swapCallData,
        Permit calldata _permit,
        bytes calldata _helperData,
        DBRHelper calldata _dbrData
    ) external payable nonReentrant dolaSupplyUnchanged {
        if (address(markets[_market].buySellToken) == address(0))
            revert MarketNotSet(_market);

        IMarket market = IMarket(_market);

        IERC20 sellToken = markets[_market].buySellToken;

        _repayAndWithdraw(_value, _collateralAmount, _permit, _dbrData, market);

        // If there's a helper contract, the collateral has to be transformed
        if (address(markets[_market].helper) != address(0)) {
            _collateralAmount = _convertToAsset(
                _collateralAmount,
                _market,
                sellToken,
                _helperData
            );
        }

        // Approve sellToken for spender
        sellToken.approve(_spender, 0);
        sellToken.approve(_spender, _collateralAmount);

        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        // NOTE: This will swap the collateral or helperCollateral for DOLA
        (bool success, ) = exchangeProxy.call{value: msg.value}(_swapCallData);
        if (!success) revert SwapFailed();

        if (address(markets[_market].helper) == address(0)) {
            uint256 collateralAvailable = markets[_market].collateral.balanceOf(
                address(this)
            );

            if (collateralAvailable != 0) {
                markets[_market].collateral.transfer(
                    msg.sender,
                    collateralAvailable
                );
            }
        } else {
            uint256 sellTokenBal = sellToken.balanceOf(address(this));
            // Send any leftover sellToken to the sender
            if (sellTokenBal != 0) {
                sellToken.transfer(msg.sender, sellTokenBal);
            }
        }

        if (dola.balanceOf(address(this)) < _value)
            revert DOLAInvalidRepay(_value, dola.balanceOf(address(this)));

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

    /// @notice Mint DOLA to this contract and approve the spender
    /// @param spender The spender address
    /// @param _value Amount of DOLA to mint and approve
    function _mintAndApproveDola(address spender, uint256 _value) internal {
        dola.mint(address(this), _value);
        dola.approve(spender, _value);
    }

    /// @notice Borrow DOLA on behalf of the user
    /// @param _value Amount of DOLA to borrow
    /// @param _permit Permit data
    /// @param _dbrData DBR data
    /// @param market The market contract
    function _borrowDola(
        uint256 _value,
        Permit calldata _permit,
        DBRHelper calldata _dbrData,
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
            msg.sender,
            dolaToBorrow,
            _permit.deadline,
            _permit.v,
            _permit.r,
            _permit.s
        );

        if (dola.balanceOf(address(this)) < dolaToBorrow)
            revert DOLAInvalidBorrow(dolaToBorrow, dola.balanceOf(address(this)));
    }

    /// @notice Repay DOLA loan and withdraw collateral from the escrow
    /// @param _value Amount of DOLA to repay
    /// @param _collateralAmount Collateral amount to withdraw from the escrow
    /// @param _permit Permit data
    /// @param _dbrData DBR data
    /// @param market The market contract
    function _repayAndWithdraw(
        uint256 _value,
        uint256 _collateralAmount,
        Permit calldata _permit,
        DBRHelper calldata _dbrData,
        IMarket market
    ) internal {
        if (_dbrData.dola != 0) {
            dola.transferFrom(msg.sender, address(this), _dbrData.dola);

            dola.mint(address(this), _value);
            dola.approve(address(market), _value + _dbrData.dola);

            market.repay(msg.sender, _value + _dbrData.dola);
        } else {
            _mintAndApproveDola(address(market), _value);
            market.repay(msg.sender, _value);
        }

        // withdraw amount from ZERO EX quote
        market.withdrawOnBehalf(
            msg.sender,
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
        bytes calldata _helperData
    ) internal returns (uint256) {
        // Collateral amount is now transformed into sellToken
        uint256 assetAmount = markets[_market].helper.transformFromCollateral(
            _collateralAmount,
            _helperData
        );

        if (sellToken.balanceOf(address(this)) < assetAmount)
            revert WithdrawFailed(assetAmount, sellToken.balanceOf(address(this)));

        return assetAmount;
    }

    /// @notice convert the underlying asset amount into the collateral
    /// @param _assetAmount The amount of sellToken/underlying to convert
    /// @param _market The market contract
    /// @param _helperData Optional helper data
    /// @return collateralAmount The amount of collateral after the conversion
    function _convertToCollateral(
        uint256 _assetAmount,
        address _market,
        bytes calldata _helperData
    ) internal returns (uint256) {
        // Collateral amount is now transformed
        uint256 collateralAmount = markets[_market]
            .helper
            .transformToCollateral(_assetAmount, _helperData);

        if (
            markets[_market].collateral.balanceOf(address(this)) <
            collateralAmount
        )
            revert DepositFailed(
                collateralAmount,
                markets[_market].collateral.balanceOf(address(this))
            );

        return collateralAmount;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
