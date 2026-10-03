# Package v4 — Besu live-test results for the CURRENT code, recorded in the main documents, with the integrated evidence

## What this package is
One integrated, self-describing package (Plan-root relative paths; extract at the Plan root, then `sha256sum -c MANIFEST.sha256`):

1. **Ten edited Plan documents** (the results, evidence classes, operational findings and open items of the Besu round of 2026-10-02/03 recorded in the existing documents — no new design document):
   `technical-design/sur-audit-2026-09-30-final-status.md` (new section "نتایج آزمون Besu دور v4"), `sur-master-open-items.md` (§28 table row + new sub-section ج),
   `offchain-services/sur-reward-router-spec.md` (§9 rows 5-8, §10.2 evidence notes, §10.3 verified facts, new §10.4), `technical-design/sur-contracts-deploy-notes.md` (new closing section),
   `technical-design/sur-contracts-oracles-accounts-report.md` (oracle gas-balance note), `offchain-services/sur-genesis-builder-tool-spec.md` (open decision on `transitions.qbft`),
   `economics/sur-tokenomics.md` (one sentence), `sur-besu-test-status.md`, `sur-besu-live-test-brief-v4.md` and `sur-project-handoff-summary.md` (pointers/status lines).
2. **Diffs** of every changed file: `evidence/diffs/v4-besu-results/` (the ten Plan documents) and `evidence/diffs/v4-besu-results/evidence-package/` (the five changed evidence documents: REPORT, FINDINGS, DEVIATIONS, LIMITATIONS, QUESTIONS).
3. **Status table** generated from the report: `evidence/v4-besu-results/STATUS-TABLE.md` (73 rows; counts computed by script).
4. **Verification evidence**: `evidence/v4-besu-results/` (state of the Plan before this round, previous v3 manifest, contracts-untouched check, stale-phrase search, hash comparison of the Plan files with the package copies, replaced-versions list). The extraction-test record cannot be inside the ZIP it tests; it is delivered next to the ZIP as `extraction-test.txt`, together with `sur-besu-v4-results-integrated-package.zip.sha256`.
5. **The complete Besu evidence** for this round: `testing-evidence/besu-live-test-v4-2026-10-03/` — report, findings, deviations, limitations, questions, result JSON, scripts, genesis files, node configs, raw node logs, baseline contract copy. It has its own `MANIFEST.sha256` (relative to that directory) in addition to the root manifest.

## Relationship to earlier versions — what this package replaces
- **It does NOT replace `sur-L05-incremental-package-v2.zip` or the v3 text-fix package; it is applied ON TOP of them** (same convention as v3). No contract, no test script of v2 and no policy is changed.
- **Plan files it replaces:** the ten documents listed above (their working-copy state at the start of this round is in `evidence/v4-besu-results/replaced-files.txt` with sha256 before/after), **and the Plan-root `MANIFEST.sha256`** (the v3 manifest, kept as `evidence/v4-besu-results/previous-MANIFEST-v3.sha256`). Note: at the start of this round the v3 manifest **already failed on three files** (`sur-besu-test-status.md`, `sur-master-open-items.md`, `technical-design/sur-audit-2026-09-30-final-status.md`, edited after v3; `evidence/v4-besu-results/plan-state-before-round.txt`). This package's manifest covers only this package's files, as v2's and v3's did.
- **Besu evidence it replaces:** `besu-test-v4-evidence-package.tar.gz` (902 files, sha256 `05020dd7fdf4246127f78aef687bad80adaea05a8f55e0b6a6f7c947f167fd21`, delivered 2026-10-03) and the earlier deliveries of the same round (547-file first delivery, 775-file first follow-up). The evidence directory here is that package with **five corrected documents** (REPORT, FINDINGS, DEVIATIONS, LIMITATIONS, QUESTIONS; its README is unchanged) (memory claims scoped, stale "Group F not run" mentions fixed, evidence classes and an exact open-items list added); the raw evidence, scripts and logs are byte-identical to the 902-file package (`replaced-files.txt` lists the manifest comparison).
- The ten Plan documents in the Plan working tree already contain these edits and are byte-identical to the copies in this package (`evidence/v4-besu-results/plan-vs-package-hash-check.txt`), so extracting is idempotent for them; extraction adds the evidence directory, diffs, status table, README and the new manifest.

## Verification
Extract at the Plan root and run `sha256sum -c MANIFEST.sha256`. The package was test-extracted (a) into an empty directory and (b) over a copy of the Plan tree; the manifest checks and the contracts-unchanged comparison are recorded in `extraction-test.txt` (delivered next to the ZIP, not inside it). Size: about 113 MB unpacked, of which about 83 MB are raw Besu node logs.

## Evidence classes (do not merge them)
| Class | Meaning |
|---|---|
| 1. Baseline | The six genesis contracts byte-identical to `contracts/` of the Plan, on real Besu 26.9.0 QBFT networks, single host, 5–6 node processes each; real values for every contract time constant |
| 2. Test-fork | Net-Fork only: three compressed `constant`s in a separate source tree (owner-authorised) — C-L05-4 L1–L3, D04, D05 and three D01 cases; **not baseline evidence** |
| 3. Simulation | `eth_call`, nothing mined — F04 repeated on Net-F6 (simulation only) and revert-message checks taken with `eth_call` |
| 4. TEST-ONLY-SEED | State written directly into genesis storage (rate history on Net-F1/F3/F6/E*, payees' `everActivated` on E*) |
| 5. Synthetic benchmark | Group E — cost measurement; not production capacity, not a gasLimit approval |

## Result and what stays open
Result table: **73 rows = 67 PASS, 2 NOT-RUN, 4 SUPERSEDED** (computed by `evidence/03-commands/count-results.js` inside the evidence directory and by the status-table generator).
**Not executed (open):** C-L04-6 (optional) and the **combined real-time path L** (C-L05-4's L4 step). **Limits kept on executed rows:** F04 on Net-F6 is a simulation; A14's limits (static scan of genesis files, live leg = block-0 state root only, presence-only slots, constructors assumed to write plain variables); D04/D05 fork-only; B07 = 17 blocks; A01–A13 not repeated live on the follow-up networks; the F07 heap observation is one finite window (about 36 minutes, no OutOfMemoryError observed with the default heap; no leak claim; cause of the earlier crash not established).
**Operational findings recorded as specification notes (design options not chosen):** transition rollout to every node including newcomers; alarm for actual-reward < approved rate; sufficient historical data for the Router (Besu answers `null`/`[]` silently outside the ≈512-block window); gas-balance funding of the oracle; behaviour and memory use of a node with a mismatched genesis.

## Status
No new test was run for this package, no contract or policy was changed (`evidence/v4-besu-results/contracts-untouched-check.txt`). **This is not a production-readiness statement.** The four project-level open items (repair path for "actual reward > cap" on a past range; production gasLimit decision; RewardRouter implementation and tests; rate-governance page in the dashboard) remain open; no package closes them.

## Known stale reference left untouched
`sur-detailed-plan-and-rationale.md` (an untracked file in the Plan working tree, not part of any package) still says at lines 14 and 793 that the transition/restart assumption is unverified; it was not edited because it is the owner's working file. Its statements are superseded by `technical-design/sur-audit-2026-09-30-final-status.md` (section "نتایج آزمون Besu دور v4").
