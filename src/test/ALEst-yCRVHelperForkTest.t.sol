// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./FiRMForkTest.sol";
import "../BorrowController.sol";
import "../DBR.sol";
import "../Fed.sol";
import "../Market.sol";
import "../Oracle.sol";
import "./mocks/ERC20.sol";
import "./mocks/BorrowContract.sol";
import {ALE} from "../util/ALE.sol";
import {STYCRVHelper} from "../util/STYCRVHelper.sol";
import {STYCRVFeed} from "./mocks/STYCRVFeed.sol";
import {console} from "forge-std/console.sol";
import {ITransformHelper} from "../interfaces/ITransformHelper.sol";

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

contract ALEForkTest is FiRMForkTest {
    bytes onlyGovUnpause = "Only governance can unpause";
    bytes onlyPauseGuardianOrGov =
        "Only pause guardian or governance can pause";
    bytes exceededLimit = "Exceeded credit limit";
    bytes repaymentGtThanDebt = "Repayment greater than debt";

    BorrowContract borrowContract;
    IERC20 WETH;
    MockExchangeProxy exchangeProxy;
    ALE ale;
    Market styCRVmarket; // st-yCRV Market
    STYCRVHelper helper;
    STYCRVFeed feedSTYCRV;

    address styCRV = 0x27B5739e22ad9033bcBf192059122d163b60349D;
    address yCRV = 0xFCc5c47bE19d06BF83eB04298b026F81069ff65b;
    uint256 liquidationBonusBpsNew = 100;

    address styCRVHolder = 0x577eBC5De943e35cdf9ECb5BbE1f7D7CB6c7C647;
    address yCRVHolder = 0xEE8fe4827ea1ad40e6960dDce84A97360D60dac2;

    function setUp() public {
        //This will fail if there's no mainnet variable in foundry.toml
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url);
        init();
        helper = new STYCRVHelper();
        feedSTYCRV = new STYCRVFeed();

        // Deploy st-yCRV Market
        initialize(
            collateralFactorBps,
            replenishmentIncentiveBps,
            liquidationBonusBpsNew,
            callOnDepositCallback
        );

        vm.startPrank(chair, chair);
        fed.expansion(IMarket(address(styCRVmarket)), 100_000e18);
        vm.stopPrank();

        borrowContract = new BorrowContract(
            address(styCRVmarket),
            payable(address(styCRVmarket.collateral()))
        );

        exchangeProxy = new MockExchangeProxy(
            address(styCRVmarket.oracle()),
            address(DOLA)
        );

        ale = new ALE(address(DOLA), address(exchangeProxy));
        // ALE setup
        vm.prank(gov);
        DOLA.addMinter(address(ale));

        ale.setMarket(
            yCRV,
            IMarket(address(styCRVmarket)),
            address(styCRVmarket.collateral()),
            address(helper)
        );

        // Allow contract
        vm.prank(gov);
        borrowController.allow(address(ale));
    }

    function initialize(
        uint collateralFactorBps_,
        uint replenishmentIncentiveBps_,
        uint liquidationBonusBps_,
        bool callOnDepositCallback_
    ) public {
        vm.startPrank(gov, gov);

        styCRVmarket = new Market(
            gov,
            address(fed),
            pauseGuardian,
            address(escrowImplementation),
            IDolaBorrowingRights(address(dbr)),
            IERC20(address(styCRV)),
            IOracle(address(oracle)),
            collateralFactorBps_,
            replenishmentIncentiveBps_,
            liquidationBonusBps_,
            callOnDepositCallback_
        );

        fed.changeMarketCeiling(IMarket(address(styCRVmarket)), type(uint).max);
        styCRVmarket.setBorrowController(
            IBorrowController(address(borrowController))
        );

        dbr.addMarket(address(styCRVmarket));
        oracle.setFeed(
            address(styCRV),
            IChainlinkFeed(address(feedSTYCRV)),
            18
        );
        oracle.setFeed(address(yCRV), IChainlinkFeed(address(feedSTYCRV)), 18);
        vm.stopPrank();
    }

    function _convertCollatToDola(uint amount) internal view returns (uint) {
        (, int latestAnswer, , , ) = feedSTYCRV.latestRoundData();
        return (amount * uint(latestAnswer)) / 10 ** feedSTYCRV.decimals();
    }

    function _convertDolaToCollat(uint amount) internal view returns (uint) {
        (, int latestAnswer, , , ) = feedSTYCRV.latestRoundData();
        return (amount * 10 ** feedSTYCRV.decimals()) / uint(latestAnswer);
    }

    function _getMaxBorrowAmount(
        uint amountCollat
    ) internal view returns (uint) {
        return
            (_convertCollatToDola(amountCollat) *
                styCRVmarket.collateralFactorBps()) / 10_000;
    }

    function test_leveragePosition() public {
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
        IERC20(yCRV).transfer(address(exchangeProxy), yCRVAmount);

        vm.startPrank(userPk, userPk);
        // Initial CRV deposit
        IErc20(styCRV).approve(address(styCRVmarket), styCRVAmount);
        styCRVmarket.deposit(styCRVAmount);

        // Sign Message for borrow on behalf
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                styCRVmarket.DOMAIN_SEPARATOR(),
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

        ale.leveragePosition(
            maxBorrowAmount,
            yCRV,
            address(exchangeProxy),
            swapData,
            permit,
            bytes("")
        );

        // Balance in escrow is equal to the collateral deposited + the extra collateral swapped from the leverage
        assertApproxEqAbs(
            IErc20(styCRV).balanceOf(
                address(styCRVmarket.predictEscrow(userPk))
            ),
            styCRVAmount +
                helper.assetToCollateral(_convertDolaToCollat(maxBorrowAmount)),
            1
        );

        assertEq(DOLA.balanceOf(userPk), 0);
    }

    function test_deleveragePosition() public {
        // We are going to deposit some CRV, then leverage the position
        uint styCRVAmount = 1 ether;
        address userPk = vm.addr(1);
        vm.prank(styCRVHolder);
        IERC20(styCRV).transfer(userPk, styCRVAmount);

        gibDBR(userPk, styCRVAmount);

        uint borrowAmount = _getMaxBorrowAmount(styCRVAmount) / 2;

        //uint256 yCRVAmount = helper.collateralToAsset(_convertDolaToCollat(borrowAmount));

        // recharge mocked proxy for swap, we need to swap DOLA to unwrapped collateral
        // vm.prank(yCRVHolder);
        // IERC20(yCRV).transfer(address(exchangeProxy), 10 ether);

        vm.startPrank(gov);
        DOLA.mint(address(exchangeProxy), _convertDolaToCollat(borrowAmount));
        vm.stopPrank();

        // We are going to deposit some CRV, then fully leverage the position

        // uint crvTestAmount = 1 ether;
        // address userPk = vm.addr(1);
        // gibWeth(userPk, crvTestAmount);
        // gibDBR(userPk, crvTestAmount);

        // // Max Amount borrowable is the one available from collateral amount +
        // // the extra borrow amount from the max borrow amount swapped and re-deposited as collateral
        // uint borrowAmount = getMaxBorrowAmount(crvTestAmount)/2;

        // // recharge mocked proxy for swap, we need to swap collateral to DOLA
        // vm.startPrank(gov);
        // DOLA.mint(address(exchangeProxy), convertCollatToDola(crvTestAmount/10));
        // vm.stopPrank();

        vm.startPrank(userPk, userPk);
        // Initial styCRV deposit
        IErc20(styCRV).approve(address(styCRVmarket), styCRVAmount);
        styCRVmarket.deposit(styCRVAmount);
        styCRVmarket.borrow(borrowAmount);

        assertEq(
            IERC20(styCRV).balanceOf(
                address(styCRVmarket.predictEscrow(userPk))
            ),
            styCRVAmount
        );
        assertEq(DOLA.balanceOf(userPk), borrowAmount);

        // We are going to withdraw only 1/10 of the collateral to deleverage
        uint256 amountToWithdraw = IERC20(styCRV).balanceOf(
            address(styCRVmarket.predictEscrow(userPk))
        ) / 10;

        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                styCRVmarket.DOMAIN_SEPARATOR(),
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

        bytes memory swapData = abi.encodeWithSelector(
            MockExchangeProxy.swapDolaOut.selector,
            yCRV,
            amountToWithdraw
        );

        ale.deleveragePosition(
            _convertCollatToDola(amountToWithdraw),
            yCRV,
            amountToWithdraw,
            address(exchangeProxy),
            swapData,
            permit,
            bytes("")
        );

        // Some collateral has been withdrawn
        assertEq(
            IERC20(styCRV).balanceOf(
                address(styCRVmarket.predictEscrow(userPk))
            ),
            styCRVAmount - amountToWithdraw
        );
        // User still has dola but has some debt repaid
        assertEq(DOLA.balanceOf(userPk), borrowAmount);
    }
}
