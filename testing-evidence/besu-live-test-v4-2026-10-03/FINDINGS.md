# FINDINGS — unexpected results, with raw evidence

## 1. B01/B07, corrected: the RPC method and the actual signing-authorization semantics answer two different questions — both now independently confirmed, not conflated

**Classification:** ابهام مشخصات (specification ambiguity), resolved by reading Besu's own source
and by direct measurement of `miner` and `extraData` on real blocks. **This supersedes an
over-broad conclusion in an earlier version of this report**, which stated the "N-1 convention"
was simply wrong and should be replaced by "N" everywhere, including for B07. That was incorrect
as a general claim; the corrected finding below treats the RPC method's own semantics and the
actual consensus-authorization question as two separate things, as they must be.

**What the RPC method itself does (confirmed from Besu's own source, `besu-eth/besu`,
`consensus/qbft/.../QbftGetValidatorsByBlockNumber.java`):** for a specific block number N (not
`"latest"`/`"pending"`), the method fetches **block N's own header** via
`getBlockHeaderByNumber(N)` and calls `validatorProvider.getValidatorsForBlock(header)` using that
header — i.e. it answers "what does the registry look like as of (immediately after) block N",
using N's own post-execution state. This is exactly consistent with this round's earlier empirical
result: `qbft_getValidatorsByBlockNumber(N)` matches `getValidators()@blockTag(N)`, not `@(N-1)`.
Raw data: `evidence/04-results/Net-B-B01.json`.

**What the RPC method does NOT tell you: who was actually authorized to sign/produce block N.**
That is a causal question — block N's proposer and committers are necessarily selected using the
registry state as it stood **before** N was built (N's own state doesn't exist yet while N is
being assembled). This round confirmed this directly and independently, by restarting a single
node read-only (no mining, no new transactions — just querying blocks it had already stored) and
inspecting the real block headers around both validator-set transitions:

| Transition | Block containing the state-changing tx | `miner` of that block | extraData size (bytes) | First block at new size | 
|---|---|---|---|---|
| B02 (5→4, suspend V5) | 107 | `g5_v1` (a pre-existing, still-active founder in both the 5- and 4-member sets) | 310 (block 104-107) | **108** → 241 bytes |
| B05 (6→4, suspend V4+V5) | 1420 | `g5_v5` (itself one of the two being suspended — still active going into 1420) | 310 (1417-1420) | **1421** → 241 bytes |

