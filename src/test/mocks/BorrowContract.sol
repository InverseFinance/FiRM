// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../Market.sol";
import "../mocks/WETH9.sol";

contract BorrowContract {
    Market market;

    constructor(address market_, address payable weth_) {
        market = Market(market_);
        WETH9(weth_).approve(address(market), type(uint).max);
    }

    function borrow(uint amount) external {
        market.borrow(amount);
    }

    function deposit(uint amount) external {
        market.deposit(amount);
    }
}