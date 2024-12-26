pragma solidity ^0.8.13;

import {ICurvePool} from "src/interfaces/ICurvePool.sol";
import {PendlePTHelper} from "src/util/PendlePTHelper.sol";
import "test/marketForkTests/PendlePTUSDeMarketForkTest.t.sol";
import {console} from "forge-std/console.sol";
import {IMultiMarketTransformHelper} from "src/interfaces/IMultiMarketTransformHelper.sol";
import {ALE} from "src/util/ALE.sol";
import {SimpleERC20Escrow} from "src/escrows/SimpleERC20Escrow.sol";
interface IFlashMinter {
    function setMaxFlashLimit(uint256 _maxFlashLimit) external;

    function flashFee(
        address _token,
        uint256 _value
    ) external view returns (uint256);
}

contract MockPendleRouter {
    IERC20 public DOLA;
    IERC20 public pendlePT;
    IERC20 public pendleYT;
    constructor(address _dola, address _pt, address _yt) {
        DOLA = IERC20(_dola);
        pendlePT = IERC20(_pt);
        pendleYT = IERC20(_yt);
    }

    function swapForPt(uint256 _amount, address recipient) external {
        DOLA.transferFrom(msg.sender, address(this), _amount);
        pendlePT.transfer(recipient, _amount);
    }

    function mintPt(uint256 _amount, address recipient) external {
        DOLA.transferFrom(msg.sender, address(this), _amount);
        pendlePT.transfer(recipient, _amount);
        pendleYT.transfer(recipient, _amount);
    }

    function swapForDola(uint256 _amount, address recipient) external {
        pendlePT.transferFrom(msg.sender, address(this), _amount);
        DOLA.transfer(recipient, _amount);
    }

    function redeemPt(uint256 _amount, address recipient) external {
        pendlePT.transferFrom(msg.sender, address(this), _amount);
        pendleYT.transferFrom(msg.sender, address(this), _amount);
        DOLA.transfer(recipient, _amount);
    }
}

