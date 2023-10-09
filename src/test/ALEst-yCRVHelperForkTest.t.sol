// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../BorrowController.sol";
import "../DBR.sol";
import "../Fed.sol";
import "../Market.sol";
import "../Oracle.sol";
import {ALE} from "../util/ALE.sol";
import {STYCRVHelper} from "../util/STYCRVHelper.sol";
import {YCRVFeed} from "./mocks/YCRVFeed.sol";
import {ISTYCRV} from "../interfaces/ISTYCRV.sol";
import {console} from "forge-std/console.sol";

interface IErc20 is IERC20 {
    function approve(address beneficiary, uint amount) external;
}

interface IMintable is IErc20 {
    function mint(address receiver, uint amount) external;

    function addMinter(address minter) external;
}

contract MockExchangeProxy {
    IOracle oracle;
    IERC20 dola;

    constructor(address _oracle, address _dola) {
        oracle = IOracle(_oracle);
        dola = IERC20(_dola);
    }

    function swapDolaIn(
        IERC20 collateral,
        uint256 dolaAmount
    ) external returns (bool success, bytes memory ret) {
        dola.transferFrom(msg.sender, address(this), dolaAmount);
        uint256 collateralAmount = (dolaAmount * 1e18) /
            oracle.viewPrice(address(collateral), 0);
        collateral.transfer(msg.sender, collateralAmount);
        success = true;
    }

    function swapDolaOut(
        IERC20 collateral,
        uint256 collateralAmount
    ) external returns (bool success, bytes memory ret) {
        collateral.transferFrom(msg.sender, address(this), collateralAmount);
        uint256 dolaAmount = (collateralAmount *
            oracle.viewPrice(address(collateral), 0)) / 1e18;
        dola.transfer(msg.sender, dolaAmount);
        success = true;
    }
}

