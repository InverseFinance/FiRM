pragma solidity ^0.8.13;
import "forge-std/Script.sol";
import "../src/Market.sol";

contract SimpleERC20EscrowMarketDeploy is Script {
    
    address gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address lender = 0x2b34548b865ad66A2B046cb82e59eE43F75B90fd;
    address pauseGuardian = 0xE3eD95e130ad9E15643f5A5f232a3daE980784cd;
    address simpleErc20EscrowImplementation = 0xc06053FcAd0A0Df7cC32289A135bBEA9030C010f;
    IDolaBorrowRights dbr = IDolaBorrowingRights(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
    IOracle oracle = IOracle(0xaBe146CF570FD27ddD985895ce9B138a7110cce8);

    
    function run() external {
        address collateral = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        uint collateralFactorBps = 7000;
        uint replenishmentIncentiveBps = 5000;
        uint liquidationIncentiveBps = 1000;
        bool callOnDepositCallBack = false;

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);     

        Market market = new Market(
            gov,
            lender,
            pauseGuardian,
            simpleErc20EscrowImplementation,
            IDolaBorrowingRights dbr,
            IERC20(collateral),
            oracle,
            collateralFactorBps,
            replenishmentIncentiveBps,
            liquidationIncentiveBps,
            callOnDepositCallback
        );

        vm.stopBroadcast();
    }
}
