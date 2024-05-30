// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
//import "../BorrowController.sol";
import "../DBR.sol";
import {IOracle} from "../Market.sol";
import {ALE} from "../util/ALE.sol";
import {ITransformHelper} from "src/interfaces/ITransformHelper.sol";
import {console} from "forge-std/console.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {ConfigAddr} from "src/test/ConfigAddr.sol";
import {BaseHelper} from "src/util/BaseHelper.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {Governable} from "src/util/Governable.sol";

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

abstract contract BaseHelperForkTest is Test, ConfigAddr {
    using stdStorage for StdStorage;

    BaseHelper base;

    function getBlockNumber() public view virtual returns (uint256) {
        return 19084238; // Random block number
    }

    function setUp() public virtual {
        string memory url = vm.rpcUrl("mainnet");
        vm.createSelectFork(url, getBlockNumber());
    }

    function initBase(address helper) public {
        base = BaseHelper(helper);
    }

    function test_setPendingGov() public {
        address newGov = address(this);
        assertEq(base.gov(), gov);
        assertEq(base.pendingGov(), address(0));

        vm.startPrank(gov);
        base.setPendingGov(address(this));
        assertEq(base.pendingGov(), address(this));
        assertEq(base.gov(), gov);

        vm.expectRevert(
            abi.encodeWithSelector(Governable.NotPendingGov.selector)
        );
        base.claimPendingGov();
        vm.stopPrank();

        base.claimPendingGov();
        assertEq(base.gov(), newGov);
        assertEq(base.pendingGov(), address(0));
    }

    function test_setGuardian() public {
        address newGuardian = address(this);
        assertEq(base.guardian(), pauseGuardian);

        vm.prank(gov);
        base.setGuardian(newGuardian);
        assertEq(base.guardian(), newGuardian);

        vm.expectRevert(abi.encodeWithSelector(Governable.NotGov.selector));
        base.setGuardian(newGuardian);
    }

    function test_sweep() public {
        uint256 amount = 100 ether;

        deal(fraxAddr, address(base), amount);
        deal(dolaAddr, address(base), amount);

        assertEq(IERC20(fraxAddr).balanceOf(address(base)), amount);
        assertEq(IERC20(dolaAddr).balanceOf(address(base)), amount);

        uint256 govBalFrax = IERC20(fraxAddr).balanceOf(gov);
        uint256 govBalDola = IERC20(dolaAddr).balanceOf(gov);

        vm.prank(gov);
        base.sweep(fraxAddr);

        assertEq(IERC20(fraxAddr).balanceOf(address(base)), 0);
        assertEq(IERC20(dolaAddr).balanceOf(address(base)), amount);
        assertEq(IERC20(fraxAddr).balanceOf(gov), govBalFrax + amount);

        vm.expectRevert(abi.encodeWithSelector(Governable.NotGov.selector));
        base.sweep(dolaAddr);

        vm.prank(gov);
        base.sweep(dolaAddr);
        assertEq(IERC20(dolaAddr).balanceOf(address(base)), 0);
        assertEq(IERC20(dolaAddr).balanceOf(gov), govBalDola + amount);
    }
}
