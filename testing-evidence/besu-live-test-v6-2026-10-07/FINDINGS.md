# FINDINGS — round 6 (BlockRewardDistributor v2.2, Shanghai/Cancun). Measurements and observations only; no contract or policy change is proposed. Every statement is limited to Besu release 26.9.0 and the configurations named.

## 1. A `blockreward` transition keyed by a timestamp changes the reward in exactly the first block whose timestamp is ≥ the key
Net-R6-S (baseline): T = 1791363089; block #429 (timestamp …3086) pays 2 SUR, #430 (timestamp …3089 = T) pays 3 SUR; 25 blocks before at the old reward, 23 after at the new one; `trace_block` and the empty-block balance delta of the distributor agree on all 48 empty blocks. The same coincidence at both governed boundaries of Net-R6-R (#501 for 3 SUR, #801 for 4 SUR). So "first block with `timestamp ≥ activationTime`" — the contract's own definition — is also where Besu changes the reward, when the Besu key equals the approved activation time. (`Net-R6-S-R1.json`, part 3 R1.1, part 4 R1.2.)

## 2. A small key is applied immediately, for rewards
A timestamp in the past (T2) and the number 100 (T3a: a block number mistaken for a timestamp, i.e. 1970) both pay the new reward from block 1 (blocks 1–40 measured: 8 SUR and 7 SUR). The node log lists the key as a milestone (`milestones: [Cancun:0, Cancun:100]`). Evidence: `Net-R6-T2-T2.json`, `Net-R6-T3-T3.json`.

## 3. `validatorselectionmode: blockheader` keyed by a timestamp stopped the chain at the transition (Net-R6-T and Net-R6-T5) — **important for the emergency-recovery procedure**
Configuration: Shanghai/Cancun genesis, 7-validator Registry in contract mode, `transitions.qbft` = [`blockheader` with the explicit list v1..v5 at TT1, `contract` with the Registry at TT2 = TT1 + 900 s], all 7 nodes running.
- The last block was #150 (timestamp TT1 − 3 s). For the whole interval until TT2 no node produced a block. All nodes log, for the proposal of block 151 (rounds 1, 2, 3, …): `Invalid block header: Incorrect validators. Expected [the Registry's 7 validator addresses] but got [].` (7 identical lines per node; first line verbatim in `Net-R6-T-T1-observation.json`.)
- After TT2 (the return to contract mode, also a timestamp) the chain **resumed by itself 384 s after TT2**: block #151 has timestamp 1791371065, **1,273 s after block #150**; the validator set is again the Registry's 7 and all 7 propose (query recorded below). I did not look for the cause of the 384 s; the QBFT round timeout grows with the round number.
- A restart of all 7 nodes **after** the recovery (same genesis, both times already past) resumed normally (head 178 → 254 in 4 minutes). A restart of all nodes **during** the halt: see REPORT row T1e.
- `blockheader` mode from the start (key 100, validators v1..v5, 5 nodes): **no block was ever produced** (head 0 for 3 minutes; no QBFT round logged). (`Net-R6-T4-T3validators.json`.)
- What this does **not** show: that every configuration of such a transition halts. One explicit list (5 of 7) was tried, on release 26.9.0, not on the develop build of the brief (QUESTIONS.md item 1). `governance/sur-emergency-consensus-recovery.md` §3 itself says the timestamp-keyed `blockheader` transition was untested; the result in this configuration is: it halted.

## 4. The v2.2 rate-change path works as designed in every case I could build; its limits are the ones its own comments name
Governance (3 board + 5 validator approvals, snapshot electorate, board-composition guard, 120 s delay on the fork), provisional entries, certification at the measured start block, exact caps after certification, non-overlapping windows, and `distributeRewards` with the **real** chain reward accepted at every governed boundary (R8). Estimates set +37 and −37 blocks from the predicted start were, against the measured start blocks, +36 and −38 — both within the tolerance (60 on the fork). The prediction of the start block from the recent block cadence (80 blocks) was off by 1 block both times (500 vs 501; 800 vs 801).

## 5. R6: a Besu transition at a time that is not an approved activation time (the "earlier" direction)
After TC3 the chain paid 5 SUR from block 1071 with no approved entry. The range holding the first 11 such blocks has a real reward of 127 SUR; the contract's cap was lower and the distribution was **rejected**; **reporting totalRewards = the cap (less than the chain paid) was accepted** — the old "silent under-payment" property (round-4 finding 13). Approving an entry afterwards does not repair it when the Besu change is outside the tolerance (363 blocks before the estimate): the oracle cannot certify Besu's real block (`start block is outside the tolerance window`), and after certification at the contract-defined block the 364 blocks that really paid 5 SUR are capped at 4 SUR for ever. The cap never rejected a correctly configured network; it did reject a misconfigured one, which is the design (the contract's own trust-boundary comment). The "later" direction was not run.

## 6. Besu's historical-state window limits the oracle on this path as well (round-4 finding 11, repeated)
`trace_block` returns `[]` for blocks older than about 512 blocks (≈ 25 minutes). A range settled later than that cannot have its reward measured (103 of the 470 blocks of range D0 were such). A real RewardRouter must settle within the window or keep its own per-block record.

## 7. Cancun on this genesis
The nodes started with `shanghaiTime` 0, `cancunTime` 0, the three Cancun header fields in the genesis header and no `blobSchedule`. The EIP-4788 contract is not in the state (observed only). All block-reading calls used by the test tools worked with the new header.

## 8. T1 direct query after the recovery (Net-R6-T)
Head 176; validator set (`qbft_getValidatorsByBlockNumber`) v1..v7; proposers of the last 20 blocks v1..v7; block #150 timestamp 1791369792, block #151 timestamp 1791371065 (gap 1,273 s); set at #151 v1..v7.

## 9. Size
`BlockRewardDistributor` runtime code: 20,424 bytes (the brief expected about 20,059; limit 24,576). `ValidatorsRegistry` 23,005 bytes (unchanged from round 5).
