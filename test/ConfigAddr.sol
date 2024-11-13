// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract ConfigAddr {
    // Inverse
    address gov = address(0x926dF14a23BE491164dCF93f4c468A50ef659D5B);
    address chair = address(0x8F97cCA30Dbe80e7a8B462F1dD1a51C32accDfC8);
    address pauseGuardian = address(0xE3eD95e130ad9E15643f5A5f232a3daE980784cd);
    address dolaAddr = address(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    address dbrAddr = address(0xAD038Eb671c44b853887A7E32528FaB35dC5D710);
    address oracleAddr = address(0xaBe146CF570FD27ddD985895ce9B138a7110cce8);
    address borrowControllerAddr =
        address(0x44B7895989Bc7886423F06DeAa844D413384b0d6);
    address fedAddr = address(0x2b34548b865ad66A2B046cb82e59eE43F75B90fd);

    // Mainnet Dola Flash Minter
    address flashMinterAddr =
        address(0x6C5Fdc0c53b122Ae0f15a863C349f3A481DE8f1F);

    // ALE
    address aleAddr = address(0x5233f4C2515ae21B540c438862Abb5603506dEBC);

    // Inverse Feeds
    address styEthFeedAddr =
        address(0xbBE5FaBbB55c2c79ae1efE6b5bd52048A199e166);
    address sFraxFeedAddr = address(0x90787a14B3D30E4865C9cF7b61B6FC04533A5F48);
    address yvyCRVFeedAddr =
        address(0xfc63C9c8Ba44AE89C01265453Ed4F427C80cBd4E);
    // Assets
    address sFraxAddr = address(0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32);
    address fraxAddr = address(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    address styEthAddr = address(0x583019fF0f430721aDa9cfb4fac8F06cA104d0B4);
    address yEthAddr = address(0x1BED97CBC3c24A4fb5C069C6E311a967386131f7);
    address yvyCRVAddr = address(0x27B5739e22ad9033bcBf192059122d163b60349D);

    // FiRM Markets
    address crvMarketAddr = address(0x63fAd99705a255fE2D500e498dbb3A9aE5AA1Ee8);
    address sFraxMarketAddr =
        address(0xFEA3A862eE4b3F9b6015581d6d2D25AF816C54f1);
    address styEthMarketAddr =
        address(0x0c0bb843FAbda441edeFB93331cFff8EC92bD168);
    address crvUSDDolaConvexAddr =
        address(0x6A522f3BD3fDA15e74180953f203cf55aA6C631E);
    address crvUSDDolaYearnAddr =
        address(0xe85943e280776254ee6C9801553B93F10Ef4C99C);
    address yvyCRVMarketAddr =
        address(0x27b6c301Fd441f3345d61B7a4245E1F823c3F9c4);

    // Chainlink
    address crvUsdFeedAddr =
        address(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f);
    address fraxUsdFeedAddr =
        address(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);

    // Curve Pools
    address triDBRAddr = address(0xC7DE47b9Ca2Fc753D6a2F167D8b3e19c6D18b19a);
    // Balancer Pools

    // FiRM Escrows
    address simpleERC20EscrowAddr =
        address(0xc06053FcAd0A0Df7cC32289A135bBEA9030C010f);
    address crvUSDDolaConvexEscrowAddr =
        0xCB21Dc82C4346cE448808A8B9C51719F13cE00c3;
    address dolaFraxBPConvexEscrowAddr =
        0xF28cCAAeB90BbE1463eb82716Fc50330084DDFf6;
    address dolaFraxPyUSDConvexEscrowAddr =
        0xfF7ec7ACA4f9e0a346e78fcCef8F41435522bA44;

    // Wrappers
    address baseFraxToUsdAddr =
        address(0xc39e4D6558dc7AA4F6457261413B4479b256572C); // ChainlinkBasePriceFeed for Frax to USD (Chainlink wrapper)

    // Inverse feeds after redesign
    // CurveLPSingleFeed for CrvUSD/Dola
    address crvUSDFallbackAddr =
        address(0x92B57f41e90F8320EADdfCF22BB8AF45b0E5ed4E); // ChainlinkCurve2CoinsFeed for CrvUSD fallback (via USDC)
    address mainCrvUSDFeedAddr =
        address(0xD78527F9853da96FEbc4aF423527309810b83Ec1); // ChainlinkBasePriceFeed for main CrvUSD (has CrvUSD fallback)
    address crvUSDDolaFeedAddr =
        address(0x948E3435Ad0e269fDAf6259D4fb6380116Cfd366); // CurveLPSingleFeed for CrvUSD/Dola (uses mainCrvUSDFeed)

    // CurveLPPessimisticFeed for DolaFraxBP
    address baseCrvUsdToUsdAddr =
        address(0x7325f9950544565Bd4Fd8F7b6FF732c19ffE6284); // ChainlinkBasePriceFeed for CrvUSD to USD (Chainlink wrapper)
    address fraxFallbackAddr =
        address(0x80B3Dc93B47865f7F31325D409587e2BE55F6B21); // ChainlinkCurve2CoinsFeed for Frax fallback
    address baseEthToUsdAddr =
        address(0x518f4Dd603A150fE7b6E89e8E18213aE2e909599); // ChainlinkBasePriceFeed for ETH to USD (Chainlink wrapper)
    address usdcFallbackAddr =
        address(0x9d2ed98AC6e72Fc826407F9DE01c8725657B93A2); // ChainlinkCurveFeed for USDC fallback
    address mainFraxFeedAddr =
        address(0x9b71bD6144C63EC08e876a1417fbBf58a125276d); // ChainlinkBasePriceFeed for main Frax (has Frax fallback)
    address mainUsdcFeedAddr =
        address(0xA5C063be4B5686Ea0B7B36F2ca9d0aF056a97f0C); // ChainlinkBasePriceFeed for main USDC (has USDC fallback)
    address dolaFraxBPFeedAddr =
        address(0x8798B5BD990e70c5C7107e9C1572954EB1158ACE); // CurveLPPessimisticFeed for DolaFraxBP (uses mainFraxFeed and mainUsdcFeed)

    // CurveLPPessimisticFeed for DolaFraxPyUSD
    address baseUsdcToUsdAddr =
        address(0xc193409C9437C96146018dec6c650a9ab32C9117); // ChainlinkBasePriceFeed for USDC to USD (Chainlink wrapper)
    address pyUSDFallbackAddr =
        address(0x6ef8aDb728e1323F1d7cd762A32d9effcfecbc65); // ChainlinkCurveFeed for PyUSD fallback
    address mainPyUSDFeedAddr =
        address(0xb805252D0f95D9c67a405C895419cF1Fb03B4015); // ChainlinkBasePriceFeed for main PyUSD (has PyUSD fallback)
    address dolaFraxPyUSDFeedAddr =
        address(0x3fF3A76A77c6FB743ebf2e397C082faD1D7ad955); // CurveLPPessimisticFeed for DolaFraxPyUSD (uses mainFraxFeed and mainPyUSDFeed)

    // CurveLPYearnV2Feed for CrvUSD/Dola
    address yearnCrvUSDDolaFeedAddr =
        address(0x9128cE78a940B1a32Aee76C1c848658C465ba98A); // CurveLPYearnV2Feed for CrvUSD/Dola (use crvUSD/Dola LP feed)

    // CurveLPYearnV2Feed for DolaFraxBP
    address yearnDolaFraxBPFeedAddr =
        address(0x85f86F9e2dCc370c90d3a7bFC2B8E9a970D84850); // CurveLPYearnV2Feed for DolaFraxBP (use DolaFraxBP LP feed)

    // CurveDolaLPHelper
    address curveDolaLPHelperAddr =
        address(0x6c592Fe4deA245B296476fd72863E8b2B739f911); // Helper for entering and exiting curve pools with Dola. Also support YearnV2 vaults for this LP.
}