The seal-carrying `extraData` size changes exactly **one block after** the state-changing
transaction, in both independent transitions — never at the transition block itself. For the two
transitions actually inspected, this directly confirms: the set of signers for block N is drawn
from the registry state as of **N-1**, including at the transition block itself (which is still
signed under the *old* set, since the transaction that changes the set is itself inside that block
and hasn't executed yet when the block is assembled). `qbft_getValidatorsByBlockNumber(N)`, by
contrast, reports the registry one block "ahead" of when that set actually starts signing at these
same two transitions, because it reads N's own post-execution state, not N-1's. Neither claim is
asserted beyond the 17 sampled blocks described below.

**Conclusion for B07** ("is `miner(N)` ∈ Registry@(N-1)?"): **confirmed for the blocks actually
inspected** — 17 sampled blocks across both transitions (104-112 around block 107; 1417-1424
around block 1420) — the actual producer at each transition block belongs to the OLD (N-1) set in
both cases, and the `extraData`-size shift at exactly the next block is consistent with this in
both independent transitions. **This is not a claim that every block in either chain's full
history (4700+ blocks on Net-B) was checked** — only the sampled windows around the two known
validator-set changes were. No block within the inspected ranges contradicted the pattern, but
absence of a contradiction in a 17-block sample is not the same as a chain-wide proof. This is the
version of B07 that should stand; substituting `qbft_getValidatorsByBlockNumber`'s own N-based
convention for this purpose, as an earlier draft of this report did, would have been answering a
different question than the one B07 asks, regardless of sample size. Raw evidence for this
section: queried via a single read-only node restart (no mining, no state-changing transactions)
against blocks already mined and stored before this round's networks were stopped; not saved as a
separate script, command and output are reproduced in full in `evidence/04-results/B01-B07-signer-authorization.json`.

**What remains open:** full QBFT committed-seal signature recovery (recovering each individual
signer's address from the seal bytes via `ecrecover`, independent of the `miner` field) was not
attempted — the `extraData`-size shift is strong circumstantial confirmation of the N-1 causality
but is not a substitute for cryptographically verifying every signer's identity. This is listed in
LIMITATIONS.md as still open.

## 2. Host resource ceiling: 38 concurrent Besu JVMs exhausted the Windows paging file at default heap size

**Classification:** محیط/زیرساخت (environment/infrastructure), not a contract or Besu bug.

Launching all 7 planned networks (38 node processes total) simultaneously with Besu's default JVM
heap sizing produced `OpenJDK ... error='The paging file is too small for this operation to
complete'` on several nodes, and a transient `JAVA_HOME is not set` error on another (apparently a
side effect of the same resource exhaustion affecting process creation, not a real PATH issue).
**Fix:** set `JAVA_OPTS=-Xmx512m -Xms256m` for every node before launch, then re-launched in two
waves. All 7 networks (38 nodes) ran stably afterward. Recorded here as an environment-scaling
constraint of this single-host test setup, not a product defect.

## 3. BlockRewardDistributor runtime bytecode size differs from the document's stated reference — root-caused to `evmVersion`/metadata settings, not source or solc-version drift

**Classification:** ابهام مشخصات (specification ambiguity) in the document itself — investigated
rigorously below, not a stop condition (source hash matched exactly, per §2.1's table; A04's
code-hash-vs-alloc checks passed exactly across all 6 networks because genesis injection and the
fingerprint comparison both come from the *same* compile, so they are internally consistent
regardless of which evmVersion was used).

**Measured:** 18,519 bytes. **Document's stated reference** (package v2): 18,177 bytes. Source
SHA-256 matches the document's table exactly (§2.1). Full solc identity used:
`0.8.24+commit.e11b9ed9` (the official release, confirmed via `buildInfo.solcLongVersion` — not a
different patch build). Compile settings used: `optimizer.enabled=true`, `runs=200`,
`viaIR=false`, `outputSelection` as needed for artifacts — exactly matching §2.2 step 3's stated
settings, **except** `evmVersion`, which the document asks to leave at "that solc's own default"
and which this project's `hardhat.config.js` never set explicitly. Hardhat 2.29.1 silently chose
`evmVersion=paris` in that case (confirmed via `buildInfo.input.settings.evmVersion`), not solc
0.8.24's own true default, which is `shanghai` (solc's default evmVersion tracks the latest fork
considered stable at release time; 0.8.24 shipped in January 2024, well after Shanghai went live
in April 2023).

**Root-cause test (reproducible, no network needed — recompiled the same unmodified source four
ways and measured each output):**

| Config tested | Runtime size |
|---|---|
| `evmVersion=paris` (what this round's baseline actually used) | **18,519 bytes** |
| `evmVersion=shanghai` (solc 0.8.24's true own default), default metadata | 18,224 bytes |
| `evmVersion=shanghai`, `metadata.bytecodeHash="none"` | 18,183 bytes |
| `evmVersion=shanghai`, `metadata.bytecodeHash="none"`, `metadata.appendCBOR=false` | 18,171 bytes |

This fully explains the 342-byte gap: switching `paris→shanghai` alone accounts for 295 bytes
(PUSH0 opcode and related codegen differences), and metadata/CBOR-trailer settings account for the
rest (the document's reference, 18,177, falls exactly between the `appendCBOR=false` case and the
`bytecodeHash="none"`-with-CBOR case — i.e. within 6 bytes of both, consistent with a metadata
variant this test didn't reproduce exactly, not with a different source or solc build). **Not a
source or solc-version difference** — definitively ruled out by the hash match and the identical
`solcLongVersion`.

**An internal tension in the document's own specification, surfaced by this test:** `evmVersion
=shanghai` enables the `PUSH0` opcode. But this round's genesis (built exactly per §4's own table —
"zeroBaseFee، londonBlock و همهٔ hard-forkها: true، همه صفر") activates forks only through
**London** and sets no `shanghaiTime`/merge field at all — so a Besu network built to this
document's own §4 spec may not execute `PUSH0` the way `shanghai`-targeted bytecode expects. This
round's baseline compile (accidentally, via Hardhat's un-set-evmVersion default landing on `paris`)
used a pre-Shanghai target that is actually **consistent** with the genesis fork configuration the
document itself specifies — literally following "use solc's own default" (`shanghai`) instead
would have produced bytecode targeting an EVM fork this round's genesis never activates. This is
reported as an open tension in the document's specification (§2.2 step 3 vs §4's fork table), not
resolved here — see QUESTIONS.md.

## 4. `A05`: `immutableReferences` is empty — confirms the L03 audit's removal of `deployTime`

Confirmed `{}` exactly as the document expects. This is a positive confirmation (not a surprise)
that `BlockRewardDistributor.sol`'s former `immutable deployTime` field (used in rounds 1-3) was
genuinely removed by the L03 audit fix along with the time-based physical-maximum check, leaving
no immutables in the contract at all.

## 5. Several of my own test-script bugs (not contract bugs) — disclosed rather than silently fixed

- **`RateProposal` struct field order**: my first C-L05 and rate-path scripts used a wrong ABI
  field order for `rateProposals(id)` (swapped `approvedAt`/`requiredValidatorApprovals` and
  misread `boardApprovals`/`validatorApprovals`), causing validator-vote loops to send one fewer
  vote than actually required. This produced misleading "still voting" states that looked like
  contract issues but were purely a script bug. Fixed by re-deriving the exact field order from
  `BlockRewardDistributor.sol`'s own struct declaration and re-running cleanly. See the `cl05`
  evidence file's own `SCRIPT_BUG_NOTE` for the full disclosure and the corrected re-run.
- **Rate-change `startBlock` margin**: an early rate-path attempt on Net-Fork chose `startBlock`
  with only `leadBlocks + 10` margin above the block at proposal time, not accounting for the
  ~60 blocks produced during the subsequent 180-second `RATE_CHANGE_DELAY` wait — by execution
  time the margin had collapsed below `MIN_RATE_CHANGE_LEAD_BLOCKS`, correctly triggering "start
  block is closer than MIN_RATE_CHANGE_LEAD_BLOCKS". Fixed by sizing the margin to cover the wait
  itself (`delay/3s blocks + leadBlocks + buffer`); the corrected run (proposal id=2) executed
  successfully. Both failures are documented in `evidence/04-results/Net-Fork-L1-L3-ratepath-FINAL.json`'s
  note. Both fixes are consolidated into a single, clean, reproducible script added to this
  delivery: `hardhat-fork/scripts/testonly-fork-ratepath-FINAL.js` (not re-run this delivery —
  added for reproducibility of the sequence that already succeeded, per the CORRECT field order
  and margin logic described above).
- **D01 array accounting**: three D01 edge cases (duplicate address, zero address, never-activated
  address) initially added a payload entry without adjusting `blocksMined`'s sum to stay within the
  settled range size, so they hit "reported blocks exceed the range size" before reaching the
  condition actually being tested. By the time this was noticed, `Net-D` had already consumed its
  one `epochCount==0` exemption (D02 had succeeded), so a clean pre-first-distribution retry on
  `Net-D` itself was no longer possible without a 23-hour wait. The three corrected cases were run
  instead on `Net-Fork` before its own first distribution — equally valid evidence, see
  `evidence/04-results/Net-Fork-D01-D02-D04-D05.json`.

## 6. Besu distribution SHA-256 differs from the document's stated reference, but the version string confirms it's genuinely 26.9.0

**Classification:** ابهام مشخصات (specification ambiguity) — likely a packaging/platform mismatch,
not a wrong version.

Document's reference: `172b29069837f13436a20bd7c8234aeca67917d8a378e81e2bd4a205c57540ea`. The
cached `besu-26.9.0.zip` (Windows distribution, reused from a prior round's download) actually
hashes to `749f90b0b29b8138f5d58b949d19eed721826cab66bfb8d983f86e15831d22b2`. Running
`besu --version` confirms `besu/v26.9.0/windows-x86_64/openjdk-java-25` — genuinely version
26.9.0. The most likely explanation is that the document's reference hash was recorded for a
different OS/architecture package (e.g. a Linux tarball) than the Windows zip used here, not that
a different Besu version is in use. Not independently re-verified against Besu's own published
release hashes this round, due to time budget — see `evidence/01-environment/env.json`.

## 7. Besu's default BONSAI historical-state limit confirmed at ~512 blocks back

**Classification:** رفتار Besu (Besu behavior), exactly as the document's own §5.2 anticipated
("مستقل از این، ردیف‌های گروه B را در لحظه جمع کن، نه بعداً").

Attempting `getValidators({blockTag: N})` on Net-B for N more than ~512 blocks behind the current
head returned `"missing revert data" / Internal error` from Besu (confirmed empirically: block 271
readable, block 261 not, at chain height 781 — i.e. the cutoff sits at roughly current-512). This
is exactly the historical-depth limitation the document's §5.2 warned about and explicitly told
this test to work around by collecting Group B evidence live, not retroactively. B01's evidence was
already collected live at the time of the B02 transition (block 107), so it is unaffected. B06's
collector was adjusted to only sample the still-reachable recent window plus the B03 transition
(~block 651); the full historical sweep back to block 1 was not attempted. `data-storage-format`
was left at its default (BONSAI); `FOREST` mode or a raised `bonsai-historical-block-limit` was not
tried this round, given the time budget.

## 8. `recordRecovery` is blocked by an independent slash case that `recordSuspension` always opens — not mentioned in the document's Group B description

**Classification:** ابهام مشخصات (specification ambiguity) — a genuine, load-bearing contract
behavior that the test brief's Group B section does not mention as a precondition.

The document's B04 ("بازگشت V5: پس از recoveryPeriod (۳۷۰۰ ث) با recordRecovery") reads as if
waiting `recoveryPeriod` and calling `recordRecovery` is sufficient. In fact, `recordSuspension`
**unconditionally** opens a `StatusDecision` with a non-zero `pendingSlashDecisionId` (source:
`ValidatorsRegistry.sol` `_recordDecision`), and `recordRecovery` requires
`v.pendingSlashEpoch == 0` — so recovery is blocked until that decision is independently resolved
through the mass-failure/delivery/appeal pipeline (`resolveMassFailureCheck` →
`confirmDelivery` → either a 72-hour uncontested wait or `fileAppeal` + a same-majority
`confirmSlash` vote). On both Net-B (B04) and Net-L04 (C-L04 recovery step), waiting only
`recoveryPeriod` and calling `recordRecovery` reverted with `"ValidatorsRegistry: resolve the
pending slash first"` until this additional path was run.

**Resolution used (fast path, to stay within the session's time budget) — and a second finding
along the way:** on Net-B, where only a single validator (V5) was suspended, the case was NOT
exempt from the mass-failure check (1 of 5 = 20%, not strictly greater than the 20% threshold), so
the full appeal path was needed: the subject validator filed an appeal (`fileAppeal`) immediately
after `confirmDelivery`, and a simple majority of active validators voted `confirmSlash`, which
executes the case immediately once quorum is reached — avoiding the 72-hour uncontested-slash wait.
On **Net-L04**, where V5 and V4 were suspended close together within the same `MASS_DEMOTION_WINDOW`
(2 of 6 = 33% > 20%), `resolveMassFailureCheck` auto-exempted **both** cases
(`SlashOutcome.ExemptMassFailure`) the moment the window closed — no appeal or vote needed at all,
and a `confirmDelivery`/`fileAppeal` attempt afterward correctly reverted with `"case already
resolved"` (confirming the case really was already closed, not stuck). Since genesis-seeded
founders have `lockedStake == 0`, the resulting slash amount was `0` in every path (no actual value
moved) — but `pendingSlashEpoch` still had to independently clear via one of these two routes before
`recordRecovery` could succeed. See `evidence/04-results/Net-B-B04.json`,
`Net-L04-V5-recovery.json`, and `Net-L04-V4-recovery.json`.

**Why this matters:** this is a real operational dependency that any future "recovery" tooling
(including the eventual RewardRouter/operations tooling) must account for — a suspended
validator cannot simply wait out `recoveryPeriod` and resume; its slash case must also reach a
final outcome first, and the only two paths to that are a 72-hour uncontested wait or a
contested-and-voted appeal. The `MASS_DEMOTION_WINDOW` (1 hour, real value, unchanged) also had to
elapse before `resolveMassFailureCheck` was callable at all, adding a further ~1-hour real
dependency on top of `recoveryPeriod` itself.

None of the above affected any already-reported PASS result for a real contract behavior check —
each was caught via before/after state comparison or a direct source re-check before being
reported, consistent with this document's own rule 8 (claims limited to what was actually observed).

---

# Follow-up pass (2026-10-03): L05 re-runs, D02 accounting, D06, Groups F and E

## 9. Besu's `transitions.qbft[].blockreward` works exactly as the document's template, and the boundary is exactly X (inclusive) — F01

**Classification:** رفتار Besu (verified, no discrepancy).
`config.transitions.qbft = [{ "block": 300, "blockreward": "3000000000000000000" }]` was accepted by
Besu 26.9.0 on all nodes with no error or warning. On a network whose contract history is
`[(300, 3e18)]` (TEST-ONLY-SEED), blocks up to 299 paid 2 SUR and **block 300 itself was the first to
pay 3 SUR**, measured by two independent methods (empty-block balance delta of 0x2222, and
`trace_block` — which on QBFT *does* return `type:"reward"` entries, with `author` = the
`miningbeneficiary`). The contract's `rewardRateAt()` flips at the same block, so there is **no
one-block coordination gap**. Evidence: `04-results/Net-F1-F01.json`, `F02-reconcile.json`.

## 10. Changing the reward on a live network: restart-with-new-file is both sufficient and necessary; a node that is out of step fails at X with a state-root mismatch — F05/F06/F07

**Classification:** رفتار Besu (verified).
- **Sufficient (F05):** editing the shared genesis file and restarting the five validators one at a
  time was accepted by Besu (same block-0 hash), the chain never stopped, and the reward changed at
  exactly X′ (=383). Nodes were stopped with a hard process kill (`taskkill /F`) and relaunched; no
  graceful-shutdown variant was tried.
- **Necessary (control, `Net-F3-F05-control-no-restart.json`):** the same file edit on a running
  network *without* restarting anything changed nothing — no reward change at X″, no divergence.
  Besu reads the genesis file only at start-up.
- **Out-of-step node (F06, F07):** a node whose genesis lacks the transition (a late joiner, or one
  validator not updated) rejects the canonical block X with
  `World State Root does not match expected value` and drops out. In F07 the other four validators
  (exactly the quorum 4/5) continued; every slot where the missing validator should have proposed
  cost one 10-second round-change (13 s block gap instead of 3 s at blocks 301, 305, 309, …).
  With f=1 consumed, one more fault would halt the chain.
- **Caveat on F07:** node5 later terminated with `java.lang.OutOfMemoryError: Java heap space`, under
  this test's `-Xmx512m` cap; it is not established that Besu would terminate on its own with a normal
  heap. **(Re-run with the default heap: FINDINGS.md item 18 — no OutOfMemoryError observed in about 36 minutes; the cause of the earlier crash is not established.)**

## 11. Independent §D extraction only works inside Besu's ~512-block state window, and OUTSIDE it Besu answers `null` / `[]` — silently, not with an error

**Classification:** رفتار Besu — and an operational constraint for the future RewardRouter.
Probed directly on Net-F3 at height 756: `eth_getBalance(0x2222, block 5)` returned **`null`** and
`trace_block(5)` returned **an empty array `[]`** (no reward entries, no error), while the block
header was still fully available and state 84 blocks back was fine. Consequences: (a) any collector
that reads `[]` as "reward 0" or `null` as "balance 0" would silently produce wrong totals — the
test tool treats both as *unavailable* and its conservation-equation gate would refuse to send;
(b) the production range is 23 h ≈ 27,600 blocks, which is **far beyond** the window — an independent
check of a whole daily range from node state is only possible on an archive/FOREST node or by
collecting incrementally per block, which is what the document already says for Group B and now
equally applies to the reward/fee accounting. Also: the full independent extraction of a 330–436 block
range took ~3.5–7 minutes per run (≥ 2 `trace_block`/state calls per block, several runs in parallel on
a loaded host), during which the chain advanced ~100–200 blocks.

## 12. Items worth knowing from the D02 re-execution on Net-D3 (all in `D02-acct-reconcile.json`)

**Classification:** ابهام مشخصات / observation (no contract defect shown).
- **The distribution transaction's own fee returns to the distributor.** With `zeroBaseFee` the whole
  gas price goes to the coinbase, which is the distributor; one `distributeRewards` of 6 validators
  cost 1,362,952 gas × 0.0001 SUR/gas = **136.3 SUR** (F02/F04 with 5 validators: 939,575 gas =
  93.96 SUR). That fee is not part of the epoch it settles (it lands after L) but of the *next* one.
- **Plain transfers into the distributor are never paid out.** A 7 SUR `receive()` transfer (the
  "X" term) was accounted for in the conservation equation but is not distributed by any epoch; it
  simply stays in the contract balance.
- **Membership fees are exempt from the 30% burn and are folded into the validators' fee pool**,
  exactly as the contract's comments say: 20,000 SUR membership fee distributed pro rata, burn =
  30% of the 40.384 SUR ordinary fees only (12.1152 SUR).
- Treasury received **94.5 SUR + 3 wei** (integer-division dust goes to Treasury, as designed).

## 13. "Cap cannot see under-payment": the L05 cap only bounds Besu's reward from above (F04)

**Classification:** ابهام مشخصات.
In F04 the contract's approved history said 3 SUR from block 300 but Besu kept paying 2 SUR; the
distribution of the real 872 SUR passed (cap 1009), and nothing on-chain records the 137 SUR gap.
Only an off-chain tool (here: the test script's warning) can notice it. Conversely (F03) a Besu
reward above the cap is rejected loudly. This matches the document's intent but is worth stating
explicitly for the RewardRouter design: under-payment drift between Besu and the contract is silent.

## 14. Second composition change in C-L05-3b necessarily drops to 3 active validators on a G5 network

**Classification:** ابهام مشخصات (document sequence vs its own ≥4 guideline). The document's 3b
("another member + `syncBoard()`") cannot be done on a 5-founder network without going from 4 to 3
active validators, because `fillVacancies()` only seats currently *active, not-yet-seated* candidates
and none exists. It was run exactly as written, all node processes kept running, the chain stayed
live — reported as a deviation in `DEVIATIONS.md` item 11.

## 15. Group E (synthetic benchmark — NOT a production capacity statement)

**Classification:** measurement; the document itself forbids reading it as production capacity, Router
capacity or a gasLimit approval, and this item does not.
- Payment cost is **linear and very regular**: about **137.6K gas per payee** (three new storage records
  per payee plus the native transfer to a previously empty account) and about **2.81K gas per rate-history
  entry inside the range** (matches the document's ~2,800 Hardhat reference), on top of a base of ≈ 421K.
  `maxRewardsForRange(1, toBlock)` alone costs 48K gas at k=0 and 1.17M gas at k=399.
- Estimates are **identical across the 15M/30M/60M networks** wherever they fit, and the real
  distribution used 99.1% of the estimate (14.32M vs 14.46M; 21.99M vs 22.19M) — `eth_estimateGas` was a
  reliable predictor here.
- At 15M the matrix runs out between N=100 (14.2M at k=0, 15.3M at k=399 → the latter does not fit) and
  N=150; Besu's raw refusal is `-32000 … (Out of gas)`.
- Because `miningbeneficiary` is the distributor and `zeroBaseFee` is on, **the fee of the distribution
  transaction itself is large and returns to the distributor**: 21,992,470 gas × 0.0001 SUR/gas ≈ 2,199 SUR
  for 150 payees (see item 12 for the smaller cases). It is booked into the next epoch, not the one it settles.
- All 75 combinations used a block-count sum equal to the range length (ratio 1); no "under-reported"
  combination was produced or needed.
- One transient failure: the first Net-E60 run aborted on a single `eth_call` returning
  `-32603 Internal error` (the same call worked immediately afterwards), most likely caused by three
  benchmark scripts hitting a loaded host at once; nothing had been sent, the run was repeated on its own
  and the raw first-attempt output is kept (`logs/v5-scripts/E60-first-attempt-transient-error.out`).

---

# Second follow-up pass (2026-10-03): combined F6 test, A14, F07 with the default heap

## 16. A14: every baseline genesis equals an independently derived expected alloc, and Besu's loaded state equals the genesis file — but Besu's debug RPCs cannot enumerate state on this node

**Classification:** measurement (no unexpected storage found); رفتار Besu for the RPC limitation.
- **Static:** 20 baseline genesis files were diffed against an expected alloc derived independently of the genesis builder
  (clean-constructor slots of a fresh deploy + a seed list computed analytically from the compiled `storageLayout`): **0 extra
  accounts, 0 extra slots, 0 missing slots, 0 wrong values**. `activeIndex` is checked at its exact 1-based value, `everActivated`
  and the checkpoint slots at exact values; `validators[a].status` and the FoundationDAO name strings are checked by presence
  (plus the semantic round-trip / short-string validity), not by exact value. A **negative control** (tampered copy: extra
  account, extra slot, removed slot, changed value) is flagged 4/4. The scan first reported 61 deviations on Net-L01, L02, L04,
  L05; that was my expectation being wrong, not the genesis: those four networks were built with `SEED_FOUNDATION=0`
  (recovered from the original build commands), i.e. FoundationDAO deliberately unseeded.
- **Live:** `debug_storageRangeAt` and `debug_accountRange` returned **empty results** even on a block containing a transaction
  (Besu 26.9.0, Bonsai) — they cannot be used to enumerate state here. Instead the node's own block-0 `stateRoot` was compared
  with a Merkle-Patricia root computed from the genesis alloc (calculator written for this, validated by the comparison itself):
  **21/21 networks equal**. Any extra or missing account/slot would change that root.
- Not covered: the *current* state of the long-lived networks (it legitimately differs from genesis); hashed-location slots
  written by a *constructor* (assumption: constructors write only plain state variables); Net-Fork (fork bytecode) is only in the
  live root check.

## 17. The combined test (F-COMB, Net-F6): accounting closes exactly across the transition with non-empty blocks; F03 is rejected, F04 simulated

**Classification:** measurement (no discrepancy). `04-results/F6-combined-reconcile.json`, `F6-F03-reconcile.json`, `F6-F04-reconcile.json`.
- Range `[1,149]` crosses X=100 with fee transactions in every block 93–111, a membership fee in block 99 and a direct 7 SUR
  inflow in block 100 itself. R (trace_block) = 348 SUR, F = 63.484, M = 20,000, X = 7, P = 0; the equation closes with residual 0
  and a **per-block** check (`Δbalance = reward + fees + inflow − outflow`) holds for all 149 blocks including the 19 non-empty
  ones — i.e. the trace_block reward is unaffected by transactions in the same block, and the empty-block method is not needed
  when fees and inflows are independently known. Cap = R exactly; the real distribution matched every BigInt expectation; the
  30% burn applied to ordinary fees only (19.0452 SUR), the 20,000 SUR membership fee was exempt.
- F03 on the same network: R=692 vs cap 681 (staged Besu rates 3→2→4 against a single approved entry) → exact revert message,
  status-0 transaction, state unchanged, and **`pendingMembershipFees` stayed at 20,000 SUR** (the fold-in inside the reverted call
  was rolled back).
- F04 on the same network is an `eth_call` **simulation** only (R=410 < cap 441 → succeeds): a network has exactly one successful
  distribution before the 23 h lock and F-COMB used it. This is a scope limit, stated in the row and in DEVIATIONS.md item 20.
- A network-design point worth recording: to get R=cap, R<cap and R>cap on three ranges of one network, Besu was given three
  staged transitions (100→3, 150→2, 200→4 SUR) and the contract a single seeded entry `[(100, 3 SUR)]`; the first range ends at 149.

## 18. Operational finding: a node with a mismatched genesis retries the invalid block continuously and uses a lot of memory; with the default heap no OutOfMemoryError was observed in about 36 minutes

**Classification:** رفتار Besu / operational finding. Evidence: `04-results/Net-F5b-F07.json`, `Net-F5b-F07b-monitor.json`, `Net-F5b-F07b-final-snapshot.json`,
`logs/v5-scripts/F07b-jcmd.log`, `logs/Net-F5b/node5.log`.
- Same scenario as F07 (transition at X=300 on nodes 1–4; node5 started without it), but **node5 alone without `-Xmx512m`** (Besu reported `Maximum heap size: 7.94 GB`).
- Behaviour at X is the same as in the capped run: node5 rejects block 300 with the state-root mismatch and stays at **height 299** while the other four continue (head 698 at the
  end), with block gaps of 13 s at 301, 305, 309, … ; node5's peer count flaps between 0 and 4 and its log shows **1,111 repeated "Invalid block 300" rejections** by the end.
- **Memory (observations):** within about 2 minutes of block 300 node5's process memory grew from ~0.6 GB to ~7.5 GB. In 31 `jcmd GC.heap_info` samples (every 60 s) the
  *used* heap ranged from 2,049 MB to 5,524 MB; between collections it rose by roughly 250–300 MB per minute, and the sampled post-GC lows were 2,080 MB (11:30 UTC) and
  2,049 MB (11:44 UTC). These are observations over one finite window; **they do not prove that there is no memory leak**, and they do not by themselves explain why the
  capped run failed.
- **Answer to the question asked:** **with the default heap, no `OutOfMemoryError` was observed in about 36 minutes** (0 `OutOfMemory`/`Terminating` lines in node5's log; process
  alive and responsive throughout; block 300 at 11:15:33 UTC → final snapshot 11:52:01 UTC, ≈ 400 blocks on the healthy nodes). **The definitive cause of the earlier crash
  (same scenario with `-Xmx512m`, `OutOfMemoryError` ≈ 90 s after block 300) was not established**; a relation to the heap size is plausible but only these two runs exist. The Besu
  launcher sets `-XX:+ExitOnOutOfMemoryError`, which is why the capped run terminated at once.
- **Why it is kept as an operational finding:** the node never recovers by itself (it stays at the old height, retrying and consuming memory and CPU) and needs operator action
  (QUESTIONS.md item 10).


---

# Third follow-up pass (2026-10-03/04): C-L04-6, Group A coverage on the follow-up networks, path-L plan

## 19. A09 spec discrepancy: `lastBoardRefreshAt` is 0 on every network built by the test builder; the genesis-builder spec asserts it equals the genesis timestamp

**Classification:** باگ ابزار آزمایشی / ابهام مشخصات (test-tool gap against the spec; not a contract defect).
The genesis-builder spec (§4.2.1, assertion list: `ValidatorsBoard.lastBoardRefreshAt() == network.genesisTimestamp`, P01, "if the board is seeded") and the brief's A09 row ("compare with the genesis-builder spec") expect the genesis timestamp. The test builder seeds the board's members and membership flags but never writes `lastBoardRefreshAt`, so it stays **0** — on all 15 follow-up networks (11 fresh twins checked live) and, per their raw files, on Net-B, D, L01, L02, L04, L05 and Fork. The earlier A09 PASS rows were recorded without making this comparison. Consequence: `refreshBoard()` (allowed when `boardMembers.length == 0 || now >= lastBoardRefreshAt + 30 days`) is immediately callable instead of after 30 days. No executed test used `refreshBoard()`. Whether the production genesis tool must write the field, or the spec text should change, is not decided (QUESTIONS.md item 12). Evidence: `04-results/A-live-Net-T-*.json`, `evidence/06-coverage/A-coverage-followup-networks.md`.

## 20. C-L04-6 (FoundationDAO eligibility snapshot) behaves exactly as the L04 policy describes — and an operational observation about unaffordable transactions

**Classification:** measurement (31/31 assertions, `04-results/Net-L04f-CL04-6.json`); observation for the second part.
- A member added after a proposal's creation is rejected on it with `not eligible - not a member when this proposal was created` while remaining eligible on later proposals; a removed member keeps the vote already cast (`hasVoted` true, tally unchanged) and cannot vote again (`caller is not a member`); a removed-and-re-added member is a *new* member for older proposals (`memberSinceNonce` 3 > the proposal's snapshot nonce); an open proposal keeps its **frozen quorum** in both directions (P2 with 8 votes did not execute while the live quorum was 8, because its snapshot was 9; P1 executed at its snapshot 8 while the live quorum was 9); membership changes never void an open proposal. `createdAtNonce` is not readable by a getter (as the brief notes), so eligibility was observed through `eth_call`/real transactions.
- **Unaffordable transactions stay pending silently.** In the first run each member had 10 SUR while a transaction with `gasLimit` 800,000 at 0.0001 SUR/gas needs 80 SUR upfront. Besu returned a transaction hash, the transaction sat in the pool (`txpool_besuTransactions` listed it; the sender's pending nonce was 1 while its latest nonce was 0) and was **never mined and never rejected** for 20+ minutes, so the client simply waited. A restart of all nodes cleared the pool. Observed once; the exact Besu rule (why it was accepted into the pool) was not investigated. It matters for the distribution oracle's gas balance (Router spec §10.4 item 3).

## 21. Group A on the follow-up networks: every live check passes on fresh twins with the identical genesis; the only failure is the A09 spec comparison

**Classification:** measurement. 15 follow-up networks were covered by 11 fresh networks whose genesis recipe is identical (`A-twin-equivalence.json`: 15/15 pairs equivalent — same alloc, config, gasLimit, extraData; only the genesis timestamp and the 6–7 storage slots *equal to it* differ). On each fresh network the check ran only after asserting that it was pristine (0 transactions, nonces 0): 65 assertions per G5 network (66 on the G6 network), **64 pass; the single failure is the A09 spec comparison (item 19)**; the critical-stop checks A07 and A08 are clean everywhere; A01 (sources, compile settings, runtime hashes) and A05(a) pass globally (11/11). Block period over the first 100 blocks: mean 3.0 s on all 11 (one network 3.04 s with a single 7 s gap). The genesis→block-1 gap (82–117 s) is the deliberately back-dated genesis timestamp, not a stall.
