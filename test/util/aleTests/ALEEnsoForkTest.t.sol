// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BorrowController} from "src/BorrowController.sol";
import {DolaBorrowingRights} from "src/DBR.sol";
import {Market} from "src/Market.sol";
import {ALEV2} from "src/util/ALEV2.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IWETH is IERC20 {
    function deposit() external payable;
}

interface IUniswapV3Router {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

enum EnsoTokenType {
    Native,
    ERC20,
    ERC721,
    ERC1155
}

struct EnsoToken {
    EnsoTokenType tokenType;
    bytes data;
}

interface IEnsoRouter {
    function shortcuts() external view returns (address);

    function safeRouteSingle(
        EnsoToken calldata tokenIn,
        EnsoToken calldata tokenOut,
        address receiver,
        bytes calldata data
    ) external payable returns (bytes memory response);
}

interface IEnsoShortcuts {
    function executeShortcut(bytes32 accountId, bytes32 requestId, bytes32[] calldata commands, bytes[] calldata state)
        external
        payable
        returns (bytes[] memory response);
}

contract ALEEnsoForkTest is Test {
    address internal constant GOV = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address internal constant ALE = 0x4dF2EaA1658a220FDB415B9966a9ae7c3d16e240;
    address internal constant WETH_MARKET = 0x63Df5e23Db45a2066508318f172bA45B9CD37035;

    address internal constant ENSO_ROUTER = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
    address internal constant UNISWAP_V3_ROUTER = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    address internal constant DOLA = 0x865377367054516e17014CcdED1e7d814EDC9ce4;
    address internal constant DBR = 0xAD038Eb671c44b853887A7E32528FaB35dC5D710;
    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 internal constant USER_PRIVATE_KEY = 1;
    uint256 internal constant INITIAL_DEPOSIT = 1 ether;
    uint256 internal constant DOLA_TO_LEVERAGE = 0.1 ether;
    uint256 internal constant MIN_WETH_OUT = 0.00001 ether;
    uint256 internal constant WETH_TO_DELEVERAGE = 0.0002 ether;
    uint256 internal constant MIN_DOLA_OUT = DOLA_TO_LEVERAGE;

    ALEV2 internal constant ale = ALEV2(payable(ALE));
    Market internal constant market = Market(WETH_MARKET);

    address internal user;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        user = vm.addr(USER_PRIVATE_KEY);

        vm.startPrank(GOV);
        // Enso-specific ALE configuration.
        ale.allowProxy(ENSO_ROUTER);
        ale.setMarket(WETH_MARKET, WETH, address(0), true);

        // The current controller also needs to permit ALE as a contract caller.
        // Keep the test trade small by lowering the fork-only minimum debt.
        BorrowController borrowController = BorrowController(address(market.borrowController()));
        borrowController.allow(ALE);
        borrowController.setMinDebt(WETH_MARKET, 1);
        vm.stopPrank();

        assertTrue(ale.isExchangeProxy(ENSO_ROUTER));
        (,,, bool useProxy) = ale.markets(WETH_MARKET);
        assertTrue(useProxy);
        assertTrue(borrowController.contractAllowlist(ALE));
    }

