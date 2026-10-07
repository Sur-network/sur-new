# DEVIATIONS — round 6 (BlockRewardDistributor v2.2, Shanghai/Cancun)

Every item says who decided it. No contract line was changed; no policy was changed; the real-time path L was not started; nothing outside `testing-evidence/besu-live-test-v6-2026-10-07/` was written in the Plan.

## 1. Besu build: the release 26.9.0 binary, not `hyperledger/besu:26.9-develop-260f602` — [this session's own judgment call; question asked in QUESTIONS.md item 1]
The brief names the develop image. Docker Desktop was not running and the image is not on the machine; pulling it is a download I did not make without your explicit yes. All networks ran on `besu/v26.9.0/windows-x86_64/openjdk-java-25` (Temurin 25.0.4), the binary of rounds 1–5. Besu-specific rows (S1–S4, R1, T1–T3) therefore describe release 26.9.0.

## 2. `shanghaiTime` = 0 and `cancunTime` = 0 — [this session's own judgment call; QUESTIONS.md item 2]
The design document only says "both active in the genesis". Cancun header fields `excessBlobGas` 0, `blobGasUsed` 0 and `parentBeaconBlockRoot` zero were written into the genesis header; no `blobSchedule` was needed (the node started without it).

## 3. Test-fork constants — [this session's own judgment call; QUESTIONS.md item 4]
`hardhat-fork/contracts-testfork/BlockRewardDistributor.sol` = the Plan file plus exactly four constants (`evidence/00-baseline/r6-testfork.diff`, hashes in `r6-testfork-sha256.txt`): `MIN_DISTRIBUTION_INTERVAL` 23 h → 45 s, `RATE_CHANGE_DELAY` 7 d → 120 s, `MIN_RATE_CHANGE_LEAD_SECONDS` 7 d → 300 s, **`RATE_START_TOLERANCE_BLOCKS` 10,000 → 60** (the brief names the lead only). Reason for the last one: with 10,000 a chain of a few hundred blocks cannot show a range "entirely before the window", the "outside the window" revert, or two non-overlapping entries minutes apart. Evidence from Net-R6-R is **test-fork evidence**; Net-R6-S is baseline; Net-R6-T* are baseline contracts. The R rows that need the real 7-day durations (the lead, the delay, the 23-hour interval) are therefore mechanism evidence only.

## 4. Net-R6-S has a back-dated genesis timestamp (2026-09-30 23:59 UTC) — [this session's own judgment call]
So that the monthly board refresh of S5 could be repeated on a baseline network (the founding board's month is older than the live month, as in round 5's Net-R5-B). The genesis→block-1 gap is about a week; nothing in S depends on it.

## 5. Group R: the plan to approve an activation time for the third transition in time was missed; R6 was redesigned — [this session's own judgment call]
The genesis of Net-R6-R contained three timestamp-keyed transitions: A1 (3 SUR), A2 (4 SUR) and TC3 (5 SUR) at A3 − 90 s, meant for a governed entry E3 (activation A3) with Besu 90 s earlier than the approved time. The earlier parts of the script ran late (see 6), so when part 5 started A3 was closer than the 300 s lead and E3 could not be proposed. TC3 passed with **no approved entry**; the chain paid 5 SUR from block 1071. R6 was therefore observed as: (a) an ungoverned transition (what the contract does with the real reward), then (b) a governed entry approved AFTER the fact with an activation time 760 s later than Besu's real change (E3b). This covers the brief's R6 question (Besu's transition at a time that is not the approved activation time), in the "earlier" direction and with a gap far larger than the tolerance; the "later" direction was not run.

## 6. Faults of mine during group R (all disclosed; none changed a contract result) — [this session's own judgment call]
- **Part 2 stalled and was stopped.** It ran `trace_block` over ranges that lie outside Besu's ~512-block historical-state window, where Besu answers `[]` silently (round-4 finding 11). I stopped it, added a documented fallback (for blocks without a trace reward entry the reward is the genesis transition table applied to the block timestamp: **derived, not measured**; 103 of the 470 blocks of range D0 were derived, recorded in `Net-R6-R-part2.json`), recorded E2's ids by hand in the state file (`id2` 3 = the third proposal, `est2` 763 as printed in the stopped run's log, `pred2` = est2 + 37 = 800) and re-ran part 2 from its middle. Ranges Da, Db, Dc, Dd and the ranges of part 5 were measured (inside the window); only D0 contains derived blocks.
- **R7.1** (part 1): my first look at the overlapping proposal Px happened before Px's own 120 s delay had elapsed, so `executeRateChange` reverted with the DELAY message instead of the overlap message. The row stays FAIL in `Net-R6-R-part1.json`; it is replaced by R7.1b/R7.1c (`Net-R6-R-part1b.json`; the first, too-early try of the supplement is kept as `…part1b-run1-too-early.json`).
- **R4.3 and R8.5** (part 3): part 3 started after A2, so its range 4 [532, 848] ran into E2's provisional window and across the second boundary; my expectation (3 SUR × blocks) was wrong. The contract accepted the distribution with the real reward (999 SUR) and rejected cap + 1. R4.3b (`Net-R6-R-part3b.json`) verifies the contract's cap for that range at the block before the distribution against an independent per-block sum (1,097 SUR). The two rows stay FAIL (script expectation) in `Net-R6-R-part3.json`.
- **Part 4** first crashed (`invalid range`: the range 4 of part 3 had already passed the second boundary); the script was patched to skip the already done steps and re-run (`Net-R6-R-part4-CRASHED.json` keeps the 4 assertions of the first run, `Net-R6-R-part4.json` the rest).
- **R5.1** (premature certification) was asserted in the first (stopped) run of part 2 only (`logs/r6-scripts/Net-R6-R-part2-run1-stopped.out`).
- **Group S, second script** (`Net-R6-S-groupS2.json`): rows B3 and B4 FAILED because a second distribution is refused for 23 hours on the baseline contract ("too soon since last distribution") — a precondition I overlooked; they are reported BLOCKED in REPORT.md, the JSON keeps the FAIL.

## 7. Net-R6-T / T2 / T3 / T4 — [this session's own judgment call]
T1 on Net-R6-T (7 nodes). T2 and T3 are two short networks with 5 of the 7 nodes running (quorum 5 of 7). A fourth network (Net-R6-T4, 5 nodes) was added to observe the validator-mode analogue of T3. Net-R6-T2's first read happened before its node was up (kept as `…T2-run1-node-not-up-yet.out`).

## 8. Group X not run — [this session's own judgment call; QUESTIONS.md item 5]
It is optional and the main groups took the session; the four rows are NOT-RUN with that reason.

## 9. Machine memory — [this session's own judgment call]
Nodes of finished networks were stopped before the next network was built, and T2/T3/T4 ran with 5 of the 7 nodes, to fit the machine's memory. No other deviation.