contract ALEPendlePTUSDeMockTest is PendlePTUSDeMarketForkTest {
    ALE ale;
    IFlashMinter flash;
    address userPk = vm.addr(1);
    PendlePTHelper helper;
    address userPkEscrow;
    MockPendleRouter mockRouter;

    address pendleRouter = address(0x888888888889758F76e7103c6CbF23ABbF58F946);
    address pendleYT = address(0x96512230bF0Fa4E20Cf02C3e8A7d983132cd2b9F);
    address marketPT = address(0xcDd26Eb5EB2Ce0f203a84553853667aE69Ca29Ce);

    // Pendle Router Mock
    address pendleYTHolder =
        address(0x9844c3688dAaA98De18fBe52499A6B152236896b);

    function setUp() public override {
        super.setUp();
        //  curvePool = dolaFraxBP;
        mockRouter = new MockPendleRouter(
            address(DOLA),
            address(pendlePT),
            address(pendleYT)
        );
        helper = new PendlePTHelper(
            gov,
            pauseGuardian,
            address(DOLA),
            address(mockRouter)
        );

        vm.startPrank(gov);
        DOLA.mint(address(this), 100000 ether);
        helper.setMarket(address(market), address(pendlePT), pendleYT);
        ale = new ALE(address(0), triDBRAddr);
        ale.setMarket(address(market), address(DOLA), address(helper), false);

        flash = IFlashMinter(address(ale.flash()));
        flash.setMaxFlashLimit(10000000 ether);
        DOLA.addMinter(address(flash));
        borrowController.allow(address(ale));
        vm.stopPrank();
        userPkEscrow = address(market.predictEscrow(userPk));

        vm.label(address(DOLA), "DOLA");
        vm.label(address(pendlePT), "pendlePT");
        vm.label(address(pendleYT), "pendleYT");
        // Fill Pendle Router Mock
        vm.prank(gov);
        DOLA.mint(address(mockRouter), 10000000 ether);
        vm.prank(address(pendlePTHolder));
        IERC20(pendlePT).transfer(address(mockRouter), 10000000 ether);
        vm.prank(address(pendleYTHolder));
        IERC20(pendleYT).transfer(address(mockRouter), 10000000 ether);
    }
    function test_leveragePosition_Mint_PT_and_YT_with_DOLA() public {
        vm.prank(gov);
        DOLA.mint(userPk, 1000000 ether);

        _transformAndDeposit(1000000 ether);

        gibDBR(userPk, 20000 ether);

        uint256 ptAmount = SimpleERC20Escrow(userPkEscrow).balance();
        uint maxBorrowAmount = _getMaxBorrowAmount(ptAmount);

        bytes memory swapData;

        ALE.DBRHelper memory dbrData;

        vm.startPrank(userPk);
        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(0),
            swapData,
            _getPermitForBorrow(maxBorrowAmount),
            _encodeMintPt(maxBorrowAmount),
            dbrData
        );
        vm.stopPrank();

        assertEq(DOLA.balanceOf(userPk), 0);
        assertApproxEqRel(
            SimpleERC20Escrow(userPkEscrow).balance(),
            ptAmount + maxBorrowAmount, // 1:1 ratio DOLA/PT
            1e14 // 0.01% Delta
        );
        assertEq(IERC20(pendleYT).balanceOf(userPk), maxBorrowAmount);
    }

    function test_leveragePosition_Swap_DOLA_for_PT() public {
        vm.prank(gov);
        DOLA.mint(userPk, 1000000 ether);

        _transformAndDeposit(1000000 ether);

        gibDBR(userPk, 20000 ether);

        uint256 ptAmount = SimpleERC20Escrow(userPkEscrow).balance();
        uint maxBorrowAmount = _getMaxBorrowAmount(ptAmount);

        bytes memory swapData;

        ALE.DBRHelper memory dbrData;

        vm.startPrank(userPk);
        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(0),
            swapData,
            _getPermitForBorrow(maxBorrowAmount),
            _encodeSwapForPT(maxBorrowAmount),
            dbrData
        );

        assertEq(DOLA.balanceOf(userPk), 0);
        assertApproxEqRel(
            SimpleERC20Escrow(userPkEscrow).balance(),
            ptAmount + maxBorrowAmount, // 1:1 ratio DOLA/PT
            1e14 // 0.01% Delta
        );
    }

    function test_leveragePosition_buyDBR(uint amount) public {
        vm.assume(amount < 5000000 ether);
        vm.assume(amount > 0.001 ether);
        vm.prank(gov);
        DOLA.mint(userPk, amount);

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), amount);
        helper.transformToCollateralAndDeposit(
            amount,
            userPk,
            abi.encode(
                address(market),
                0,
                address(0),
                abi.encodeWithSelector(
                    MockPendleRouter.swapForPt.selector,
                    amount,
                    address(helper)
                )
            )
        );
        vm.stopPrank();

        uint256 lpAmount = SimpleERC20Escrow(userPkEscrow).balance();

        uint maxBorrowAmount = _getMaxBorrowAmount(lpAmount);

        // Calculate the amount of DOLA needed to borrow to buy the DBR needed to cover for the borrowing period
        (uint256 dolaForDBR, uint256 dbrAmount) = ale
            .approximateDolaAndDbrNeeded(maxBorrowAmount, 15 days, 8);

        bytes memory swapData;

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
            dolaForDBR,
            (dbrAmount * 90) / 100,
            0
        );

        vm.startPrank(userPk);
        ale.leveragePosition(
            maxBorrowAmount,
            address(market),
            address(0),
            swapData,
            _getPermitForBorrow(maxBorrowAmount + dolaForDBR),
            _encodeSwapForPT(maxBorrowAmount),
            dbrData
        );

        assertEq(DOLA.balanceOf(userPk), 0);
        assertEq(
            SimpleERC20Escrow(userPkEscrow).balance(),
            lpAmount + maxBorrowAmount
        );
        assertGt(dbr.balanceOf(userPk), (dbrAmount * 95) / 100);
    }

    function test_depositAndLeveragePosition_DOLA(uint amount) public {
        vm.assume(amount < 5000000 ether);
        vm.assume(amount > 0.001 ether);
        vm.prank(gov);
        DOLA.mint(userPk, amount);
        uint256 initialDolaDeposit = amount / 10;

        _transformAndDeposit(amount - initialDolaDeposit);

        uint256 lpAmount = SimpleERC20Escrow(userPkEscrow).balance();
        gibDBR(userPk, 20000 ether);

        uint maxBorrowAmount = _getMaxBorrowAmount(lpAmount);

        bytes memory swapData;

        ALE.DBRHelper memory dbrData;

        vm.startPrank(userPk);
        DOLA.approve(address(ale), initialDolaDeposit);
        ale.depositAndLeveragePosition(
            initialDolaDeposit,
            maxBorrowAmount,
            address(market),
            address(0),
            swapData,
            _getPermitForBorrow(maxBorrowAmount),
            _encodeSwapForPT(maxBorrowAmount + initialDolaDeposit),
            dbrData,
            false
        );

        assertEq(DOLA.balanceOf(userPk), 0, "DOLA BALANCE");
        assertEq(
            SimpleERC20Escrow(userPkEscrow).balance(),
            lpAmount + maxBorrowAmount + initialDolaDeposit
        );
    }

    function test_depositAndLeveragePosition_LP(uint256 amount) public {
        vm.assume(amount < 5000000 ether);
        vm.assume(amount > 0.001 ether);
        vm.prank(gov);
        DOLA.mint(userPk, amount);
        uint256 initialDolaDeposit = amount / 10;

        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), amount);
        uint256 initialLpAmount = helper.transformToCollateral(
            initialDolaDeposit,
            abi.encode(
                address(market),
                0,
                address(0),
                abi.encodeWithSelector(
                    MockPendleRouter.swapForPt.selector,
                    initialDolaDeposit,
                    address(helper)
                )
            )
        );
        helper.transformToCollateralAndDeposit(
            amount - initialDolaDeposit,
            userPk,
            abi.encode(
                address(market),
                0,
                address(0),
                abi.encodeWithSelector(
                    MockPendleRouter.swapForPt.selector,
                    amount - initialDolaDeposit,
                    address(helper)
                )
            )
        );
        vm.stopPrank();

        uint256 lpAmount = SimpleERC20Escrow(userPkEscrow).balance();
        gibDBR(userPk, 20000 ether);

        uint maxBorrowAmount = _getMaxBorrowAmount(lpAmount);

        bytes memory swapData;

        ALE.DBRHelper memory dbrData;

        vm.startPrank(userPk);
        IERC20(address(pendlePT)).approve(address(ale), initialLpAmount);
        ale.depositAndLeveragePosition(
            initialLpAmount,
            maxBorrowAmount,
            address(market),
            address(0),
            swapData,
            _getPermitForBorrow(maxBorrowAmount),
            abi.encode(
                address(market),
                0,
                address(0),
                abi.encodeWithSelector(
                    MockPendleRouter.swapForPt.selector,
                    maxBorrowAmount,
                    address(helper)
                )
            ),
            dbrData,
            true
        );

        assertEq(DOLA.balanceOf(userPk), 0);
        assertEq(
            SimpleERC20Escrow(userPkEscrow).balance(),
            lpAmount + maxBorrowAmount + initialLpAmount
        );
    }

    function test_deleveragePosition_Redeem_with_PT_and_YT(
        uint256 lpAmount
    ) public {
        test_leveragePosition_Mint_PT_and_YT_with_DOLA();

        uint256 totalLpAmount = SimpleERC20Escrow(userPkEscrow).balance();
        vm.assume(lpAmount > 0.0001 ether);
        vm.assume(lpAmount <= totalLpAmount);
        uint256 amountToWithdraw = lpAmount / 2;

        ALE.DBRHelper memory dbrData;
        bytes memory swapData;

        uint256 ytBalBefore = IERC20(pendleYT).balanceOf(userPk);
        if (amountToWithdraw > ytBalBefore) {
            vm.prank(pendleYTHolder);
            IERC20(pendleYT).transfer(userPk, amountToWithdraw - ytBalBefore);
        }

        uint256 ytBalAfter = IERC20(pendleYT).balanceOf(userPk);
        vm.startPrank(userPk);
        IERC20(pendleYT).approve(address(helper), type(uint256).max);

        ale.deleveragePosition(
            amountToWithdraw / 2, // dola redeemed to be deleveraged
            address(market),
            amountToWithdraw,
            address(0),
            swapData,
            _getPermitWithdraw(amountToWithdraw),
            _encodeRedeem(amountToWithdraw),
            dbrData
        );

        assertEq(
            SimpleERC20Escrow(userPkEscrow).balance(),
            totalLpAmount - amountToWithdraw
        );
        assertApproxEqAbs(DOLA.balanceOf(userPk), amountToWithdraw / 2, 1);
        assertEq(
            IERC20(pendleYT).balanceOf(userPk),
            ytBalAfter - amountToWithdraw
        );
    }

    function test_deleveragePosition_Swap_PT_to_DOLA(uint256 lpAmount) public {
        test_leveragePosition_Swap_DOLA_for_PT();

        uint256 totalLpAmount = SimpleERC20Escrow(userPkEscrow).balance();
        vm.assume(lpAmount > 0.0001 ether);
        vm.assume(lpAmount <= totalLpAmount);
        uint256 amountToWithdraw = lpAmount / 2;

        ALE.DBRHelper memory dbrData;
        bytes memory swapData;

        vm.startPrank(userPk);
        ale.deleveragePosition(
            amountToWithdraw / 2, // dola redeemed to be deleveraged
            address(market),
            amountToWithdraw,
            address(0),
            swapData,
            _getPermitWithdraw(amountToWithdraw),
            _encodeSwapForDola(amountToWithdraw),
            dbrData
        );

        assertEq(
            SimpleERC20Escrow(userPkEscrow).balance(),
            totalLpAmount - amountToWithdraw
        );
        assertApproxEqAbs(DOLA.balanceOf(userPk), amountToWithdraw / 2, 1);
    }

    function test_deleveragePosition_sellDBR(uint256 lpAmount) public {
        test_leveragePosition_Swap_DOLA_for_PT();
        uint256 totalLpAmount = SimpleERC20Escrow(userPkEscrow).balance();
        vm.assume(lpAmount > 0.0001 ether);
        vm.assume(lpAmount <= totalLpAmount);
        uint256 amountToWithdraw = lpAmount;

        uint256 dolaRedeemed = amountToWithdraw;

        uint256 debt = market.debts(address(userPk));
        uint256 amountToRepay;
        if (debt < dolaRedeemed) {
            amountToRepay = debt;
        } else {
            amountToRepay = dolaRedeemed;
        }

        ALE.DBRHelper memory dbrData = ALE.DBRHelper(
            dbr.balanceOf(userPk),
            0,
            0
        ); // sell all DBR
        bytes memory swapData;

        vm.startPrank(userPk);
        dbr.approve(address(ale), dbr.balanceOf(userPk));
        ale.deleveragePosition(
            amountToRepay,
            address(market),
            amountToWithdraw,
            address(0),
            swapData,
            _getPermitWithdraw(amountToWithdraw),
            _encodeSwapForDola(amountToWithdraw),
            dbrData
        );

        assertEq(
            SimpleERC20Escrow(userPkEscrow).balance(),
            totalLpAmount - amountToWithdraw
        );
        // Dbrs have also been sold
        if (debt < dolaRedeemed) {
            // Dola left are more than the debt (plus the DBR sold)
            assertGt(DOLA.balanceOf(userPk), dolaRedeemed - amountToRepay);
        } else {
            // only DBR sold
            assertGt(DOLA.balanceOf(userPk), 0);
        }

        assertEq(dbr.balanceOf(userPk), 0);
    }

    function _transformAndDeposit(uint amount) internal {
        vm.startPrank(userPk, userPk);
        DOLA.approve(address(helper), amount);
        helper.transformToCollateralAndDeposit(
            amount,
            userPk,
            abi.encode(
                address(market),
                0,
                address(0),
                abi.encodeWithSelector(
                    MockPendleRouter.swapForPt.selector,
                    amount,
                    address(helper)
                )
            )
        );
        vm.stopPrank();
    }

    function _getPermitForBorrow(
        uint amount
    ) internal view returns (ALE.Permit memory permit) {
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
                        amount,
                        0,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, hash);

        permit = ALE.Permit(block.timestamp, v, r, s);
    }

    function _getPermitWithdraw(
        uint256 amountToWithdraw
    ) internal view returns (ALE.Permit memory permit) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            1,
            keccak256(
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
                            1,
                            block.timestamp
                        )
                    )
                )
            )
        );
        return ALE.Permit(block.timestamp, v, r, s);
    }

    function _encodeSwapForPT(
        uint amount
    ) internal view returns (bytes memory) {
        return
            abi.encode(
                address(market),
                0,
                address(0),
                abi.encodeWithSelector(
                    MockPendleRouter.swapForPt.selector,
                    amount,
                    address(helper)
                )
            );
    }

    function _encodeSwapForDola(
        uint amount
    ) internal view returns (bytes memory) {
        return
            abi.encode(
                address(market),
                uint(0),
                address(0),
                abi.encodeWithSelector(
                    MockPendleRouter.swapForDola.selector,
                    amount,
                    address(ale)
                )
            );
    }

    function _encodeMintPt(uint amount) internal view returns (bytes memory) {
        return
            abi.encode(
                address(market),
                0,
                address(userPk),
                abi.encodeWithSelector(
                    MockPendleRouter.mintPt.selector,
                    amount,
                    address(helper)
                )
            );
    }

    function _encodeRedeem(
        uint256 amount
    ) internal view returns (bytes memory) {
        return
            abi.encode(
                address(market),
                uint(0),
                userPk,
                abi.encodeWithSelector(
                    MockPendleRouter.redeemPt.selector,
                    amount,
                    address(ale)
                )
            );
    }

    function _getMaxBorrowAmount(
        uint amountCollat
    ) internal view returns (uint) {
        return
            (amountCollat *
                oracle.viewPrice(address(pendlePT), 0) *
                market.collateralFactorBps()) /
            10_000 /
            1e18;
    }
}
