# Besu/QBFT live-execution test of the SUR contracts — final report

Test conducted 2026-09-27/28, on a fresh 4(+1)-node Hyperledger Besu 26.9.0 QBFT network built from
scratch on Windows, following the user's runbook. Everything lives under
`D:\Amir\Business\SUR\Test\besu-live-test\`. All source contracts came from the English
`contracts/` tree at `D:\Amir\Business\SUR\NewSur\Plan\contracts\`.

## 1. Test-parameter substitution table actually used

| Parameter | Production value | Test value used |
|---|---|---|
| `ValidatorsRegistry.probationPeriod` | 604800 (1 week) | **300** (5 min) |
| `ValidatorsRegistry.recoveryPeriod` | 172800 (48h) | **120** (2 min) |
| `ValidatorsRegistry.MASS_DEMOTION_WINDOW` | 3600 (1h) | **60** (1 min) |
| `ValidatorsRegistry.APPEAL_FILING_WINDOW` | 259200 (72h) | **120** (2 min) |
| `ValidatorsRegistry.APPEAL_VOTING_PERIOD` | 604800 (7d) | **180** (3 min) |
| `ValidatorsRegistry.DELIVERY_DISPUTE_GRACE_PERIOD` | 604800 (7d) | **120** (2 min) |
| `ValidatorsRegistry.exitCooldown` | 604800 (1 week) | **120** (2 min) |
| `ValidatorsTreasury.perPaymentCap` | 0 (unset/FILL_IN) | **1000 ether** |
| `ValidatorsTreasury.periodCap` | 0 (unset/FILL_IN) | **5000 ether** |
| `ValidatorsRegistry.verifier` default | `SurAddresses.VERIFIER` (prod key, not held) | **fresh test address** (see §2 deviation 3) |
| `ValidatorsRegistry_GenesisSeed` initial validators | 7 hardcoded placeholders | **4 test addresses = the 4 real Besu node addresses** |
| `ValidatorsBoard_GenesisSeed` / `FoundationDAO_GenesisSeed` | 5 / 15 hardcoded placeholders | **not used — both deployed with genuinely empty genesis state** (see §2) |
| genesis timestamp / `windowStart` / `BlockRewardDistributor.deployTime` | n/a | **1790539778** (2026-09-27T20:09:38Z) |

## 2. Deviations from the runbook (all found necessary during the build, not guessed around)

1. The 3 `_GenesisSeed` helpers have **zero-argument constructors** with hardcoded placeholder
   addresses inside, not constructor parameters as the runbook assumed. Edited a test-fork copy in
   place.
2. `ValidatorsRegistry`'s genesis validator array resized **7 -> 4** to exactly match the 4 real
   Besu node addresses used in this test (`qbft.validatorcontractaddress` mode makes
   `getValidators()` the live block-1+ validator set — extra unbacked entries would break quorum).
3. `verifier`'s default is a hardcoded production address (`SurAddresses.VERIFIER`) we don't hold
   the key for. Edited the test-fork's `ValidatorsRegistry.sol` line 177 to a freshly generated
   test address. (This edit only takes effect because genesis storage was extracted by *actually
   deploying* the real contract on a temp Hardhat chain — see §4 — which runs the implicit
   constructor; a literal-only edit would have had zero effect under naive genesis injection.)
4. **`ValidatorsBoard` and `FoundationDAO` were deployed with genuinely empty genesis state**
   (no seeded members), not the runbook's placeholder-filled `_GenesisSeed` helpers. Justification:
   `ValidatorsBoard.voteFor`/`refreshBoard` only ever admit *currently active validators* as
   board candidates regardless of genesis seeding, and `proposeApproveBudget`'s hard-minimum-3
   requirement is a fixed constant independent of how many of `BOARD_SIZE`'s 5 seats are filled —
   so pre-seeding the board would have been immediately overwritten by scenario D's live
   `voteFor`+`refreshBoard()` anyway, and skipping it is a *more faithful* test of the runbook's
   own stated goal ("real voteFor/refreshBoard"). `FoundationDAO` isn't touched by any scenario in
   this test, so its genesis members were left empty rather than hand-deriving
   `Member{string,address}[]` storage slots with no functional payoff.
5. Compiling all 12 `.sol` files (9 main + 3 `_GenesisSeed`) with solc 0.8.24 and `viaIR: false`
   **failed** — `sur-contracts-deploy-notes.md`'s claim that all 8 contracts compile clean without
   `viaIR` is currently false against the actual source. See §3 for the exact error and the
   non-viaIR fix applied.
6. `sur-contracts-deploy-notes.md` is stale on two more points versus current source (confirmed by
   the earlier research pass): `requiredLivenessRatioBps`/`inactivityThreshold` no longer exist
   (liveness math moved fully off-chain), and `ValidatorsTreasury.smallBudgetCap` no longer exists
   (replaced by `perPaymentCap`/`periodCap`).
7. Registered a real, reproducible **Besu-on-Windows bug**: `--bootnodes` (CLI and TOML) rejects
   *any* enode URL with `Illegal char <:> at index 5` — see §5. Worked around with
   `static-nodes.json` (a documented, standard Besu alternative), not a hidden hack.
8. Went further than the runbook asked in scenario A: after finding candidate5 (added purely as
   an EOA) never got a real proposer turn, stood up an actual 5th Besu node using its exact key —
   see §6.

## 3. Compile-phase finding: real Stack-too-deep bug, fixed without viaIR

Full detail in `logs/00-compile-findings.md`. Summary: `BlockRewardDistributor.distributeRewards`
hit `CompilerError: Stack too deep` at its call to the internal `_payValidators` helper — too many
simultaneously-live locals, contradicting the deploy-notes' claim this was already fixed. Fixed
(test-fork only) by extracting the pre-computation block into a new `_prepareEpoch()` helper
returning one `EpochPrep` memory struct instead of 4 separate locals, plus reordering
`foundationAmount`/`treasuryAmount` to after the `_payValidators` call. No `require()`, event, or
execution-order changes — confirmed: `Compiled 13 Solidity files successfully (evm target: paris)`.

## 4. Genesis storage extraction — verified, not just asserted

Method (see `hardhat/scripts/02-extract-genesis-storage.js`): deployed every real contract on
Hardhat's in-memory network (captures every plain scalar/immutable correctly, including every
TEST-FORK substitution above, via the real implicit constructor) + deployed
`ValidatorsRegistry_GenesisSeed` and computed the mapping/array storage slots for the 4 known
validator addresses analytically (`keccak256(abi.encode(addr, baseSlot))`, standard Solidity
layout), cross-checked against the helper's own `getActiveValidators()`. **Round-trip verified**:
injected the computed storage into a fresh `ValidatorsRegistry` instance via
`hardhat_setStorageAt` and confirmed `getValidators()`, `isValidator()`, `verifier()`, and
`windowStart()` all matched exactly before ever touching real Besu.

## 5. Genesis/network bring-up findings

- **Missing EVM hard-fork blocks** crashed node1 on first launch: `Invalid opcode: 0x1c` (SHR)
  calling `getValidators()`, because `config` had no fork-activation blocks at all and Besu
  defaulted to pre-Constantinople rules. Fixed by adding `homesteadBlock` through `londonBlock`
  (all 0) + `zeroBaseFee: true`. Full detail in `logs/phase3-network-verification.md`.
- **Besu-on-Windows bug**: `--bootnodes`/TOML `bootnodes=[...]` rejects any enode URL with
  `Illegal char <:> at index 5` (isolated with a dummy enode and even a plain `"aaaaa:bbb..."`
  string — reproduces regardless of content, so it's a `java.nio.file.Path`-style validator
  wrongly applied to this option on this build, not a malformed enode). Worked around with
  `static-nodes.json` in each node's data directory.
- **Phase 3 gate — genesis injection confirmed identical across all 4 real nodes**: identical
  genesis block hash (`0xe73bc939e927...`), identical genesis timestamp, and identical 37,218-char
  `eth_getCode(0x3333...3333)` (sha256 `5e39eb51ab25...`) on all 4 nodes.
- **QBFT proposer rotation confirmed contract-driven**: blocks 1-8 round-robin cleanly across
  exactly the 4 registry-seeded validators.

## 6. Scenario A — membership request, probation, activation, real proposer turn

Full raw data: `logs/scenario-a-raw.json`, narrative: `logs/scenario-a-findings.md`.
- `requestMembership()` (paid 520,000 Suren, computed live) -> real 300s wall-clock wait ->
  `recordActivation()` by the test verifier key -> `isValidator()`/`getValidators()` updated
  instantly on-chain.
- **First result was itself an important finding**: candidate5 (added only as an EOA) never
  appeared as block `miner`. Root-caused via `qbft_getValidatorsByBlockNumber` (confirmed Besu's
  own QBFT layer *did* pick up the change instantly) and block-timestamp deltas (a clean, periodic
  13s gap — 3s block period + 10s `requesttimeoutseconds` round-change timeout — every 5th slot):
  candidate5 was correctly included in the round-robin, but with no real node behind it, the
  network correctly round-changed past its turn every cycle. Valid BFT fault-tolerance behavior,
  not a defect.
- **Stood up a real 5th Besu node** with candidate5's exact key. It synced in seconds and produced
  block **#173** itself, with a normal 3s delta and no further round-change gaps afterward — full,
  clean confirmation that contract-driven activation makes a real QBFT proposer.

## 7. Scenario B — suspension and real quorum adaptation

Full raw data: `logs/scenario-b-raw.json`.
- `recordSuspension(validator2, evidenceHash)` (tx `0x0e3be359...`, block 188, decisionId `2`) ->
  `getValidators()` dropped validator2 in the very next call.
- Watched 15 subsequent blocks: network stayed live throughout, clean 3s spacing (no round-change
  gaps — all 4 remaining validators had real nodes), validator2 never proposed again.
- Network never shrank below BFT quorum in this test (5 -> 4 validators, well above `⌊2n/3⌋+1`),
  so the "does the chain actually halt below quorum" question from the runbook was not reached —
  noted as an explicit scope limit, not answered.

## 8. Scenario C — uncontested suspension -> automatic real-time penalty

Full raw data: `logs/scenario-c-raw.json`.
- Reused scenario B's `decisionId=2`. `resolveMassFailureCheck` — **not** mass-failure-exempt
  (1 suspension out of 5 pre-suspension validators = exactly the 20% boundary, and the contract's
  check requires *strictly greater than* 20% — confirms scenario ordering A-before-B/C mattered:
  running B first, against only 4 validators, would have hit the exemption instead).
- `confirmDelivery` by the subject validator -> real 130s wall-clock wait through
  `APPEAL_FILING_WINDOW` with no `fileAppeal` call -> `executeUncontestedSlash` succeeded.
- **Honest caveat**: validator2 is a genesis-seeded founder (`lockedStake = 0`, never a paid
  entrant), so the 1% slash computed against a 0 balance is 0 wei — the *mechanism* (state
  transition, `SlashOutcome.ExecutedUncontested`, event) is fully confirmed; the *monetary* effect
  is not, because no genesis founder has stake at risk by design. A real stake-slash test would
  need to target a paid entrant (e.g. candidate5) instead.

## 9. Scenario D — real board formation and treasury payment

Full raw data: `logs/scenario-d-console.log` (main run, ends mid-way at the bug below) +
`logs/scenario-d-continue-raw.json` (the 2 remaining votes + final balance check).
- Funded `ValidatorsTreasury` with 2000 Suren via a plain transfer (genesis gave it 0 balance —
  not something the runbook specified, needed once `boardApproveExpenditure` requires
  `amount <= address(this).balance`).
- All 4 currently-active validators (validator1, candidate5, validator3, validator4 — validator2
  suspended by scenario B) called `registerIdentity()` then `voteFor(self)` (self-votes explicitly
  allowed), then `refreshBoard()` — all real transactions. `isBoardMember()` confirmed true for
  all 4 afterward (5th `BOARD_SIZE` seat stays empty — exactly as reasoned in deviation §2.4, no
  functional effect).
- `proposeApproveBudget(budgetRecipient, 100 ether, ...)` -> `actionId=1`.
- **Real bug in my own script, not the contract**: assumed the proposer's vote wasn't
  automatically counted and tried to cast a 4th explicit vote from validator1, which reverted
  `"ValidatorsBoard: already voted"`. Root cause: `ValidatorsBoard._createAction` calls
  `_voteAction(id, msg.sender)` internally — **the proposer's vote is automatically counted**.
  Fixed by casting only the 2 additional votes actually needed (candidate5, validator3; 1 + 2 = 3,
  meeting the hard-minimum `requiredVotes`).
- **Confirmed real, on-chain payment**: `budgetRecipient` balance went from `0` to exactly
  `100000000000000000000` wei (100 Suren) — a genuine `boardApproveExpenditure` -> native transfer,
  end to end through real governance on the real network.

## 10. Time spent

| Phase | Wall-clock time |
|---|---|
| Research (repo/contract exploration, deploy-notes reconciliation) | ~25 min |
| Planning (this plan's write-up + approval) | ~10 min |
| Phase 1 (accounts, test-fork edits, compile incl. stack-too-deep fix) | ~25 min |
| Phase 2 (genesis storage extraction + round-trip verification) | ~15 min |
| Phase 3 (Besu download/extract + 2 crash-fix cycles + 4-node, later 5-node, bring-up) | ~25 min |
| Phase 4 — scenario A (mostly the real 310s probation wait + 5th-node investigation) | ~10 min |
| Phase 4 — scenario B (suspension + 15-block watch) | ~1 min |
| Phase 4 — scenario C (mostly the real 130s appeal-window wait) | ~2.5 min |
| Phase 4 — scenario D (board formation + treasury payment, incl. debugging the auto-vote finding) | ~2 min |
| Report | ~10 min |
| **Total** | **~2 hours** |

## Network endpoints (left running)
- node1 (bootnode): http://127.0.0.1:8541 — p2p 30301
- node2: http://127.0.0.1:8542 — p2p 30302
- node3: http://127.0.0.1:8543 — p2p 30303
- node4: http://127.0.0.1:8544 — p2p 30304
- node5 (candidate5): http://127.0.0.1:8545 — p2p 30305