    function test_ensoRouterV2_depositAndLeverageAfterGovernanceSetup() public {
        _fundUser();

        ALEV2.Permit memory permit = _signBorrowPermit(DOLA_TO_LEVERAGE);
        bytes memory ensoCallData = _buildEnsoDolaToWethRoute(DOLA_TO_LEVERAGE);
        ALEV2.DBRHelper memory noDbrSwap;

        uint256 collateralBefore = IERC20(WETH).balanceOf(address(market.predictEscrow(user)));
        uint256 debtBefore = market.debts(user);
        address ensoShortcuts = IEnsoRouter(ENSO_ROUTER).shortcuts();
        uint256 ensoDolaBefore = IERC20(DOLA).balanceOf(ensoShortcuts);

        vm.startPrank(user);
        IERC20(WETH).approve(ALE, INITIAL_DEPOSIT);
        ale.depositAndLeveragePosition(
            INITIAL_DEPOSIT,
            DOLA_TO_LEVERAGE,
            WETH_MARKET,
            ENSO_ROUTER,
            ensoCallData,
            permit,
            bytes(""),
            noDbrSwap,
            true
        );
        vm.stopPrank();

        uint256 collateralAfter = IERC20(WETH).balanceOf(address(market.predictEscrow(user)));

        assertGt(
            collateralAfter,
            collateralBefore + INITIAL_DEPOSIT,
            "Enso output was not deposited as additional collateral"
        );
        assertEq(
            market.debts(user),
            debtBefore + DOLA_TO_LEVERAGE,
            "ALE did not borrow the flash-loan principal on behalf of the user"
        );
        assertEq(IERC20(DOLA).balanceOf(ALE), 0, "ALE retained DOLA after flash-loan repayment");
        assertEq(IERC20(WETH).balanceOf(ALE), 0, "ALE retained WETH instead of depositing it");
        assertEq(IERC20(DOLA).balanceOf(ensoShortcuts), ensoDolaBefore, "Enso retained part of ALE's DOLA input");
    }

    function test_ensoRouterV2_deleverageAfterGovernanceSetup() public {
        _openBorrowPosition();

        ALEV2.Permit memory permit = _signWithdrawPermit(WETH_TO_DELEVERAGE);
        bytes memory ensoCallData = _buildEnsoWethToDolaRoute(WETH_TO_DELEVERAGE);
        ALEV2.DBRHelper memory noDbrSwap;

        address escrow = address(market.predictEscrow(user));
        address ensoShortcuts = IEnsoRouter(ENSO_ROUTER).shortcuts();
        uint256 collateralBefore = IERC20(WETH).balanceOf(escrow);
        uint256 userDolaBefore = IERC20(DOLA).balanceOf(user);
        uint256 ensoWethBefore = IERC20(WETH).balanceOf(ensoShortcuts);

        assertEq(market.debts(user), DOLA_TO_LEVERAGE);

        vm.prank(user);
        ale.deleveragePosition(
            DOLA_TO_LEVERAGE, WETH_MARKET, ENSO_ROUTER, WETH_TO_DELEVERAGE, ensoCallData, permit, bytes(""), noDbrSwap
        );

        assertEq(market.debts(user), 0, "ALE did not repay the user's debt");
        assertEq(
            IERC20(WETH).balanceOf(escrow),
            collateralBefore - WETH_TO_DELEVERAGE,
            "ALE did not withdraw the requested collateral"
        );
        assertGt(IERC20(DOLA).balanceOf(user), userDolaBefore, "ALE did not refund excess Enso output to the user");
        assertEq(IERC20(DOLA).balanceOf(ALE), 0, "ALE retained DOLA after flash-loan repayment");
        assertEq(IERC20(WETH).balanceOf(ALE), 0, "ALE retained WETH after the Enso swap");
        assertEq(IERC20(WETH).balanceOf(ensoShortcuts), ensoWethBefore, "Enso retained part of ALE's WETH input");
    }

    function _fundUser() internal {
        vm.deal(user, INITIAL_DEPOSIT);
        vm.prank(user);
        IWETH(WETH).deposit{value: INITIAL_DEPOSIT}();

        vm.prank(GOV);
        DolaBorrowingRights(DBR).mint(user, 1_000 ether);
    }

    function _openBorrowPosition() internal {
        _fundUser();

        ALEV2.Permit memory permit = _signBorrowPermit(DOLA_TO_LEVERAGE);
        bytes memory ensoCallData = _buildEnsoDolaToWethRoute(DOLA_TO_LEVERAGE);
        ALEV2.DBRHelper memory noDbrSwap;

        vm.startPrank(user);
        IERC20(WETH).approve(ALE, INITIAL_DEPOSIT);
        ale.depositAndLeveragePosition(
            INITIAL_DEPOSIT,
            DOLA_TO_LEVERAGE,
            WETH_MARKET,
            ENSO_ROUTER,
            ensoCallData,
            permit,
            bytes(""),
            noDbrSwap,
            true
        );
        vm.stopPrank();
    }

