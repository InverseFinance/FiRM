//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "src/interfaces/IMarket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IDola.sol";
import "src/interfaces/ITransformHelper.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
// Accelerated leverage engine
contract ALE is Ownable, ReentrancyGuard {

    error TargetNotExchangeProxy(address target);
    error MarketNotSetForCollateral(address collateral);
    error SwapFailed();
    error DOLAInvalidBorrow();
    error DOLAInvalidRepay();
    error InvalidProxyAddress();

    // 0x ExchangeProxy address.
    // See https://docs.0x.org/developer-resources/contract-addresses
    address public exchangeProxy;

    IDola public immutable dola;

    struct Market {
        address market;
        address helper;
        address collateral;
    }

    // Mapping of sellToken/buyToken to Market structs
    // NOTE: in normal cases sellToken/buyToken is the collateral token, 
    // in other cases it could be different (eg. st-yCRV is collateral, yCRV is the token to be swapped from/to DOLA)
    // That's why we need to keep track of collateral in market struct
    mapping(address => Market) public markets;

    constructor(address _dola, address _exchangeProxy) Ownable(msg.sender){
        dola = IDola(_dola);
        exchangeProxy = _exchangeProxy;
    }

    function setExchangeProxy(address _exchangeProxy) external onlyOwner {
        if(_exchangeProxy == address(0)) revert InvalidProxyAddress();
        exchangeProxy = _exchangeProxy;
    }

    function setMarket(address _market, address _buySelltoken) external onlyOwner {
        markets[_buySelltoken].market = _market;
    }

    function setMarketHelper(address _helper, address _buySelltoken) external onlyOwner {
        markets[_buySelltoken].helper = _helper;
    }

    function setMarketCollateral(address _collateral, address _buySelltoken) external onlyOwner {
        markets[_buySelltoken].collateral = _collateral;
    }

    function leveragePosition(
        // Amount of DOLA to borrow
        uint256 _value,
        // `buyTokenAddress` field from the API response.
        address _buyTokenAddress,
        // The `allowanceTarget` field from the API response.
        address _spender,
        // The `to` field from the API response.
        address payable _swapTarget,
        // The `data` field from the API response.
        bytes calldata _swapCallData,
        // Deadline for permit borrow on behalt
        uint256 _deadline,
        // Signature for permit borrow on behalt
        uint8 _v,
        bytes32 _r,
        bytes32 _s,
        // Optional helper data in case the collateral needs to be transformed
        bytes calldata _helperData
    ) external nonReentrant payable {
        // Checks that the swapTarget is actually the address of 0x ExchangeProxy
        if(_swapTarget != exchangeProxy) revert TargetNotExchangeProxy(_swapTarget);
        if(markets[_buyTokenAddress].market == address(0)) revert MarketNotSetForCollateral(_buyTokenAddress);
        
        IMarket market = IMarket(markets[_buyTokenAddress].market);
    
        // Mint and approve
        dola.mint(address(this), _value);
        dola.approve(_spender, _value);

        IERC20 buyToken = IERC20(_buyTokenAddress);
        uint256 collateralBalBefore = buyToken.balanceOf(address(this));
        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        (bool success, ) = _swapTarget.call{value: msg.value}(_swapCallData);
        if(!success) revert SwapFailed();

        uint256 collateralBalanceAfter = buyToken.balanceOf(
            address(this)
        );

        // Actual collateral/buyToken bought
        uint256 collateralAmount = collateralBalanceAfter -
            collateralBalBefore;

        // If there's an helper contract, the buyToken has to be transformed
        if(markets[_buyTokenAddress].helper != address(0)) {
            // Approve collateral to be transformed
            buyToken.approve(markets[_buyTokenAddress].helper, collateralAmount);
            // Collateral amount is now transformed
            collateralAmount = ITransformHelper(markets[_buyTokenAddress].helper).transformToCollateral(collateralAmount, _helperData);
            // Approve market to spend transformed collateral
            IERC20(markets[_buyTokenAddress].collateral).approve(address(market), collateralAmount);
        } else {
            // If there's no helper it means we already bought the collateral token so we can deposit
            // Approve market to spend collateral
            buyToken.approve(address(market), collateralAmount);
        }

        // Deposit and borrow on behalf
        market.deposit(msg.sender, collateralAmount);

        // We borrow the amount of DOLA we minted before
        market.borrowOnBehalf(
            msg.sender,
            _value,
            _deadline,
            _v,
            _r,
            _s
        );

        if(dola.balanceOf(address(this)) < _value) revert DOLAInvalidBorrow();
    
        // Burn the dola minted previously
        dola.burn(_value);

        // Refund any possible unspent 0x protocol fees to the sender.
        payable(msg.sender).transfer(address(this).balance);
    }

    function deleveragePosition(
        // Amount of DOLA to repay
        uint256 _value,
        // `sellTokenAddress` field from the API response.
        address _sellTokenAddress,
        // Collateral amount to withdraw from the escrow
        uint256 _collateralAmount,
        // The `allowanceTarget` field from the API response.
        address _spender,
        // The `to` field from the API response.
        address payable _swapTarget,
        // The `data` field from the API response.
        bytes calldata _swapCallData,
        // Deadline for permit withdraw on behalf
        uint256 _deadline,
        // Signature for permit withdraw on behalf
        uint8 _v,
        bytes32 _r,
        bytes32 _s,
        // Optional helper data in case collateral needs to be transformed
        bytes calldata _helperData
    ) external nonReentrant payable {
        // Checks that the swapTarget is actually the address of 0x ExchangeProxy
        if(_swapTarget != exchangeProxy) revert TargetNotExchangeProxy(_swapTarget);
        if(markets[_sellTokenAddress].market == address(0)) revert MarketNotSetForCollateral(_sellTokenAddress);

        IMarket market = IMarket(markets[_sellTokenAddress].market);
        IERC20 collateral = IERC20(markets[_sellTokenAddress].collateral);

        dola.mint(address(this), _value);

        market.repay(msg.sender, _value);
       
        // withdraw amount from ZERO EX quote
        market.withdrawOnBehalf(msg.sender, _collateralAmount, _deadline, _v, _r, _s);
        
        // If there's an helper contract, the collateral has to be transformed
        if(markets[_sellTokenAddress].helper != address(0)) {
            //Approve collateral to be transformed to sellToken
             collateral.approve(markets[_sellTokenAddress].helper, _collateralAmount);
            // Collateral amount is now transformed into sellToken
            _collateralAmount = ITransformHelper(markets[_sellTokenAddress].helper).transformFromCollateral(_collateralAmount, _helperData);
            // Approve sellToken for spender
            IERC20(_sellTokenAddress).approve(_spender, _collateralAmount);
        } else {
            // If there's no helper the withdrawn collateral is the sellToken
            // Approve collateral to be swapped
            collateral.approve(_spender, 0); // in some cases like USDT we need to first set it to zero and the approve (TODO review this)
            collateral.approve(_spender, _collateralAmount); 
        }

        uint256 dolaBalBefore = dola.balanceOf(address(this));

        // Call the encoded swap function call on the contract at `swapTarget`,
        // passing along any ETH attached to this function call to cover protocol fees.
        // NOTE: This will swap the collateral or helperCollateral for DOLA
        (bool success, ) = _swapTarget.call{value: msg.value}(_swapCallData);
        if(!success) revert SwapFailed();
        
        uint256 dolaBalAfter = dola.balanceOf(address(this));

        if(dolaBalAfter - dolaBalBefore < _value) revert DOLAInvalidRepay();

        dola.burn(_value);

        // Refund any unspent protocol fees to the sender.
        payable(msg.sender).transfer(address(this).balance);
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}
}
