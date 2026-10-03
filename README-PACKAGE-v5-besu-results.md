# Package v5 — third follow-up pass of the Besu live test (C-L04-6, Group A coverage, path-L plan), recorded in the main documents, with the integrated evidence

## What this package is
One integrated, self-describing package (Plan-root relative paths; extract at the Plan root, then `sha256sum -c MANIFEST.sha256`). It has the same layout as the v4 package and **replaces it**:

1. **Ten Plan documents** (edited copies; the Plan working tree was NOT modified by this round — it is still at commit `f4d75c3`): the C-L04-6 result, the Group A coverage method and result, the A09-spec finding and the unaffordable-transaction observation recorded in the existing documents — `technical-design/sur-audit-2026-09-30-final-status.md`, `sur-master-open-items.md`, `sur-project-handoff-summary.md`, `sur-besu-live-test-brief-v4.md`, `sur-besu-test-status.md`, `offchain-services/sur-reward-router-spec.md`, `offchain-services/sur-genesis-builder-tool-spec.md`, `technical-design/sur-contracts-deploy-notes.md`; `economics/sur-tokenomics.md` and `technical-design/sur-contracts-oracles-accounts-report.md` are unchanged in this round.
2. **Diffs** against the Plan working tree: `evidence/diffs/v5-besu-results/` (Plan documents) and `evidence/diffs/v5-besu-results/evidence-package/` (the six changed evidence documents: REPORT, FINDINGS, DEVIATIONS, LIMITATIONS, QUESTIONS, README).
3. **Status table** generated from the report: `evidence/v5-besu-results/STATUS-TABLE.md` (89 rows; counts computed by script).
4. **Verification evidence**: `evidence/v5-besu-results/` (Plan state before this round, previous v4 root manifest, contracts-untouched check, stale-phrase search, hash comparison of the Plan files with the package copies, replaced-files list including the inner-manifest comparison). The extraction-test record cannot be inside the ZIP it tests; it is delivered next to the ZIP as `extraction-test.txt`, with the `.sha256` of the ZIP.
5. **The complete Besu evidence**: `testing-evidence/besu-live-test-v4-2026-10-03/` — report, findings, deviations, limitations, questions, result JSON, scripts, genesis files, node configs, raw node logs, baseline contract copy, **`PLAN-path-L-real-time.md`** (execution plan for the real-time path L — not executed), **`evidence/06-coverage/`** (Group A per-network table + `new-results-sha256.txt`, the sha256 of every file produced or changed by this pass). It has its own `MANIFEST.sha256` (relative to that directory) in addition to the root manifest.

## Relationship to earlier versions — what this package replaces
- **Replaces** `sur-besu-v4-results-integrated-package.zip` (sha256 `8680b482158e7d77ca87e749b84259c09ed6ae9e99c2a6606bc0dcb4b58124fe`; Plan commit `f4d75c3` contains its contents). It does not replace `sur-L05-incremental-package-v2.zip` or the v3 text-fix package. No contract, no policy and no earlier test script is changed.
- **Plan files it replaces:** the documents named above (before/after hashes in `evidence/v5-besu-results/replaced-files.txt`) **and the Plan-root `MANIFEST.sha256`** (the v4 root manifest, kept as `evidence/v5-besu-results/previous-MANIFEST-v4.sha256`). The v4 verification evidence (`evidence/v4-besu-results/`, `evidence/diffs/v4-besu-results/`) and `README-PACKAGE-v4-besu-results.md` stay in the Plan as history; their statements about "C-L04-6 not executed" and "73 rows" describe the v4 package and are superseded by this one.
- **Evidence directory:** same as v4 plus the new files of this pass and six changed documents. Raw evidence, scripts and logs of earlier passes are byte-identical to the v4 package **except** `logs/Net-F3/node1.log`, which gained start-up lines (DEVIATIONS.md item 28).

## Verification
Extract at the Plan root and run `sha256sum -c MANIFEST.sha256`. The package was test-extracted (a) into an empty directory and (b) over a copy of the Plan tree; the checks (root manifest, inner manifest, `new-results-sha256.txt`, contracts-unchanged comparison, counts recomputed from the extracted REPORT.md) are recorded in `extraction-test.txt` (next to the ZIP).

## Evidence classes (do not merge them)
| Class | Meaning |
|---|---|
| 1. Baseline | The six genesis contracts byte-identical to `contracts/` of the Plan, on real Besu 26.9.0 QBFT networks, single host, 5–6 node processes each; real values for every contract time constant |
| 2. Test-fork | Net-Fork only: three compressed `constant`s in a separate source tree (owner-authorised); **not baseline evidence** |
| 3. Simulation | `eth_call`, nothing mined — F04 repeated on Net-F6 and revert-message checks taken with `eth_call` |
| 4. TEST-ONLY-SEED | State written directly into genesis storage (rate history on Net-F1/F3/F6/E*, payees' `everActivated` on E*) |
| 5. Synthetic benchmark | Group E — cost measurement; not production capacity, not a gasLimit approval |

## Result and what stays open
Result table: **89 rows = 83 PASS, 1 FAIL, 1 NOT-RUN, 4 SUPERSEDED** (computed by `evidence/03-commands/count-results.js` and by the status-table generator). Compared with v4 (73 rows: 67 PASS / 2 NOT-RUN / 4 SUPERSEDED): C-L04-6 NOT-RUN → PASS (31/31 assertions on a fresh network with the 15-member FoundationDAO seed); 16 rows added (Group A coverage on the follow-up networks via fresh twin networks with proven genesis equivalence, 15/15): 15 PASS and **1 FAIL — A09-spec** (`lastBoardRefreshAt` is 0 on every network built by the test builder; the genesis-builder spec asserts the genesis timestamp; a test-tool/spec gap, not a contract defect).
**Not executed (the one NOT-RUN row):** the **combined real-time path L** (C-L05-4's L4 step). Only the plan exists (`PLAN-path-L-real-time.md`: duration ≈15 days, resources, outage/restart procedure, decisions and authorisations needed); nothing of it was started.
**Limits kept on executed rows:** Group A on the follow-up networks was run on fresh twin networks, not on the original networks' own first blocks (A14 not repeated); C-L04-6 is one run on one network; F04 on Net-F6 is a simulation; A14's limits; D04/D05 fork-only; B07 = 17 blocks; the F07 heap observation is one finite window.
**Observations recorded as specification notes (no design option chosen):** unaffordable (upfront gas) transactions stay pending silently; `lastBoardRefreshAt` in the genesis tool; plus the v4 operational findings.

## Status
No contract or policy was changed (`evidence/v5-besu-results/contracts-untouched-check.txt`), no fork was used in this pass, the real-time path L was not started. **This is not a production-readiness statement.** The four project-level open items (repair path for "actual reward > cap" on a past range; production gasLimit decision; RewardRouter implementation and tests; rate-governance page in the dashboard) remain open.

## Known stale reference left untouched
`sur-detailed-plan-and-rationale.md` (tracked in the Plan since commit `f8a6ae7`, not one of the ten documents of this package) still says at line 14 that the current code has not yet been tested on real Besu and at line 793 that the transition/restart assumption is untested. Both statements are **superseded** by `technical-design/sur-audit-2026-09-30-final-status.md` (section "نتایج آزمون Besu دور v4"); the file was not edited because that was not requested. (The v4 README called it "untracked"; it is tracked.)
