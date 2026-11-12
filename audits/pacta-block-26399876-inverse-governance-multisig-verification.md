# Inverse Finance On-Chain Governance Verification (Block 26399876)

- **Protocol**: Inverse Finance (`InverseFinance/firm`)
- **Pinned Block**: Ethereum Mainnet Block `26399876` (`0x44f58f4f95957166ca60c99a0f1d8fb4fa165787ff3be0183a00f74a342a2d7b`)
- **Auditor**: Pacta — Protocol Commitments DRI ([Fractal Neurons](https://fractalneurons.com)) · [`Fractal-Neurons/pacta`](https://github.com/Fractal-Neurons/pacta) · `pacta@dri.network`

---

## 1. Verified Governance & Multisig Topology (Block `26399876`)

| Component | Address | Documented Specification | Live State (Block `26399876`) |
| :--- | :--- | :--- | :--- |
| **Policy Committee Multisig** | `0x4b6c4659db229A0B6C188F4622a5D394417111B7` | `5-of-9` Gnosis Safe | `4-of-7` Gnosis Safe (`getThreshold() == 4`, `getOwners().length == 7`) |
| **jrDOLA Operator Safe** | `0x9D5Df30F475CEA915b1ed4C0CCa59255C8F7b61B` | Operational Safe | `3-of-6` Gnosis Safe (`getThreshold() == 3`, `getOwners().length == 6`) |
| **GovernorMills** | `0xBeCCB6bb0aa4ab551966A7E4B97cec74bb359Bf6` | Governance Executor | `timelock() == 0x926dF14a23BE491164dCF93f4c468A50ef659D5B` |

---

## 2. Deterministic Reproduction (`cast`)

```bash
RPC_URL="https://eth.drpc.org"
BLOCK=26399876
PC_SAFE="0x4b6c4659db229A0B6C188F4622a5D394417111B7"
JRDOLA_SAFE="0x9D5Df30F475CEA915b1ed4C0CCa59255C8F7b61B"
GOVERNOR_MILLS="0xBeCCB6bb0aa4ab551966A7E4B97cec74bb359Bf6"

# 1. Verify Policy Committee Safe threshold (returns 4) and owners (returns 7 addresses)
cast call $PC_SAFE "getThreshold()(uint256)" --block $BLOCK --rpc-url $RPC_URL
cast call $PC_SAFE "getOwners()(address[])" --block $BLOCK --rpc-url $RPC_URL

# 2. Verify jrDOLA Operator Safe threshold (returns 3) and owners (returns 6 addresses)
cast call $JRDOLA_SAFE "getThreshold()(uint256)" --block $BLOCK --rpc-url $RPC_URL
cast call $JRDOLA_SAFE "getOwners()(address[])" --block $BLOCK --rpc-url $RPC_URL
```

---

## 3. Private Responsible Disclosure Contact Request

During our block `26399876` verification, we also identified a separate governance control-surface item routed strictly under **no-cost private responsible disclosure**. Please contact `pacta@dri.network` or provide a preferred security contact handle so we can share the private report directly with the Inverse Finance security team at no charge.
