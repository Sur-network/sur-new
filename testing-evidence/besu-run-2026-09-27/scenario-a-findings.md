# Scenario A — findings (richer than the raw script output alone)

## requestMembership -> probation -> recordActivation: all succeeded as real transactions
- `requestMembership()` tx `0x4ff513b1...` — status 1, block 35, paid 520,000 Suren (500,000 threshold + 20,000 membership fee, computed live from `currentEntryThreshold()`/`currentMembershipFee()`).
- Waited the real test-value `probationPeriod` (300s) wall-clock, not simulated time.
- `recordActivation()` tx `0x747a8dab...` — status 1, block 139. `isValidator(candidate5)` -> true. `getValidators()` -> all 5 addresses, contract-side confirmed instantly.

## First pass: candidate5 never appeared as block `miner` — a real, important finding, not a bug
Scenario A's own automated 12-block watch (right after activation) reported `candidateGotTurn: false`.
Investigated with raw RPC rather than assuming the watch script was broken:
- `qbft_getValidatorsByBlockNumber("latest")` **did** already include candidate5 right after
  activation — Besu's own QBFT validator tracking picked up the contract change immediately.
- But blocks 135-162 showed a periodic pattern: 4 blocks at the normal 3s `blockperiodseconds`,
  then **one 13-second gap** (3s block period + 10s `requesttimeoutseconds` round-change timeout),
  repeating every 5 slots — exactly the signature of a validator being *in* the round-robin
  rotation but never actually proposing, forcing the other nodes to time out and round-change past
  its turn every cycle.
- Root cause: **candidate5 was only ever an EOA in this test — no Besu node was ever started with
  its private key.** The contract-level validator set updated correctly and instantly; the
  protocol was correctly, resiliently working around a registered-but-offline validator exactly as
  BFT is supposed to. This is itself a valid, useful confirmation of QBFT's fault tolerance, not a
  failure of the genesis-injection/validator-contract mechanism.

## Second pass: stood up a real 5th Besu node for candidate5 — full confirmation
Added `node5` (candidate5's real private key as its Besu nodekey, joined via the existing
bootnode). It synced from block 0 in seconds and, unprompted, produced block **#173** itself
(`Produced #173 ... in 0.087s`). Confirmed via direct RPC: block 173's `miner` field is exactly
candidate5's address, with a normal 3s delta (no round-change needed), and every block after it
returned to smooth 3s spacing with no further gaps.

**This is the clean, complete answer to the runbook's core question**: a validator activated
purely through `ValidatorsRegistry.recordActivation()` — with no other on-chain step — genuinely
becomes a real QBFT block proposer the moment its own node joins the network, and the network
correctly, gracefully tolerates it being temporarily offline before that.