contract ALEHelperForkTest is Test {
    //Market deployment:
    Market market;
    IChainlinkFeed feed;
    BorrowController borrowController;

    //EOAs & Multisigs
    address user = address(0x69);
    address user2 = address(0x70);
    address replenisher = address(0x71);
    address collatHolder = address(0x577eBC5De943e35cdf9ECb5BbE1f7D7CB6c7C647); // sty CRV
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    address chair = address(0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8);
    address pauseGuardian = address(0xE3eD95e130ad9E15643f5A5f232a3daE980784cd);
    address curvePool = address(0x056ef502C1Fc5335172bc95EC4cAE16C2eB9b5b6); // DBR/DOLA pool
    address styCRVHolder = address(0x577eBC5De943e35cdf9ECb5BbE1f7D7CB6c7C647);
    address yCRVHolder = address(0xEE8fe4827ea1ad40e6960dDce84A97360D60dac2);
    address styCRV = address(0x27B5739e22ad9033bcBf192059122d163b60349D);
    address yCRV = address(0xFCc5c47bE19d06BF83eB04298b026F81069ff65b);
    address triDBR = address(0xC7DE47b9Ca2Fc753D6a2F167D8b3e19c6D18b19a);
    
    //ERC-20s
    IMintable DOLA;
    IErc20 collateral;

    //FiRM
    Oracle oracle;
    IEscrow escrowImplementation;
    DolaBorrowingRights dbr;
    Fed fed;

    MockExchangeProxy exchangeProxy;
    ALE ale;
    STYCRVHelper helper;
    YCRVFeed feedYCRV;

    //Variables
    uint collateralFactorBps;
    uint replenishmentIncentiveBps;
    uint liquidationBonusBps;
    uint replenishmentPriceBps;

    uint testAmount = 1 ether;

    bytes onlyChair = "ONLY CHAIR";
    bytes onlyGov = "Only gov can call this function";
    bytes onlyLender = "Only lender can recall";
    bytes onlyOperator = "ONLY OPERATOR";

    function setUp() public {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url,18164420);

        DOLA = IMintable(0x865377367054516e17014CcdED1e7d814EDC9ce4);
        market = Market(0x27b6c301Fd441f3345d61B7a4245E1F823c3F9c4); // st-yCRV Market
        feed = IChainlinkFeed(0xfc63C9c8Ba44AE89C01265453Ed4F427C80cBd4E);
        borrowController = BorrowController(
            0x20C7349f6D6A746a25e66f7c235E96DAC880bc0D
        );
        dbr = DolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);

        replenishmentIncentiveBps = market.replenishmentIncentiveBps();
        liquidationBonusBps = market.liquidationIncentiveBps();
        replenishmentPriceBps = dbr.replenishmentPriceBps();

        helper = new STYCRVHelper();
        feedYCRV = new YCRVFeed();

        exchangeProxy = new MockExchangeProxy(
            address(market.oracle()),
            address(DOLA)
        );

        vm.startPrank(gov);
        market.pauseBorrows(false);
        dbr.addMarket(address(market));
        vm.stopPrank();

        ale = new ALE(address(exchangeProxy), triDBR);
        ale.setMarket(
            address(market),
            yCRV,
            address(market.collateral()),
            address(helper)
        );

        //FiRM
        oracle = Oracle(address(market.oracle()));
        escrowImplementation = IEscrow(market.escrowImplementation());
        fed = Fed(market.lender());
        collateral = IErc20(address(market.collateral()));

        vm.label(user, "user");
        vm.label(user2, "user2");

        //Warp forward 7 days since local chain timestamp is 0, will cause revert when calculating `days` in oracle.
        vm.warp(block.timestamp + 7 days);

        vm.startPrank(gov, gov);
        market.setBorrowController(
            IBorrowController(address(borrowController))
        );
        market.setCollateralFactorBps(7500);
        borrowController.setDailyLimit(address(market), 250_000 * 1e18);
     
        fed.changeMarketCeiling(IMarket(address(market)), type(uint).max);
        fed.changeSupplyCeiling(type(uint).max);
        oracle.setFeed(address(collateral), feed, 18);
        oracle.setFeed(yCRV, IChainlinkFeed(address(feedYCRV)), 18);
        borrowController.allow(address(ale));
        DOLA.addMinter(address(ale));
        vm.stopPrank();

        collateralFactorBps = market.collateralFactorBps();
    }

    function checkEq(
        uint stYCRVDeposit,
        uint collateralToSwap,
        address userPk
    ) internal {
        assertApproxEqAbs(
            IErc20(styCRV).balanceOf(address(market.predictEscrow(userPk))),
            stYCRVDeposit + collateralToSwap,
            1
        );
    }

    function test_leveragePosition() public {
        // vm.assume(styCRVAmount < 7900 ether);
        // vm.assume(styCRVAmount > 0.00000001 ether);
        // We are going to deposit some CRV, then leverage the position
        uint styCRVAmount = 1 ether;
        address userPk = vm.addr(1);
        vm.prank(styCRVHolder);
        IERC20(styCRV).transfer(userPk, styCRVAmount);

        gibDBR(userPk, styCRVAmount);

        uint maxBorrowAmount = _getMaxBorrowAmount(styCRVAmount);

        uint256 yCRVAmount = helper.collateralToAsset(
            _convertDolaToCollat(maxBorrowAmount)
        );
        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.prank(yCRVHolder);
        IERC20(yCRV).transfer(address(exchangeProxy), yCRVAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        IErc20(styCRV).approve(address(market), styCRVAmount);
        market.deposit(styCRVAmount);

        // Sign Message for borrow on behalf
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        maxBorrowAmount,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            yCRV,
            maxBorrowAmount
        );

        ALE.DBRHelper memory dbrData;

        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        assertApproxEqAbs(
            IErc20(styCRV).balanceOf(address(market.predictEscrow(userPk))),
            styCRVAmount +
                helper.assetToCollateral(
                    _convertDolaToUnderlying(maxBorrowAmount)
                ),
            1
        );

        assertEq(DOLA.balanceOf(userPk), 0);
    }

    function test_leveragePosition_buyDBR() public {
        // We are going to deposit some st-yCRV, then leverage the position
        uint styCRVAmount = 1 ether;
        address userPk = vm.addr(1);
        vm.prank(styCRVHolder);
        IERC20(styCRV).transfer(userPk, styCRVAmount);

        uint maxBorrowAmount = _getMaxBorrowAmount(styCRVAmount);

        uint256 yCRVAmount = helper.collateralToAsset(
            _convertDolaToCollat(maxBorrowAmount)
        );

        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.prank(yCRVHolder);
        IERC20(yCRV).transfer(address(exchangeProxy), yCRVAmount + 2);

        vm.startPrank(userPk, userPk);
        // Initial st-yCRV deposit
        IErc20(styCRV).approve(address(market), styCRVAmount);
        market.deposit(styCRVAmount);

        // Calculate the amount of DOLA needed to borrow to buy the DBR needed to cover for the borrowing period
        (uint256 dolaForDBR, uint256 dbrAmount) = ale
            .approximateDolaAndDbrNeeded(maxBorrowAmount, 365 days, 8);

        // Sign Message for borrow on behalf
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        maxBorrowAmount + dolaForDBR,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaIn.selector,
            yCRV,
            maxBorrowAmount
        );

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
            dolaForDBR,
            (dbrAmount * 98) / 100,
            0
        );

        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        checkEq(styCRVAmount, _convertDolaToCollat(maxBorrowAmount), userPk);

        assertEq(DOLA.balanceOf(userPk), 0);

        assertGt(dbr.balanceOf(userPk), (dbrAmount * 98) / 100);
    }

    function test_deleveragePosition_sellDBR(uint256 styCRVAmount) public {
        vm.assume(styCRVAmount < 7900 ether);
        vm.assume(styCRVAmount > 0.00000001 ether);
        // We are going to deposit some st-yCRV, then borrow and then deleverage the position
        //uint styCRVAmount = 1 ether;
        address userPk = vm.addr(1);
        vm.prank(styCRVHolder);
        IERC20(styCRV).transfer(userPk, styCRVAmount);

        gibDBR(userPk, styCRVAmount);

        uint borrowAmount = (_getMaxBorrowAmount(styCRVAmount) * 97) / 100;

        vm.startPrank(userPk, userPk);
        // Initial styCRV deposit
        IErc20(styCRV).approve(address(market), styCRVAmount);
        market.deposit(styCRVAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        assertEq(
            IERC20(styCRV).balanceOf(address(market.predictEscrow(userPk))),
            styCRVAmount
        );
        assertEq(DOLA.balanceOf(userPk), borrowAmount);

        // We are going to withdraw only 1/10 of the collateral to deleverage
        uint256 amountToWithdraw = IERC20(styCRV).balanceOf(
            address(market.predictEscrow(userPk))
        ) / 10;

        uint256 dolaAmountForSwap = _convertUnderlyingToDola(
            helper.collateralToAsset(amountToWithdraw)
        );

        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), dolaAmountForSwap);
        vm.stopPrank();

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        amountToWithdraw,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(dbr.balanceOf(userPk), 0, 0); // sell all DBR

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            yCRV,
            helper.collateralToAsset(amountToWithdraw)
        );

        vm.startPrank(userPk, userPk);
        dbr.approve(address(ale), type(uint).max);

        ale.deleveragePosition(
            _convertCollatToDola(amountToWithdraw),
            address(market),
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // Some collateral has been withdrawn
        assertEq(
            IERC20(styCRV).balanceOf(address(market.predictEscrow(userPk))),
            styCRVAmount - amountToWithdraw
        );

        // User still has dola and actually he has more bc he sold his DBRs
        assertGt(DOLA.balanceOf(userPk), borrowAmount);

        assertEq(dbr.balanceOf(userPk), 0);
    }

    function test_deleveragePosition(uint256 styCRVAmount) public {
        vm.assume(styCRVAmount < 7900 ether);
        vm.assume(styCRVAmount > 0.00000001 ether);
        // We are going to deposit some st-yCRV, then borrow and then deleverage the position
        uint styCRVAmount = 1 ether;
        address userPk = vm.addr(1);
        vm.prank(styCRVHolder);
        IERC20(styCRV).transfer(userPk, styCRVAmount);

        gibDBR(userPk, styCRVAmount);

        uint borrowAmount = (_getMaxBorrowAmount(styCRVAmount) * 97) / 100;

        vm.startPrank(userPk, userPk);
        // Initial styCRV deposit
        IErc20(styCRV).approve(address(market), styCRVAmount);
        market.deposit(styCRVAmount);
        market.borrow(borrowAmount);
        vm.stopPrank();

        address userEscrow = address(market.predictEscrow(userPk));
        assertEq(IERC20(styCRV).balanceOf(userEscrow), styCRVAmount);
        assertEq(DOLA.balanceOf(userPk), borrowAmount);

        // We are going to withdraw only 1/10 of the collateral to deleverage
        uint256 amountToWithdraw = IERC20(styCRV).balanceOf(userEscrow) / 10;
        uint256 dolaAmountForSwap = _convertUnderlyingToDola(
            helper.collateralToAsset(amountToWithdraw)
        );

        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), dolaAmountForSwap);
        vm.stopPrank();

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(ale),
                        userPk,
                        amountToWithdraw,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        ALE.Permit memory permit = ALE.Permit(block.timestamp, v, r, s);

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(0,0,borrowAmount/2); // repay partially debt with DOLA in the wallet

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            yCRV,
            helper.collateralToAsset(amountToWithdraw)
        );

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(ale), borrowAmount/2);

        ale.deleveragePosition(
            _convertCollatToDola(amountToWithdraw),
            address(market),
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            bytes(""),
            dbrData
        );

        // Some collateral has been withdrawn
        assertEq(
            IERC20(styCRV).balanceOf(userEscrow),
            styCRVAmount - amountToWithdraw
        );
        // User still has dola but has some debt repaid
        assertApproxEqAbs(DOLA.balanceOf(userPk), borrowAmount/2, 1);
    }

    function test_transformToCollateralAndDeposit(uint256 yCRVAmount) public {
        vm.assume(yCRVAmount < ISTYCRV(styCRV).availableDepositLimit());

        uint256 yCRVAmount = 1 ether;
        address userPk = vm.addr(1);
        vm.prank(yCRVHolder);
        IERC20(yCRV).transfer(userPk, yCRVAmount);

        vm.startPrank(userPk, userPk);
        IErc20(yCRV).approve(address(helper), yCRVAmount);
        helper.transformToCollateralAndDeposit(yCRVAmount, "");

        assertEq(IERC20(yCRV).balanceOf(userPk), 0);
        Market market = Market(address(helper.market()));

        assertEq(
            IErc20(styCRV).balanceOf(address(market.predictEscrow(userPk))),
            helper.assetToCollateral(yCRVAmount)
        );
    }

    function test_withdrawAndTransformFromCollateral(uint256 yCRVAmount) public {
        vm.assume(yCRVAmount < ISTYCRV(styCRV).availableDepositLimit());
        
        uint256 yCRVAmount = 1 ether;
        address userPk = vm.addr(1);
        vm.prank(yCRVHolder);
        IERC20(yCRV).transfer(userPk, yCRVAmount);

        vm.startPrank(userPk, userPk);
        IErc20(yCRV).approve(address(helper), yCRVAmount);
        helper.transformToCollateralAndDeposit(yCRVAmount, "");

        Market market = Market(address(helper.market())); // actual Mainnet market for helper contract
        uint256 amountToWithdraw = IErc20(styCRV).balanceOf(
            address(market.predictEscrow(userPk))
        ) / 10;

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                market.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                        ),
                        address(helper),
                        userPk,
                        amountToWithdraw,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        STYCRVHelper.Permit memory permit = STYCRVHelper.Permit(
            block.timestamp,
            v,
            r,
            s
        );

        assertEq(IERC20(yCRV).balanceOf(userPk), 0);

        helper.withdrawAndTransformFromCollateral(amountToWithdraw, permit, "");

        assertApproxEqAbs(
            IERC20(yCRV).balanceOf(userPk),
            helper.collateralToAsset(amountToWithdraw),
            1
        );
    }

    function _convertCollatToDola(uint amount) internal view returns (uint) {
        uint256 underlying = helper.collateralToAsset(amount);
        return _convertUnderlyingToDola(underlying);
    }

    function _convertDolaToCollat(uint amount) internal view returns (uint) {
        uint256 underlying = _convertDolaToUnderlying(amount);
        return helper.assetToCollateral(underlying);
    }

    function _convertDolaToUnderlying(
        uint amount
    ) internal view returns (uint) {
        return (amount * 1e18) / oracle.viewPrice(yCRV, 0);
    }

    function _convertUnderlyingToDola(
        uint amount
    ) internal view returns (uint) {
        return (amount * oracle.viewPrice(yCRV, 0)) / 1e18;
    }

    function _getMaxBorrowAmount(
        uint amountCollat
    ) internal view returns (uint) {
        return
            (_convertCollatToDola(amountCollat) *
                market.collateralFactorBps()) / 10_000;
    }

    function gibWeth(address _address, uint _amount) internal {
        vm.startPrank(collatHolder, collatHolder);
        collateral.transfer(_address, _amount);
        vm.stopPrank();
    }

    function gibDBR(address _address, uint _amount) internal {
        vm.startPrank(gov);
        dbr.mint(_address, _amount);
        vm.stopPrank();
    }

    function gibDOLA(address _address, uint _amount) internal {
        vm.startPrank(gov);
        DOLA.mint(_address, _amount);
        vm.stopPrank();
    }

    function codeAt(address _addr) public view returns (bytes memory o_code) {
        assembly {
            // retrieve the size of the code, this needs assembly
            let size := extcodesize(_addr)
            // allocate output byte array - this could also be done without assembly
            // by using o_code = new bytes(size)
            o_code := mload(0x40)
            // new "memory end" including padding
            mstore(
                0x40,
                add(o_code, and(add(add(size, 0x20), 0x1f), not(0x1f)))
            )
            // store length in memory
            mstore(o_code, size)
            // actually retrieve the code, this needs assembly
            extcodecopy(_addr, add(o_code, 0x20), 0, size)
        }
    }
}
