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
    // Inverse Feeds
    address styEthFeedAddr =
        address(0xbBE5FaBbB55c2c79ae1efE6b5bd52048A199e166);
    address sFraxFeedAddr = address(0x90787a14B3D30E4865C9cF7b61B6FC04533A5F48);

    // Assets
    address sFraxAddr = address(0xA663B02CF0a4b149d2aD41910CB81e23e1c41c32);
    address fraxAddr = address(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    address styEthAddr = address(0x583019fF0f430721aDa9cfb4fac8F06cA104d0B4);
    address yEthAddr = address(0x1BED97CBC3c24A4fb5C069C6E311a967386131f7);

    // FiRM Markets
    address crvMarketAddr = address(0x63fAd99705a255fE2D500e498dbb3A9aE5AA1Ee8);
    address sFraxMarketAddr =
        address(0xFEA3A862eE4b3F9b6015581d6d2D25AF816C54f1);
    address styEthMarketAddr =
        address(0x0c0bb843FAbda441edeFB93331cFff8EC92bD168);

    // Chainlink
    address crvUsdFeedAddr =
        address(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f);
    address fraxUsdFeedAddr =
        address(0xB9E1E3A9feFf48998E45Fa90847ed4D467E8BcfD);

    // Curve Pools
    address triDBRAddr = address(0xC7DE47b9Ca2Fc753D6a2F167D8b3e19c6D18b19a);
    // Balancer Pools
}
