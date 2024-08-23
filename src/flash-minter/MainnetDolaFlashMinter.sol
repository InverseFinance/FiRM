//SPDX-License-Identifier: None
pragma solidity ^0.8.0;

import "./DolaFlashMinter.sol";

contract MainnetDolaFlashMinter is DolaFlashMinter {
    constructor()
        DolaFlashMinter(
            // Mainnet Dola
            0x865377367054516e17014CcdED1e7d814EDC9ce4,
            // Mainnet Inverse Treasury
            0x926dF14a23BE491164dCF93f4c468A50ef659D5B
        )
    // solhint-disable-next-line no-empty-blocks
    {

    }
}
