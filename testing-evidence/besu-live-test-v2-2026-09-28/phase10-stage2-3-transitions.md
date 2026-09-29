# Phase 10, Stages 2-3 — transitions.qbft technical mechanism, real Besu test

First real test of this technique against a live Besu network for this project (per the
governance doc's own note that it was "not yet tested on real Besu").

## Setup
At block 2172 (chain running normally, 4 active validators: validator1, validator2, validator3,
candidateA), stopped **all 15** Besu nodes and edited the single shared `genesis.json`'s `config`
to add:
```json
"transitions": {
  "qbft": [
    { "block": 2200, "validatorselectionmode": "blockheader", "validators": [<the same 4 addresses>] },
    { "block": 2230, "validatorselectionmode": "contract", "validatorcontractaddress": "0x3333...3333" }
  ]
}
```
Deliberately used the *same* 4 addresses for the temporary `blockheader` list as were already
`contract`-mode-active, both because they were the only validators genuinely online at the time and
to isolate "does the mechanism work at all" from "does it work with a different validator set" —
the latter wasn't needed to answer the question this test cares about.

Restarted all 15 nodes. Adding `transitions` to `config` does not change the genesis block's own
hash (block-hash-relevant fields — `alloc`, `extraData`, `difficulty`, `gasLimit`, `timestamp` —
were untouched; `config` is client-side interpretation only), so all nodes resumed from their
existing chain data without any resync or fork.

## Result: both transitions fired exactly as configured, zero chain halt

Confirmed via explicit Besu log lines (not inferred):
```
[block ~2200] ValidatorModeTransitionLogger | Transitioning validator selection mode from contract (address: 0x3333...3333) to blockheader
[block ~2230] ValidatorModeTransitionLogger | Transitioning validator selection mode from blockheader to contract (address: 0x3333...3333)
```
Block production never stopped through either transition — height progressed continuously
(2172 → 2206 → 2236+) at the normal ~3s cadence throughout.

## Result: contract state fully preserved across both transitions

Spot-checked several pieces of state that a consensus-only mechanism must never touch:
- `ValidatorsBoard.boardVersion` — unchanged (6, matching its last confirmed value from Phase 4).
- `ValidatorsRegistry.getValidators()` — unchanged (same 4 addresses).
- candidateD's post-slash `lockedStake` (from Phase 3 scenario 1/7) — unchanged to the wei.
- candidateE's fully-exited record (from Phase 3 scenario 9) — still deleted/zeroed, as it was
  before the transitions.

This directly confirms the governance doc's own design intent (§5 of
`sur-emergency-consensus-recovery.md`): the mechanism changes only consensus validator selection,
never contract state.

## What this test did not attempt
- A genuinely **different** validator set during the `blockheader` window (used the same 4 for
  isolation, as noted above) — the mechanism's ability to substitute an arbitrary validator list is
  documented by Besu itself and wasn't the open question here.
- The full 5-of-7 custodian signature/governance process around when to invoke this (Stage 2's
  organizational process) — this test only exercises the technical Besu mechanism (Stage 1's
  revival technique and the technical transition itself), not the human decision process wrapped
  around it, which has no code to test.
- The §4 "return checklist" gating condition (non-participating share ≤ `⌊(n-1)/3⌋`) was satisfied
  trivially here (0 non-participating validators among the 4 by the time of the return transition)
  rather than deliberately tested at its boundary.