    function _signBorrowPermit(uint256 amount) internal view returns (ALEV2.Permit memory permit) {
        uint256 deadline = block.timestamp;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("BorrowOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"),
                ALE,
                user,
                amount,
                market.nonces(user),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", market.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PRIVATE_KEY, digest);
        permit = ALEV2.Permit({deadline: deadline, v: v, r: r, s: s});
    }

    function _signWithdrawPermit(uint256 amount) internal view returns (ALEV2.Permit memory permit) {
        uint256 deadline = block.timestamp;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "WithdrawOnBehalf(address caller,address from,uint256 amount,uint256 nonce,uint256 deadline)"
                ),
                ALE,
                user,
                amount,
                market.nonces(user),
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", market.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_PRIVATE_KEY, digest);
        permit = ALEV2.Permit({deadline: deadline, v: v, r: r, s: s});
    }

    function _buildEnsoDolaToWethRoute(uint256 amountIn) internal pure returns (bytes memory) {
        return _buildEnsoRoute(
            DOLA,
            WETH,
            amountIn,
            MIN_WETH_OUT,
            abi.encodePacked(DOLA, uint24(3_000), USDC, uint24(500), WETH),
            keccak256("ALE_ENSO_LEVERAGE_FORK_TEST")
        );
    }

    function _buildEnsoWethToDolaRoute(uint256 amountIn) internal pure returns (bytes memory) {
        return _buildEnsoRoute(
            WETH,
            DOLA,
            amountIn,
            MIN_DOLA_OUT,
            abi.encodePacked(WETH, uint24(500), USDC, uint24(3_000), DOLA),
            keccak256("ALE_ENSO_DELEVERAGE_FORK_TEST")
        );
    }

    function _buildEnsoRoute(
        address tokenInAddress,
        address tokenOutAddress,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes memory path,
        bytes32 requestId
    ) internal pure returns (bytes memory) {
        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](2);

        state[0] = abi.encodeCall(IERC20.approve, (UNISWAP_V3_ROUTER, amountIn));
        commands[0] = _ensoCallCommand(IERC20.approve.selector, 0, tokenInAddress);

        IUniswapV3Router.ExactInputParams memory swapParams = IUniswapV3Router.ExactInputParams({
            path: path, recipient: ALE, amountIn: amountIn, amountOutMinimum: minAmountOut
        });
        state[1] = abi.encodeCall(IUniswapV3Router.exactInput, (swapParams));
        commands[1] = _ensoCallCommand(IUniswapV3Router.exactInput.selector, 1, UNISWAP_V3_ROUTER);

        bytes memory shortcutCallData =
            abi.encodeCall(IEnsoShortcuts.executeShortcut, (bytes32(0), requestId, commands, state));

        EnsoToken memory tokenIn =
            EnsoToken({tokenType: EnsoTokenType.ERC20, data: abi.encode(tokenInAddress, amountIn)});
        EnsoToken memory tokenOut =
            EnsoToken({tokenType: EnsoTokenType.ERC20, data: abi.encode(tokenOutAddress, minAmountOut)});

        return abi.encodeCall(IEnsoRouter.safeRouteSingle, (tokenIn, tokenOut, ALE, shortcutCallData));
    }

    function _ensoCallCommand(bytes4 selector, uint8 stateIndex, address target) internal pure returns (bytes32) {
        // Enso Weiroll command layout:
        // selector (4) | CALL + FLAG_DATA (1) | state index (1) |
        // output/unused (6) | target (20).
        return bytes32(abi.encodePacked(selector, uint8(0x21), stateIndex, bytes6(0), target));
    }
}
