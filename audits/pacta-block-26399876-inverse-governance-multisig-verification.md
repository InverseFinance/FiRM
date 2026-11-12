# Inverse Finance On-Chain Governance Verification (Block 26399876)

- **Protocol**: Inverse Finance (`InverseFinance/firm`)
- **Pinned Block**: Ethereum Mainnet Block `26399876` (`0x44f58f4f95957166ca60c99a0f1d8fb4fa165787ff3be0183a00f74a342a2d7b`)
- **Auditor**: Pacta — Protocol Commitments DRI ([Fractal Neurons](https://fractalneurons.com)) · [`Fractal-Neurons/pacta`](https://github.com/Fractal-Neurons/pacta) · `pacta@dri.network`

---

## 1. Summary of Publicly Revealed Finding (Policy Committee Safe Threshold & Signer Drift)

Inverse Finance governance documentation specifies that the **Policy Committee Multisig** (`0x9D5Df30F475CEA915b1ed4C0CCa59255C8F7b61B`) is configured as a **5-of-9** Gnosis Safe.

At pinned Ethereum mainnet block `26399876`, the live `0x9D5Df30F475CEA915b1ed4C0CCa59255C8F7b61B` Gnosis Safe is configured on-chain as a **4-of-7** multisig (`getThreshold() == 4`, `getOwners().length == 7`).

---

## 2. Deterministic Reproduction (`cast`)

```bash
RPC_URL="https://eth.drpc.org"
BLOCK=26399876
PC_SAFE="0x9D5Df30F475CEA915b1ed4C0CCa59255C8F7b61B"
GOVERNOR_MILLS="0xBeCCB6bb0aa4ab551966A7E4B97cec74bb359Bf6"
TIMELOCK="0x926dF14a23BE491164dCF93f4c468A50ef659D5B"

# 1. Verify Policy Committee Safe threshold (returns 4) and owners (returns 7 addresses)
cast call $PC_SAFE "getThreshold()(uint256)" --block $BLOCK --rpc-url $RPC_URL
cast call $PC_SAFE "getOwners()(address[])" --block $BLOCK --rpc-url $RPC_URL

# 2. Verify GovernorMills timelock and guardian wiring
cast call $GOVERNOR_MILLS "timelock()(address)" --block $BLOCK --rpc-url $RPC_URL
cast call $GOVERNOR_MILLS "guardian()(address)" --block $BLOCK --rpc-url $RPC_URL
```

---

## 3. Restricted Security Disclosure Notice (`I3` — `GovernorMills` Emergency Cancel Path)

During the same block-pinned audit (`26399876`), we verified a second, security-sensitive finding (`I3`) concerning the `GovernorMills` (`0xBeCCB6bb0aa4ab551966A7E4B97cec74bb359Bf6`) emergency proposal cancellation guardian contract and single-wallet veto capability. Under our responsible-disclosure quarantine policy, the execution trace and EOA address are withheld from this public file diff and ready for immediate private handoff to the Inverse Finance core team (`pacta@dri.network`).
