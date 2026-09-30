# SUR — Round 3: `everActivated` reward-payment policy, real Besu/QBFT test

**Scope**: per `sur-besu-test-status.md` v3 (2026-09-30), this round tests ONLY the new
"pay the real block-producer directly regardless of later exit/suspension" reward policy —
the `everActivated` mapping in `ValidatorsRegistry.sol`, its use in `BlockRewardDistributor.sol`,
and the genesis-seed-helper fix in `ValidatorsRegistry_GenesisSeed.sol`. Everything proven in
round 2 (membership lifecycle, board, treasury, N04 recovery, FoundationDAO, IdentityRegistry,
ServiceStaking) was **not** re-tested, per the v3 document's own §0.

All of Phase A through Phase E below ran against a **real, fresh Hyperledger Besu 26.9.0 QBFT
network** (chain ID 424244) built from the **current** contract source — never Hardhat's simulated
EVM. Priority 2 (optional §1.2 items) was **not attempted** — see "Deviations" at the end; per the
v3 document's own prioritization this is an acceptable, explicitly-flagged omission, not a gap in
the mandatory scope.

## Network setup summary

- 3 genesis-seeded founders (`founder1`, `founder2`, `founder3`) + 1 post-genesis-joined validator
  (`newValidator1`), each backed by a real Besu node with the matching key — 4 nodes total, kept
  ≥ the active-validator count at every point (per round 2's quorum-deadlock lesson).
- `extraData` = 0 validators (contract-validator mode); all EVM hard-forks = block 0;
  `zeroBaseFee: true`; `static-nodes.json` (not `--bootnodes`) — per round 2's operational findings,
  re-verified working here.
- Genesis-injected contracts (6, exactly per §2.2.1): `ValidatorsRegistry`, `ValidatorsBoard`,
  `ValidatorsTreasury`, `BlockRewardDistributor`, `FoundationDAO`, `IdentityRegistry`.
  `ValidatorsBoard`/`FoundationDAO` were seeded genesis-**empty** (no members) — out of this
  round's scope; both have unconditional `receive() external payable`, so
  `BlockRewardDistributor`'s plain `.call{value:...}` transfers to them succeed regardless of
  internal membership state.
- `ValidatorsRegistry_GenesisSeed.sol` deployed and extracted **exactly as-is** (per §2.2.3) — no
  manual `everActivated` overlay. Storage for the 3 founders (`validators[addr]`,
  `activeIndex[addr]`, `everActivated[addr]`, `activeValidators`) was read directly off the
  deployed helper via `eth_getStorageAt` and copied into the real contract's genesis alloc at the
  identical slot numbers (the helper's `__gap1` reservation makes this valid), then round-trip
  verified on a fresh `ValidatorsRegistry` deploy on Hardhat before ever touching Besu.
- `verifier` / `distributionOracle` overlaid to test-controlled keys; `perPaymentCap`/`periodCap`
  picked up automatically via the deploy-and-extract method (their non-zero initializers run on
  the temp Hardhat deploy). Test-only timing constants shortened (probationPeriod=180s,
  exitCooldown=90s, recoveryPeriod=90s, `MIN_DISTRIBUTION_INTERVAL`=60s, and others not exercised
  this round) — same category of substitution as round 2, required to fit real wall-clock waits
  into one session; none of the shortened areas were this round's target.

## §3 storage-slot independent verification (before touching Besu)

The v3 document claims `everActivated` sits at storage slot 20. Verified independently by
enumerating `ValidatorsRegistry.sol`'s full sequential state-variable declaration order (excluding
every `constant`, which occupies no storage slot):

`validators`(0) → `paidValidatorCount`(1) → `verifier`(2) → `activeValidators`(3) →
`activeIndex`(4) → `lastEconomicParamChangeTime`(5) → `entryThresholdBase`(6) →
`growthFactorPerValidator`(7) → `membershipFeeBps`(8) → `maxEntriesPerWindow`(9) →
`entryWindowSeconds`(10) → `probationPeriod`(11) → `recoveryPeriod`(12) → `slashBps`(13) →
`exitCooldown`(14) → `demotionEpochs`(15) → `currentDemotionEpochId`(16) → `windowStart`(17) →
`entriesInWindow`(18) → `massFailureChecked`(19) → **`everActivated`(20)**.

Confirmed: **slot 20 is correct.**

Also confirmed by direct source read: `BlockRewardDistributor.sol:705` —
`require(REGISTRY.everActivated(validator), "BlockRewardDistributor: address was never a legitimate validator");`
(checks `everActivated`, not `isValidator`).

---

## Phase A — genesis verification (everActivated from block zero)

**Wall-clock**: instantaneous once the network was live (~04:16, 2026-09-30).

Queried directly against the real Besu network at `blockTag: 0` (genesis):

| Founder | `everActivated()` getter | `isValidator()` getter | manual slot `keccak256(addr,20)` | raw storage @block0 |
|---|---|---|---|---|
| founder1 `0x22B2…78c7` | **true** | **true** | `0x50ac68cd…41859` | `0x…0001` (true) |
| founder2 `0x0F8D…365a` | **true** | **true** | `0xf74d41a2…d29e` | `0x…0001` (true) |
| founder3 `0x9135…60d5` | **true** | **true** | `0x790d33be…ab5cc` | `0x…0001` (true) |

`getValidators()` @block0 = exactly the 3 founders. `verifier()` and `windowStart()` both read back
correctly from the test-fork overlay. **All checks passed** — the genesis-seed-helper fix is
proven: founders get `everActivated=true` from block zero on a real chain, confirmed both via the
public getter and via independent manual storage-slot computation (not just trusting the getter).

Full raw result: [logs/phaseA-result.json](logs/phaseA-result.json)

---

## Phase B — first real `distributeRewards()` (founders)

**Wall-clock**: 2026-09-30T04:17:01.931Z. **Time spent this phase**: ~1 minute (waiting for blocks
to accumulate + the call itself).

- Range: blocks 1–26 (26 blocks, all 3 founders producing).
- Block counts: founder1=9, founder2=9, founder3=8.
- `distributionOracle` called `distributeRewards({1,26}, [founder1,founder2,founder3], [9,9,8], 54 ether, 0)`.
- **tx**: `0x9c65fb9f68cd1a4e527f6e0dcb02ca43892cea6794c2b74fe5fbb8e3f006091b`
- **status**: `1` (success, no revert) — **gasUsed**: `709386`

| Address | Before | After | Delta |
|---|---|---|---|
| founder1 | 2,000,000.0 | 2,000,009.346153846153846153 | **+9.346153846153846153** |
| founder2 | 2,000,000.0 | 2,000,009.346153846153846153 | **+9.346153846153846153** |
| founder3 | 2,000,000.0 | 2,000,008.307692307692307692 | **+8.307692307692307692** |
| FoundationDAO | 0 | 8.1 | **+8.1** |
| ValidatorsTreasury | 0 | 18.900000000000000002 | **+18.9** |

Formula check (totalRewards=54, FOUNDATION_SHARE_BPS=1500, validatorDirectShareBps=5000):
foundation expected = 54×15% = **8.1** ✅ exact match. Validator-direct pool = 54×50% = 27, split
9/26, 9/26, 8/26 → **9.346…, 9.346…, 8.307…** ✅ exact match to the wei. Treasury remainder =
54−8.1−27 = **18.9** ✅ exact match.

Full raw result: [logs/phaseB-result.json](logs/phaseB-result.json)

---

## Phase C — mid-work exit, direct full payment

**Wall-clock**: exit tx 2026-09-30T04:17:36.490Z; real distribution 2026-09-30T04:18:51.153Z.
**Time spent this phase**: ~2 minutes (includes the 60s `MIN_DISTRIBUTION_INTERVAL` wait).

1. founder3 mined more blocks as a normal Active validator, then called `requestExit()`:
   - **tx**: `0x04cd52041effeac15dcd2ae452a942fca0c364a3ac07c5df4ea484fc4c8679fc`, **status 1**,
     **gasUsed 110174**, mined in block 40.
   - Confirmed immediately: `isValidator(founder3)` flips to **false**, `getValidators()` drops to
     2 entries (founder1, founder2) — P04's "immediate removal" semantics confirmed live.
2. Range 27–61 (35 blocks) settled with founder3 **still included** in the payout list:
   block counts founder1=15, founder2=15, founder3=5 (all mined before its exit at block 40).
   - **tx**: `0x10517d55eda38e55ddb34ce8be029918ce9f631b5582ae1535c7f539eba62a6e`
   - **status**: `1` — **gasUsed**: `487371`

| Address | Delta | Expected (proportional to blocks) |
|---|---|---|
| founder1 (15 blocks) | +32.562 | 32.562 ✅ |
| founder2 (15 blocks) | +32.562 | 32.562 ✅ |
| founder3 (5 blocks, **exited, isValidator=false**) | **+10.854** | 10.854 ✅ |
| FoundationDAO | +22.7934 | 15% of 151.956 = 22.7934 ✅ |
| ValidatorsTreasury | +53.1846 | remainder ✅ |

**founder3 received its full, exact proportional share despite `isValidator()==false`** — no
revert, no zeroing, and founder1/founder2 received only their own genuine shares (no windfall of
founder3's portion). This is the core Phase-C proof.

Full raw results: [logs/phaseC-exit-result.json](logs/phaseC-exit-result.json),
[logs/phaseC-distribute-result.json](logs/phaseC-distribute-result.json)

---

## Phase D — reject a never-activated address

**Method**: `distributeRewards.staticCall(...)` (read-only simulation against live chain state —
correct way to observe a revert reason without mutating state or wasting a real settled range).

First attempt (inside the same range/parameters as Phase C, before waiting long enough) hit the
document's own documented fallback case exactly as warned: **`"BlockRewardDistributor: too soon
since last distribution"`** — confirming `MIN_DISTRIBUTION_INTERVAL` hadn't elapsed yet, not the
fake-address check. Retried after clearing that gate, with a fresh dummy address (`fakeAddress`,
never `recordActivation`'d) included with nonzero `blocksMined`:

- **Revert reason (exact, decoded from the contract's raw revert data)**:
  `"BlockRewardDistributor: address was never a legitimate validator"`
- Matches the required message **exactly**.

Full raw result: [logs/phaseD-result.json](logs/phaseD-result.json)

---

## Phase E — `everActivated` persistence after a real `withdrawStake()`

**Wall-clock**: join 2026-09-30T04:20:46.539Z → activate 04:23:51.134Z (180s real probation wait)
→ exit 04:24:22.807Z → withdraw 04:25:57.076Z (90s real exit-cooldown wait) → final distribution
04:29:12.114Z. **Time spent this phase**: ~8.5 minutes (dominated by real wall-clock waits).

1. **Join**: `newValidator1` (not a founder) called `requestMembership()` paying
   `currentEntryThreshold()` (500,000 ether) + `currentMembershipFee()` (20,000 ether) = 520,000
   ether. **tx**: `0x2b4a9a381e035a4bec99b5abc6fc3cebf7494d2c0254f2c3f0aa9a0df4464c52`, **status 1**,
   gasUsed 213338. Status → Probation.
2. **Activation**: after the real 180s probation period, `verifier` called `recordActivation()`.
   **tx**: `0x497803540c785a3dc49ea4d0bc6c7557b4d76abfe36cf08c6deee9aa0123aa34`, **status 1**,
   gasUsed 219084, block 165. Confirmed: `isValidator=true`, `everActivated=true`,
   `getValidators()` now includes `newValidator1` (3 active: founder1, founder2, newValidator1).
3. `newValidator1` mined blocks as Active (4 blocks, up to block 175), then called
   `requestExit()`. **tx**: `0xc7de58beb80312d8a4e826eadeb2df8bd249161bc6c62939690d68fd8ea00e51`,
   **status 1**, block 175.
4. After the real 90s exit cooldown, `newValidator1` called `withdrawStake()` — a **real**
   withdrawal that fully deletes `ValidatorInfo`.
   **tx**: `0xbd2ceda660811f7669e58b122981b096683e8e15b53ae5bec2141f2bbb50adbe`, **status 1**,
   block 207. Balance delta (net of gas): **+499,993.2256 ether** (its full locked collateral).
   - **`getValidatorInfo(newValidator1)` after withdrawal**: `(status=0/None, lockedStake=0,
     periodStartedAt=0, demotedAt=0, pendingSlashEpoch=0, isPaidEntrant=false)` — fully cleared,
     exactly as `delete validators[msg.sender]` guarantees.
   - **`everActivated(newValidator1)` after withdrawal**: **true** — survives the deletion.
5. **Final distribution**, called AFTER the full withdrawal (range 62–255, capped short of the
   then-current block to stay under `BlockRewardDistributor`'s physical-maximum sanity check —
   see "Unexpected findings" below), with `newValidator1` still included (4 blocks mined before
   its exit):
   - **tx**: `0x237b68dd7396acc816cc4957cf1cfafee8c1cb3d47880edf502240d1bd8326a7`
   - **status**: `1` — **gasUsed**: `658871`

| Address | Delta | Note |
|---|---|---|
| founder1 (95 blocks) | +9,888.814432989690721649 | reward share (95) + fee share (9,793.814…) |
| founder2 (95 blocks) | +9,888.814432989690721649 | same |
| **newValidator1 (4 blocks, fully withdrawn — status=None)** | **+416.371134020618556701** | reward share (4) + fee share (412.371…) |
| FoundationDAO | +58.2 | 15% of totalRewards (388) |
| ValidatorsTreasury | +135.8 | remainder |

This distribution's fee component is unusually large because `newValidator1`'s one-time 20,000
ether membership fee (paid during its `requestMembership()` in step 1) was still sitting in
`pendingMembershipFees` and got folded into this call's `effectiveTotalFees` — fees are split
proportionally by blocks mined with **no** foundation/treasury cut (per the contract's documented
design, `sur-tokenomics.md` §6), unlike `totalRewards`. Verified exactly: reward share (2
ether/block × range size × validatorDirectShareBps 50%, split 95/95/4 of 194) + fee share (20,000
ether split 95/95/4 of 194) reconciles to the wei for every address, including the 15%-of-rewards
foundation share and the exact remainder to treasury.

**`newValidator1` — with a fully deleted `ValidatorInfo` (status=None) and no longer appearing in
any active-set or membership bookkeeping — still received its full, exact proportional payment.**
This is the strongest possible proof that `everActivated`, not `isValidator()` and not any live
`ValidatorInfo` field, is what gates payment eligibility.

Full raw results: [logs/phaseE-join-result.json](logs/phaseE-join-result.json),
[logs/phaseE-activate-result.json](logs/phaseE-activate-result.json),
[logs/phaseE-exit-withdraw-result.json](logs/phaseE-exit-withdraw-result.json),
[logs/phaseE-distribute-result.json](logs/phaseE-distribute-result.json)

---

## §3 checklist — final results

| مورد | نتیجه‌ی مورد انتظار | نتیجه |
|---|---|---|
| `everActivated(founder)` از بلاک صفر برای هر مؤسسِ genesis‌شده | `true` | ✅ Phase A — getter + manual slot 20 computation, all 3 founders |
| `isValidator(founder)` از بلاک صفر | `true` | ✅ Phase A |
| اولین `distributeRewards()` با مؤسسان در فهرست پرداخت | موفق (`status=1`)، بدون revert | ✅ Phase B — tx `0x9c65fb9f…6091b` |
| ولیدیتوری که بین تولید بلاک و توزیع خارج/معلق شده | پرداخت مستقیم و کامل می‌گیرد | ✅ Phase C — tx `0x10517d55…a62a6e`, founder3 got exact 10.854 ether despite `isValidator=false` |
| آدرس هرگز-فعال‌نشده در فهرست پرداخت | رد با پیام دقیق `"address was never a legitimate validator"` | ✅ Phase D — exact revert string confirmed |
| `everActivated` بعد از `withdrawStake` واقعی | همچنان `true` | ✅ Phase E — tx `0xbd2ceda6…0adbe`; `getValidatorInfo` fully cleared, `everActivated` still true, AND a later distribution paying it (tx `0x237b68dd…26f1c1`) succeeded |
| (اختیاری) خروج بدون پرونده، تساوی رأی هیأت، جداسازی P05 | طبق بخش ۱.۲ | 🔶 left open, per this document's prioritization (Priority 1 consumed the full test session) |

---

## Unexpected findings

1. **My own setup bug — genesis timestamp initially set in the future.** The first genesis.json
   used a timestamp 30 minutes ahead of the actual moment of writing it (intended as buffer for
   setup time that in fact took far less). Since a QBFT block's timestamp must be ≥ its parent's,
   block 1 could never be produced until real wall-clock time caught up — the network sat at block
   0 for ~15 minutes with peers connected and no errors logged, which looked identical to a stalled
   consensus but was actually just waiting for real time to pass. **Not a contract or Besu bug** —
   fixed by rebuilding `genesis.json` with a timestamp in the past and wiping all 4 nodes' data
   directories for a clean restart (all 4 simultaneously, per round 2's "restart all nodes
   together" rule, even though this was a fresh boot rather than a mid-chain recovery).
2. **`--sync-min-peers` is silently ignored in FULL sync-mode** ("`--sync-min-peers is ignored in
   FULL sync-mode`", logged by Besu itself) — a red herring encountered while diagnosing #1. The
   recurring "Unable to find sync target. Waiting for 5 peers minimum" log line is normal,
   non-blocking full-sync bootstrap chatter and does **not** gate BFT block production (confirmed:
   it also appears, harmlessly, during round 2's mid-chain restarts where blocks resumed within
   seconds).
3. **`BlockRewardDistributor`'s physical-maximum sanity check (`_checkPhysicalMaximum`, a real,
   intentional safety gate — not a bug) tripped twice in Phase E.** This network's actual block
   cadence ran slightly faster than the nominal `blockperiodseconds=3` (observed ~2.95s/block
   average), so naively declaring `toBlock=currentBlock-1` after a long wait (accumulated for the
   probation/exit-cooldown waits) reported more blocks than `elapsed / MIN_BLOCK_PERIOD_SECONDS`
   allowed. Fixed in the test script by capping the declared range. Worth flagging upstream: the
   real off-chain `RewardRouter` oracle (per `sur-reward-router-spec.md`) should apply the same
   defensive capping if a real gap between distribution calls ever lets blocks accumulate faster
   than the nominal period assumes.
4. **My own test-script bug (not a contract bug)**: the first Phase E distribution attempt passed
   `totalRewards = BlockRewardDistributor's full raw wallet balance`, which unintentionally
   included `newValidator1`'s pending 20,000 ether membership fee — a value the contract tracks
   **separately** (`pendingMembershipFees`, folded into `effectiveTotalFees` inside
   `_prepareEpoch`, not into `totalRewards`). This double-counted the fee against the
   `totalRewards + effectiveTotalFees <= balance` check and reverted with `"insufficient contract
   balance"`. Fixed by computing `totalRewards` as pure block-reward accrual (2 ether/block ×
   range size), matching the oracle's documented responsibility to compute `totalRewards` from
   `trace_block` "reward" entries only. Once fixed, the membership fee correctly flowed through as
   a per-block-proportional **fee** share (see Phase E's table) — an incidental but exact
   confirmation of the fee-folding design.

## Deviations from the v3 document

- Used exactly 3 founders (the document's stated minimum — "at least 3, not necessarily all 7"),
  each backed by a real node.
- `ValidatorsBoard` and `FoundationDAO` were genesis-seeded with **zero** members (fully empty) —
  out of this round's scope; confirmed this has no effect on `BlockRewardDistributor`'s plain-value
  transfers to their addresses (both have unconditional `receive()`).
- `windowStart`/`deployTime` were hardcoded in the test-fork source to `1790742970`, but the actual
  genesis block ended up at `1790741696` (≈21 minutes earlier) due to finding #1 above (the
  original future-timestamp mistake was corrected by changing `genesis.json`'s top-level
  `timestamp` field only — the already-compiled contract constants were left as originally set,
  since redoing the full extraction/compile cycle would have cost more time than the mismatch is
  worth). Confirmed **no functional impact**: `_enforceRateLimit()`'s reset condition
  (`block.timestamp >= windowStart + entryWindowSeconds`) never fires on this network regardless,
  which trivially keeps `entriesInWindow` at its correct default of 0 for our single new-entrant
  test; `deployTime`'s only use (`_checkPhysicalMaximum`) is skipped entirely for epoch 0 and uses
  `lastDistributionTime` (a real on-chain value, not `deployTime`) for every epoch after that.
- Priority 2 (optional §1.2 items — exit without a pending case, an exact board-reselection tie
  vote, isolating the P05 check from `MIN_DISTRIBUTION_INTERVAL`) was **not attempted**. Priority 1
  alone required five real wall-clock waits (probation, exit cooldown ×2, and the distribution
  interval multiple times) that consumed the full test session. Per the document's own explicit
  prioritization language, this is recorded here rather than silently skipped.
- Standard test-only timing shortenings applied (see "Network setup summary") — same category
  already established and accepted in round 2, applied only to areas this round does not test.

## Wall-clock time spent

| Phase | Time |
|---|---|
| Source verification (slot-20 independent check, revert-string confirmation, genesis-seed-helper review) | ~15 min |
| Network build (accounts, test-fork, compile, genesis extraction/round-trip verify, node setup) | ~10 min |
| Network launch + genesis-timestamp bug diagnosis and fix | ~15 min |
| Phase A | <1 min |
| Phase B | ~1 min |
| Phase C | ~2 min |
| Phase D | ~1 min (interleaved with Phase C) |
| Phase E | ~8.5 min (dominated by real 180s probation + 90s exit-cooldown waits) |
| **Total** | **~50 min** |

## Deliverables

- This report: `REPORT.md`
- Final genesis: [besu/genesis.json](besu/genesis.json)
- Per-phase raw JSON evidence: `logs/phase{A,B,C,D,E}*-result.json`
- Node logs: `logs/node{1,2,3,4}.log`
- Test accounts (local dev-chain only, plaintext private keys, never reused anywhere real):
  `accounts.json`
- All 4 Besu nodes are currently **left running** for independent inspection
  (RPC: `http://127.0.0.1:865{1,2,3,4}`), current chain height 250+. Stop with `taskkill //F //IM
  java.exe` (Windows) when no longer needed.
