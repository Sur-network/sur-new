# LIMITATIONS and open items

- All networks are single-host, multiple-process. This does not measure multi-host network
  latency, real geographic distribution, or load under real adversarial conditions.
- **Groups E and F:** not run in the first pass; run in the follow-up passes of 2026-10-03 (result table; FINDINGS.md items 9-18). What they do *not* establish: each F test ran once on a single-host network; F05's restarts used hard process kills; F06 used one late joiner; F07 was run twice (a capped 512 MB heap, where node5 ended with an `OutOfMemoryError`, and a default ~7.94 GB heap, where none was observed in about 36 minutes — FINDINGS.md item 18; the cause of the first outcome was not established). The coordinated crossing of X with **non-empty blocks and non-trivial F/M/X terms** is covered once, on Net-F6 (range `[1,149]`); F01/F02 themselves used empty blocks. **F04 on Net-F6 is an `eth_call` simulation, not a mined transaction** (one successful distribution per network before the 23 h lock; DEVIATIONS.md item 20). Group E is a synthetic benchmark by the document's own definition (TEST-ONLY-SEED).
- The real (uncompressed) `MIN_DISTRIBUTION_INTERVAL` (23h), `SHARE_CHANGE_MIN_INTERVAL` (180
  days), `RATE_CHANGE_DELAY` (7 days), `MIN_RATE_CHANGE_LEAD_BLOCKS` (201,600 blocks),
  `PROPOSAL_EXPIRY`/`RATE_VOTING_EXPIRY` (30 days), `CAP_CHANGE_TIMELOCK_DELAY` (7 days), and
  `BOARD_REFRESH_INTERVAL` (30 days) paths were **not exercised at their real values** for the
  scenarios that need them to actually elapse (D04, D05, the full rate-change path, the 180-day
  share-change unlock). Compressed-constant equivalents were exercised instead, on the clearly
  separated test-fork — see REPORT.md's per-ID table for exactly which rows are "fork-verified
  equivalent" vs a true NOT-RUN. The 180-day share-change re-unlock itself was not exercised even
  on the fork (not required by any listed test ID — see the compressed-constants table's own
  reasoning).
- Full cryptographic signer recovery (recovering every individual committed-seal signature's
  address via `ecrecover`, independent of the `miner`/proposer field) was not attempted this round.
  B07 was answered using the `miner` field plus the `extraData` byte-size shift at both
  validator-set transitions (see FINDINGS.md item 1) — strong, concrete, but circumstantial
  evidence of which set actually signed each block, not a full signature-by-signature audit of
  every committer. **In addition, B07's confirmation covers only 17 sampled blocks** (the two
  transition windows), not the full 4700+-block history of Net-B — the claim is scoped to what
  was actually inspected, not generalized to every block.
- **Independent §D accounting:** the full methodology (independent R/F/M/X/P extraction, conservation equation closed before sending, gates, BigInt expected amounts, post-distribution conservation) was executed in the follow-up pass for **D02 on a fresh network (Net-D3)** and for F02/F03/F04. It was **not** applied retroactively to the original Net-D D02, nor re-done for the fork's D04'/D05' (those rows keep their earlier scoping: `totalRewards` was taken from `maxRewardsForRange`). All of it relies on Besu's ~512-block state window (FINDINGS.md item 11): outside it Besu answers `null`/`[]` silently, so the same procedure cannot be repeated on a 27,600-block daily range from a pruned node.
- **Path L / C-L05-4's L4 step remains NOT-RUN.** The two halves are now evidenced separately — governance L1-L3 on the compressed fork (earlier) and the Besu transition + cap coordination at X on Net-F1 with a *seeded* history entry (follow-up) — but the combined real-time run (proposal → real 7-day delay → execute → ≥201,600 blocks → cross `startBlock` → settle) has not been executed, per the owner's instruction.
- B05 (two suspensions landing in the same block) was budgeted for up to 3 attempts per the
  document; depending on how much of the session budget remained when B04/B05 executed, fewer
  attempts than 3 may have been made — see the B05 result row for the actual attempt count.
- T02 (production genesis-builder tool) and the real RewardRouter oracle remain unimplemented and
  untested, exactly as the document itself states this round cannot and does not test them.
- Production `gasLimit`, the "actual reward exceeds cap for a past range" recovery path, and the
  rate-governance dashboard page remain open items per the document's own framing; this round's
  results do not resolve any of them.

- **A01–A13 on the follow-up networks:** see the third-pass limits at the end of this file.
- **A14 (now executed):** the static scan covers the 20 baseline genesis files against an expected alloc derived from a fresh deploy plus an analytically computed seed list (two slot kinds are checked by presence only: `validators[a].status`, FoundationDAO name strings); it assumes constructors write only plain state variables; the live leg proves the node's *block-0* state root equals the genesis file's alloc — it says nothing about the current state of the long-lived networks, and `debug_storageRangeAt`/`debug_accountRange` could not be used (they returned empty). Net-L01/L02/L04/L05 have no FoundationDAO seed by their build recipe (so C-L04-6 could not have been run there). The initial scan reported 61 false deviations on those four because my expectation ignored the recipe (disclosed in DEVIATIONS.md item 22).
- **F07 heap observation is finite and descriptive:** with the default heap the node was alive and no `OutOfMemoryError` was observed in about 36 minutes (FINDINGS.md item 18). This does not prove it would never run out of memory over longer periods, does **not** prove the absence of a memory leak (used heap was sampled 31 times: 2,049–5,524 MB), and the cause of the earlier crash with the 512 MB cap was not established.

- **Group A coverage by twins (third pass):** each live check ran on a fresh network with the identical genesis, not on the original network's own first block (impossible after state change); original networks are tied to their twin by genesis equivalence (`A-twin-equivalence.json`) and, for storage/extra accounts, by A14 (not repeated). A06–A10 and A15 were run as an extra. A15 has no numeric threshold in the brief. The A09 spec comparison fails on every network (FINDINGS.md item 19).
- **C-L04-6 (third pass):** one run on one fresh network without candidate C6; the case "re-added member re-votes on a proposal that is still pending and where it had voted" was not exercised (that proposal was already executed); eligibility was observed through `eth_call` and real transactions because `createdAtNonce` has no getter.
- **Path L remains not started:** only the plan exists (`PLAN-path-L-real-time.md`); durations, disk and memory in it are estimates, and the restart/keep-awake/historical-window options in it are unverified until a rehearsal.
