// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IMarket} from "src/interfaces/IMarket.sol";
import {Sweepable, SafeERC20, IERC20} from "src/util/Sweepable.sol";
import {IPendleHelper} from "src/interfaces/IPendleHelper.sol";

interface IPendlePT {
    function expiry() external view returns (uint256);
}
/**
 * @title Pendle PT ALE and market helper
 * @notice This contract is a generalized ALE and market helper contract for Pendle PT tokens from and to DOLA.
 * @dev Carefully prepare the router calldata from Pendle API when using it from the ALE:
 * When converting TO collateral, the receiver in Pendle API has to be set to this contract address
 * When converting FROM collateral, the receiver in Pendle API has to be set to the ALE address.
 * The Pendle Router can either SWAP DOLA for PT or MINT PT and YT as well SWAP PT for DOLA or REDEEM PT (using YT before maturity) for DOLA.
 * Do not use this contract for other routes otherwise won't work properly.
 **/

contract PendlePTHelper is Sweepable, IPendleHelper {
    using SafeERC20 for IERC20;

    error InsufficientDOLA();
    error InsufficientPT();
    error InsufficientYT();
    error MarketNotSet(address market);
    error PendleSwapFailed();
    error NotALE();
    error InvalidRecipient();
    error InvalidSelector();

    struct PT {
        address pt;
        address yt;
    }

    event MarketSet(
        address indexed market,
        address indexed pt,
        address indexed yt
    );
    event MarketRemoved(address indexed market);

    IERC20 public immutable DOLA;
    address public immutable router;
    address public immutable ale;

    /// @notice Mapping of market addresses to their associated PT and YT tokens.
    mapping(address => PT) public markets;

    bytes4 public constant SWAP_PT = hex"c81f847a";
    bytes4 public constant MINT_PT = hex"d0f42385";
    bytes4 public constant SWAP_DOLA = hex"594a88cc";
    bytes4 public constant REDEEM_PT = hex"47f1de22";

    /** @dev Constructor
    @param _gov The address of Inverse Finance governance
    @param _guardian The address of the guardian
    @param _pendleRouter The address of the Pendle Router
    **/
    constructor(
        address _gov,
        address _guardian,
        address _dola,
        address _pendleRouter,
        address _ale
    ) Sweepable(_gov, _guardian) {
        DOLA = IERC20(_dola);
        router = _pendleRouter;
        ale = _ale;
    }

    modifier onlyALE() {
        if (msg.sender != ale) revert NotALE();
        _;
    }
    /**
     * @notice Convert DOLA to PT or PT and YT
     * @dev Can only be used by the ALE. Carefully review input data for Pendle API.
     * The receiver in Pendle API has to be set to this contract address.
     * If a MINT is performed, YT will be sent to the msg.sender.
     * @param amount The amount of underlying token to be deposited.
     * @param data Encoded address of the market, minimum amount of PT to receive (and possibly YT), ytRecipient if minting, and Pendle callData.
     * @return collateralAmount The amount of PT (and possibly YT) token received.
     */
    function convertToCollateral(
        address user,
        uint256 amount,
        bytes calldata data
    ) external override onlyALE returns (uint256 collateralAmount) {
        return _convertToCollateral(user, amount, msg.sender, data);
    }

    /**
     * @notice Helper function to convert DOLA to PT or PT and YT, sending PT and YT to msg.sender (probably better using directly the Pendle Router for saving gas)
     * @dev The receiver in Pendle API has to be set to this contract address.
     * @param amount The amount of DOLA to be deposited.
     * @param data Encoded address of the market, minimum amount of PT to receive (and possibly YT), ytRecipient if minting, and Pendle callData.
     * @return collateralAmount The amount of PT (and possibly YT) token received.
     */
    function convertToCollateral(
        uint256 amount,
        bytes calldata data
    ) external override returns (uint256 collateralAmount) {
        return _convertToCollateral(msg.sender, amount, msg.sender, data);
    }

    /**
     * @notice Convert DOLA to PT or PT and YT and deposit PT amount on behalf of recipient, sending YT to the msg.sender
     * @dev The receiver in Pendle API has to be set to this contract address.
     * @param assets Amount of DOLA to be converted and deposited
     * @param recipient The address on behalf of which the PT tokens are deposited.
     * @param data The encoded address of the market.
     * @return collateralAmount The amount of collateral deposited into the market.
     */
    function convertToCollateralAndDeposit(
        uint256 assets,
        address recipient,
        bytes calldata data
    ) external override returns (uint256) {
        (address market, , ) = abi.decode(data, (address, uint256, bytes));

        // Convert DOLA to PT token
        uint256 amount = _convertToCollateral(
            msg.sender,
            assets,
            address(this),
            data
        );

        // Deposit PT into Market
        IERC20(markets[market].pt).approve(market, amount);
        IMarket(market).deposit(recipient, amount);

        return amount;
    }

    function _convertToCollateral(
        address user,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) internal returns (uint256 collateralAmount) {
        (
            address market,
            uint256 minOut, // Minimum amount of PT to receive (and possibly YT)
            bytes memory callData
        ) = abi.decode(data, (address, uint256, bytes));
        _revertIfMarketNotSet(market);

        bytes4 selector = getSelector(callData);
        if (selector != SWAP_PT && selector != MINT_PT)
            revert InvalidSelector();

        DOLA.safeTransferFrom(msg.sender, address(this), amount);
        DOLA.approve(router, amount);

        _callRouter(callData);

        IERC20 pt = IERC20(markets[market].pt);
        uint256 ptBal = pt.balanceOf(address(this));

        if (ptBal < minOut) revert InsufficientPT();
        if (recipient != address(this)) pt.safeTransfer(recipient, ptBal);

        if (selector == MINT_PT) {
            IERC20 yt = IERC20(markets[market].yt);
            // Send YT to user if minted
            uint256 ytBalMinted = yt.balanceOf(address(this));
            if (ytBalMinted < minOut) revert InsufficientYT();
            yt.safeTransfer(user, ytBalMinted);
        }

        return ptBal;
    }
    /**
     * @notice Redeems PT token for DOLA.
     * @dev Used by the ALE but can be called by anyone. Carefully review input data for Pendle API.
     * The receiver in Pendle API has to be set same as the recipient (ALE)
     * If a redemption is performed, ensure the user has enough balance and allowance for YT if before maturity
     * @param amount The amount of PT token to be redeemed (and YT if specified).
     * @param data Encoded address of the market, minimum amount of DOLA to receive, ytProvider, and Pendle callData.
     * @return dolaAmount The amount of DOLA redeemed.
     */
    function convertFromCollateral(
        address user,
        uint256 amount,
        bytes calldata data
    ) external override onlyALE returns (uint256 dolaAmount) {
        return _convertFromCollateral(user, amount, msg.sender, data);
    }

    /**
     * @notice Redeems Collateral for DOLA.
     * @dev The receiver in Pendle API has to be set same as the recipient. If a REDEEM is performed, include a ytProvider with enough allowance.
     * @param amount The amount of PT Token to be redeemed (and YT if specified).
     * @param recipient The address to which the underlying token is transferred.
     * @param data Encoded address of the market, minimum amount of DOLA to receive for the recipient, ytProvider, and Pendle callData.
     * @return dolaAmount The amount of DOLA redeemed.
     */
    function convertFromCollateral(
        uint256 amount,
        address recipient,
        bytes calldata data
    ) public override returns (uint256 dolaAmount) {
        return _convertFromCollateral(msg.sender, amount, recipient, data);
    }

    function _convertFromCollateral(
        address user,
        uint256 amount,
        address recipient,
        bytes calldata data
    ) internal returns (uint256 dolaAmount) {
        (
            address market,
            uint256 minOut, // Minimum amount of DOLA to receive
            bytes memory callData
        ) = abi.decode(data, (address, uint256, bytes));
        _revertIfMarketNotSet(market);

        bytes4 selector = getSelector(callData);
        if (selector != SWAP_DOLA && selector != REDEEM_PT)
            revert InvalidSelector();

        if (selector == REDEEM_PT) _handleYT(market, user, amount);

        IERC20 pt = IERC20(markets[market].pt);
        pt.safeTransferFrom(msg.sender, address(this), amount);
        pt.approve(router, amount);

        uint256 dolaBal = DOLA.balanceOf(recipient);

        _callRouter(callData);
        // Ensure recipient received at least minOut DOLA
        dolaAmount = DOLA.balanceOf(recipient) - dolaBal;
        if (dolaAmount < minOut) revert InsufficientDOLA();
    }

    /**
     * @notice Withdraw the collateral from the market then convert to DOLA.
     * @dev The receiver in Pendle API has to be set same as the recipient.
     * If a redemption is performed Before maturity, ensure msg.sender has enough balance and allowance for YT
     * @param amount The amount of PT token to be withdrawn from the market.
     * @param recipient The address to which DOLA is transferred.
     * @param permit The permit data for the Market.
     * @param data The encoded address of the market.
     * @return dolaAmount The amount of DOLA redeemed.
     */
    function withdrawAndConvertFromCollateral(
        uint256 amount,
        address recipient,
        Permit calldata permit,
        bytes calldata data
    ) external override returns (uint256 dolaAmount) {
        (address market, uint256 minOut, bytes memory callData) = abi.decode(
            data,
            (address, uint256, bytes)
        );
        _revertIfMarketNotSet(market);

        bytes4 selector = getSelector(callData);
        if (selector != SWAP_DOLA && selector != REDEEM_PT)
            revert InvalidSelector();

        if (selector == REDEEM_PT) _handleYT(market, msg.sender, amount);

        IMarket(market).withdrawOnBehalf(
            msg.sender,
            amount,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );

        IERC20 pt = IERC20(markets[market].pt);
        pt.approve(router, amount);

        uint256 dolaBal = DOLA.balanceOf(recipient);
        _callRouter(callData);

        dolaAmount = DOLA.balanceOf(recipient) - dolaBal;
        if (dolaAmount < minOut) revert InsufficientDOLA();
    }

    /**
     * @notice Call router.
     * @param pendleData to be called on the router.
     */
    function _callRouter(bytes memory pendleData) internal {
        (bool success, ) = router.call(pendleData);
        if (!success) revert PendleSwapFailed();
    }

    /**
     * @notice Handle YT, pulling it from the user and approving the router if before maturity
     * @param market The market address.
     * @param user The user address.
     * @param amount The amount of YT to handle.
     */
    function _handleYT(address market, address user, uint256 amount) internal {
        // Check if PT is not expired, in which case YT is not needed
        if (block.timestamp < IPendlePT(markets[market].pt).expiry()) {
            IERC20 yt = IERC20(markets[market].yt);
            if (yt.balanceOf(user) < amount) revert InsufficientYT();
            yt.safeTransferFrom(user, address(this), amount);
            yt.approve(router, amount);
        }
    }
    function _revertIfMarketNotSet(address market) internal view {
        if (address(markets[market].pt) == address(0))
            revert MarketNotSet(market);
    }

    /// ADMIN FUNCTIONS

    /**
     * @notice Set the market address and its associated Pendle PT and YT addresses.
     * @dev Only callable by the governance.
     * @param marketAddress The address of the market.
     * @param ptAddress Pendle PT address
     * @param ytAddress Pendle YT address
     */
    function setMarket(
        address marketAddress,
        address ptAddress,
        address ytAddress
    ) external onlyGov {
        markets[marketAddress] = PT({pt: ptAddress, yt: ytAddress});
        emit MarketSet(marketAddress, ptAddress, ytAddress);
    }

    /**
     * @notice Remove the market.
     * @dev Only callable by the governance or the guardian.
     * @param market The address of the market to be removed.
     */
    function removeMarket(address market) external onlyGuardianOrGov {
        delete markets[market];
        emit MarketRemoved(market);
    }

    /// UTILS
    function getSelector(bytes memory _bytes) internal pure returns (bytes4) {
        uint256 _start = 0;
        uint256 _length = 4;
        //require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        // Check length is 0. `iszero` return 1 for `true` and 0 for `false`.
        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // Calculate length mod 32 to handle slices that are not a multiple of 32 in size.
                let lengthmod := and(_length, 31)

                // tempBytes will have the following format in memory: <length><data>
                // When copying data we will offset the start forward to avoid allocating additional memory
                // Therefore part of the length area will be written, but this will be overwritten later anyways.
                // In case no offset is require, the start is set to the data region (0x20 from the tempBytes)
                // mc will be used to keep track where to copy the data to.
                let mc := add(
                    add(tempBytes, lengthmod),
                    mul(0x20, iszero(lengthmod))
                )
                let end := add(mc, _length)

                for {
                    // Same logic as for mc is applied and additionally the start offset specified for the method is added
                    let cc := add(
                        add(
                            add(_bytes, lengthmod),
                            mul(0x20, iszero(lengthmod))
                        ),
                        _start
                    )
                } lt(mc, end) {
                    // increase `mc` and `cc` to read the next word from memory
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    // Copy the data from source (cc location) to the slice data (mc location)
                    mstore(mc, mload(cc))
                }

                // Store the length of the slice. This will overwrite any partial data that
                // was copied when having slices that are not a multiple of 32.
                mstore(tempBytes, _length)

                // update free-memory pointer
                // allocating the array padded to 32 bytes like the compiler does now
                // To set the used memory as a multiple of 32, add 31 to the actual memory usage (mc)
                // and remove the modulo 32 (the `and` with `not(31)`)
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            // if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
                // zero out the 32 bytes slice we are about to return
                // we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                // update free-memory pointer
                // tempBytes uses 32 bytes in memory (even when empty) for the length.
                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return bytes4(tempBytes);
    }
}
