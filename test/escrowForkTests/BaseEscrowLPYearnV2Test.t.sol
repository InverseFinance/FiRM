// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/escrows/LPCurveYearnV2Escrow.sol";
import {YearnVaultV2Helper} from "src/util/YearnVaultV2Helper.sol";
import {console} from "forge-std/console.sol";
import {RewardHook} from "test/mocks/RewardHook.sol";

//import {IYearnVaultV2} from "src/interfaces/IYearnVaultV2.sol";

interface DeployedHelper {
    function sharesToAmount(
        address vault,
        uint256 shares
    ) external view returns (uint256);
}

interface IExtraRewardStashV3 {
    function setExtraReward(address _token) external;

    function setRewardHook(address hook) external;

    function operator() external view returns (address);

    function stashRewards() external returns (bool);
}

interface IMintable is IERC20 {
    function mint(address to, uint256 amount) external;
}

interface IYearnVaultFactory {
    function createNewVaultsAndStrategies(
        address _gauge
    )
        external
        returns (
            address vault,
            address convexStrategy,
            address curveStrategy,
            address convexFraxStrategy
        );
}

abstract contract BaseEscrowLPYearnV2Test is Test {
    address market = address(0xA);
    address beneficiary = address(0xB);
    address friend = address(0xC);
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    IMintable dola = IMintable(0x865377367054516e17014CcdED1e7d814EDC9ce4);

    DeployedHelper deployedHelper =
        DeployedHelper(0x444443bae5bB8640677A8cdF94CB8879Fec948Ec);
    IYearnVaultFactory yearnFactory =
        IYearnVaultFactory(0x21b1FC8A52f179757bf555346130bF27c0C2A17A);

    address lpHolder;
    address yearnHolder;
    IERC20 curvePool;
    address gauge;

    IYearnVaultV2 yearn;

    LPCurveYearnV2Escrow escrow;

    struct YearnInfo {
        address vault;
        address yearnHolder;
    }

    function init(
        address _curvePool,
        address _lpHolder,
        address _gauge,
        YearnInfo memory _yearnInfo
    ) public {
        curvePool = IERC20(_curvePool);
        lpHolder = _lpHolder;
        gauge = _gauge;

        if (_yearnInfo.vault == address(0)) {
            // Setup YearnVault
            (address yearnVault, , , ) = yearnFactory
                .createNewVaultsAndStrategies(gauge);
            yearn = IYearnVaultV2(yearnVault);

            yearnHolder = address(0xD);

            vm.startPrank(lpHolder, lpHolder);
            curvePool.approve(yearnVault, type(uint256).max);
            yearn.deposit(1000000, yearnHolder);
            vm.stopPrank();
        } else yearn = IYearnVaultV2(_yearnInfo.vault);

        escrow = new LPCurveYearnV2Escrow(address(yearn));
        vm.prank(market, market);
        escrow.initialize(curvePool, beneficiary);
    }

    function test_initialize() public {
        LPCurveYearnV2Escrow freshEscrow = new LPCurveYearnV2Escrow(
            address(yearn)
        );
        vm.prank(address(market));
        freshEscrow.initialize(curvePool, lpHolder);
        assertEq(
            address(freshEscrow.market()),
            address(market),
            "Market not equal market"
        );
        assertEq(freshEscrow.beneficiary(), lpHolder, "Holder not beneficiary");
        assertEq(
            address(freshEscrow.token()),
            address(curvePool),
            "curvePool not Token"
        );
    }

    function test_depositToYearn_successful_when_contract_holds_CurveLP(
        uint256 amount
    ) public {
        vm.assume(amount > 1);
        vm.assume(amount < curvePool.balanceOf(lpHolder));

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);
        vm.prank(beneficiary, beneficiary);
        escrow.depositToYearn();

        assertApproxEqAbs(
            escrow.balance(),
            amount,
            2,
            "Escrow Balance is not correct"
        );
        assertApproxEqAbs(
            yearn.balanceOf(address(escrow)),
            YearnVaultV2Helper.assetToCollateral(yearn, amount),
            0,
            "Yearn Balance is not correct"
        );
    }

    function test_withdrawFromYearn_successful_if_deposited(
        uint amount
    ) public {
        vm.assume(amount > 1);
        vm.assume(amount < curvePool.balanceOf(lpHolder));
        uint256 maxDelta = 2;

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);

        vm.startPrank(beneficiary, beneficiary);
        escrow.depositToYearn();
        assertApproxEqAbs(
            deployedHelper.sharesToAmount(
                address(yearn),
                yearn.balanceOf(address(escrow))
            ),
            amount,
            maxDelta,
            "Helper from Wavey Balance is not correct"
        );
        assertApproxEqAbs(
            YearnVaultV2Helper.collateralToAsset(
                yearn,
                yearn.balanceOf(address(escrow))
            ),
            amount,
            maxDelta,
            "Helper Math is not correct"
        );
        escrow.withdrawFromYearn();
        assertApproxEqAbs(
            escrow.balance(),
            amount,
            maxDelta,
            "Escrow Balance is not correct"
        );

        assertEq(
            yearn.balanceOf(address(escrow)),
            0,
            "Yearn Balance is not correct"
        );
    }

    function test_withdrawFromYearn2_successful_if_deposited(
        uint256 amount
    ) public {
        // Test fuzz deposit to yearn, withdraw exact amount if expected calculated expected amount from yearn based on shares
        vm.assume(amount > 1);
        vm.assume(amount < curvePool.balanceOf(lpHolder));

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.depositToYearn();
        assertApproxEqAbs(
            deployedHelper.sharesToAmount(
                address(yearn),
                yearn.balanceOf(address(escrow))
            ),
            amount,
            2,
            "Helper from Wavey Balance is not correct"
        );
        assertApproxEqAbs(
            YearnVaultV2Helper.collateralToAsset(
                yearn,
                yearn.balanceOf(address(escrow))
            ),
            amount,
            2,
            "Helper Math is not correct"
        );

        vm.startPrank(address(market), address(market));
        escrow.pay(
            beneficiary,
            YearnVaultV2Helper.collateralToAsset(
                yearn,
                yearn.balanceOf(address(escrow))
            )
        );

        assertEq(
            yearn.balanceOf(address(escrow)),
            0,
            "Yearn Balance is not correct"
        );
    }

    function test_Pay_when_escrow_has_CurveLP_in_Yearn(uint256 amount) public {
        vm.assume(amount > 2);
        vm.assume(amount < curvePool.balanceOf(lpHolder));

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.depositToYearn();

        assertApproxEqAbs(
            escrow.balance(),
            amount,
            2,
            "Escrow Balance is not correct"
        );
        uint balanceBefore = escrow.balance();
        uint yearnBalBefore = YearnVaultV2Helper.collateralToAsset(
            yearn,
            yearn.balanceOf(address(escrow))
        );
        uint beneficiaryBalanceBefore = curvePool.balanceOf(beneficiary);

        vm.prank(market, market);
        uint256 withdrawAmount = amount / 2;
        escrow.pay(beneficiary, withdrawAmount);

        assertApproxEqAbs(
            escrow.balance(),
            balanceBefore - withdrawAmount,
            1,
            "Escrow Balance after is not correct"
        );
        assertApproxEqAbs(
            YearnVaultV2Helper.collateralToAsset(
                yearn,
                yearn.balanceOf(address(escrow))
            ),
            yearnBalBefore - withdrawAmount,
            2
        );
        assertEq(
            curvePool.balanceOf(beneficiary),
            beneficiaryBalanceBefore + withdrawAmount
        );
    }

    function test_Pay_partially_with_escrow_balance_when_escrow_has_CurveLP_in_Yearn(
        uint256 amount
    ) public {
        uint256 extraCurveLP = 1 ether;
        vm.assume(amount > 2);
        vm.assume(amount < curvePool.balanceOf(lpHolder) - extraCurveLP);

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);

        vm.prank(beneficiary, beneficiary);
        escrow.depositToYearn();

        // Send extra CurveLP to the escrow
        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), extraCurveLP);

        uint balanceBefore = escrow.balance();
        uint yearnBalBefore = YearnVaultV2Helper.collateralToAsset(
            yearn,
            yearn.balanceOf(address(escrow))
        );
        uint beneficiaryBalanceBefore = curvePool.balanceOf(beneficiary);

        vm.prank(market, market);
        uint256 withdrawAmount = amount / 2 + extraCurveLP;
        escrow.pay(beneficiary, withdrawAmount);

        assertApproxEqAbs(escrow.balance(), balanceBefore - withdrawAmount, 2);
        assertApproxEqAbs(
            YearnVaultV2Helper.collateralToAsset(
                yearn,
                yearn.balanceOf(address(escrow))
            ),
            yearnBalBefore - (amount / 2),
            2
        );
        assertEq(
            curvePool.balanceOf(beneficiary),
            beneficiaryBalanceBefore + withdrawAmount
        );
    }

    function test_Pay_ALL_when_donation_of_Yearn(uint amount) public {
        uint256 donationAmount = yearn.balanceOf(yearnHolder);
        vm.assume(amount > 1);
        vm.assume(amount < curvePool.balanceOf(lpHolder));

        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), amount);

        // Donate yearn to escrow
        vm.prank(yearnHolder, yearnHolder);
        IERC20(address(yearn)).transfer(address(escrow), donationAmount);

        uint256 lpFromDonation = YearnVaultV2Helper.collateralToAsset(
            yearn,
            yearn.balanceOf(address(escrow))
        );

        uint balanceBefore = escrow.balance();

        vm.prank(market, market);
        uint256 withdrawAmount = amount + lpFromDonation;
        escrow.pay(beneficiary, withdrawAmount);

        assertEq(escrow.balance(), balanceBefore - withdrawAmount);

        assertEq(yearn.balanceOf(address(escrow)), 0);
    }

    function test_Pay_fail_with_OnlyMarket_when_called_by_non_market() public {
        vm.prank(lpHolder, lpHolder);
        curvePool.transfer(address(escrow), 1 ether);
        vm.prank(beneficiary, beneficiary);
        escrow.depositToYearn();

        vm.prank(lpHolder, lpHolder);
        vm.expectRevert(LPCurveYearnV2Escrow.OnlyMarket.selector);
        escrow.pay(beneficiary, 1 ether);
    }
}
