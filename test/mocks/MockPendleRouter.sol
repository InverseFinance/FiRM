// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockPendleRouter {
    struct ApproxParams {
        uint256 guessMin;
        uint256 guessMax;
        uint256 guessOffchain;
        uint256 maxIteration;
        uint256 eps;
    }

    struct TokenInput {
        address tokenIn;
        uint256 netTokenIn;
        address tokenMintSy;
        address pendleSwap;
        SwapData swapData;
    }
    struct TokenOutput {
        address tokenOut;
        uint256 minTokenOut;
        address tokenRedeemSy;
        address pendleSwap;
        SwapData swapData;
    }

    struct LimitOrderData {
        address limitRouter;
        uint256 epsSkipMarket;
        FillOrderParams[] normalFills;
        FillOrderParams[] flashFills;
        bytes optData;
    }

    struct Order {
        uint256 salt;
        uint256 expiry;
        uint256 nonce;
        OrderType orderType;
        address token;
        address YT;
        address maker;
        address receiver;
        uint256 makingAmount;
        uint256 lnImpliedRate;
        uint256 failSafeRate;
        bytes permit;
    }

    enum OrderType {
        SY_FOR_PT,
        PT_FOR_SY,
        SY_FOR_YT,
        YT_FOR_SY
    }

    struct FillOrderParams {
        Order order;
        bytes signature;
        uint256 makingAmount;
    }

    struct SwapData {
        SwapType swapType;
        address extRouter;
        bytes extCalldata;
        bool needScale;
    }

    enum SwapType {
        NONE,
        KYBERSWAP,
        ODOS,
        // ETH_WETH not used in Aggregator
        ETH_WETH,
        OKX,
        ONE_INCH,
        RESERVE_1,
        RESERVE_2,
        RESERVE_3,
        RESERVE_4,
        RESERVE_5
    }
    IERC20 public DOLA;
    IERC20 public pendlePT;
    IERC20 public pendleYT;
    constructor(address _dola, address _pt, address _yt) {
        DOLA = IERC20(_dola);
        pendlePT = IERC20(_pt);
        pendleYT = IERC20(_yt);
    }
    function swapExactTokenForPt(
        address receiver,
        address /*market*/,
        uint256 minPtOut,
        ApproxParams calldata /*guessPtOut*/,
        TokenInput calldata /*input*/,
        LimitOrderData calldata /*limit*/
    ) external {
        DOLA.transferFrom(msg.sender, address(this), minPtOut);
        pendlePT.transfer(receiver, minPtOut);
    }

    function swapExactPtForToken(
        address receiver,
        address /*market*/,
        uint256 exactPtIn,
        TokenOutput calldata /*output*/,
        LimitOrderData calldata /*limit*/
    ) external {
        pendlePT.transferFrom(msg.sender, address(this), exactPtIn);
        DOLA.transfer(receiver, exactPtIn);
    }

    function mintPyFromToken(
        address receiver,
        address /*YT*/,
        uint256 minPyOut,
        TokenInput calldata /*input*/
    ) external {
        DOLA.transferFrom(msg.sender, address(this), minPyOut);
        pendlePT.transfer(receiver, minPyOut);
        pendleYT.transfer(receiver, minPyOut);
    }

    function redeemPyToToken(
        address receiver,
        address /*YT*/,
        uint256 netPyIn,
        TokenOutput calldata /*output*/
    ) external {
        pendlePT.transferFrom(msg.sender, address(this), netPyIn);
        pendleYT.transferFrom(msg.sender, address(this), netPyIn);
        DOLA.transfer(receiver, netPyIn);
    }
}
