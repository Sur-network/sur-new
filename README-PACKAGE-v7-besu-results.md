# Package v7 (final) — Besu live-test results, fourth pass, with a documentation-only correction

## What changed since v6 (documentation only)
Owner instruction 2026-10-04: **writing `lastBoardRefreshAt = network.genesisTimestamp` for a seeded board, and asserting it, in the PRODUCTION genesis tool is not an open decision.** It is an existing project requirement (P01; genesis-builder spec §4.2.1; deploy-notes item 4) and part of the remaining implementation of **T02** (the production genesis tool, not implemented). v6 had listed it as an open decision (and QUESTIONS.md item 12 asked whether the spec should change); that wording is corrected everywhere it appeared. **No test was run, no contract, policy, spec requirement or test result changed.**

Documents corrected:
- Plan: `sur-master-open-items.md` (the row is removed from the owner-decisions table and folded into the T02 implementation row), `technical-design/sur-audit-2026-09-30-final-status.md` (T02 row of the status table, finding 9, open-items lists), `offchain-services/sur-genesis-builder-tool-spec.md` (comment under the assertion), `technical-design/sur-contracts-deploy-notes.md`, `sur-project-handoff-summary.md`.
- Evidence directory (`testing-evidence/besu-live-test-v4-2026-10-03/`): `QUESTIONS.md` item 12 is **withdrawn** (kept, not renumbered), `FINDINGS.md` items 19 (classification no longer says "spec ambiguity") and 22 (new bullet on T02), `LIMITATIONS.md`, `REPORT.md` (limits bullet + closing note), `README.md` (closing note). The status table `evidence/v7-besu-results/STATUS-TABLE.md` is regenerated from REPORT.md (counts unchanged).

## What this package is
One integrated, self-describing package (Plan-root relative paths; extract at the Plan root, then `sha256sum -c MANIFEST.sha256`). Same layout as v6; **it replaces v6**:
1. The ten Plan documents of this series, taken from the Plan working tree (Plan HEAD `bb03d3f` — which already contains the v6 package and the owner's later edits to other documents — plus the corrections above, uncommitted).
2. Diffs against Plan HEAD `bb03d3f`: `evidence/diffs/v7-besu-results/` (Plan documents) and `.../evidence-package/` (evidence documents).
3. Status table: `evidence/v7-besu-results/STATUS-TABLE.md` (97 rows, counts computed by script).
4. Verification evidence: `evidence/v7-besu-results/` (Plan state before, previous v6 root manifest, contracts-untouched check, stale-phrase search, Plan-vs-package hash check, replaced-files list with inner-manifest comparison). The extraction-test record is delivered next to the ZIP as `extraction-test.txt`, with the ZIP's `.sha256`.
5. The complete Besu evidence: `testing-evidence/besu-live-test-v4-2026-10-03/` (own `MANIFEST.sha256`) — documents, `PLAN-path-L-real-time.md` (plan only, not executed), all result JSON, scripts, genesis files, node configs, raw node logs, `evidence/06-coverage/` with both hash lists (`new-results-sha256.txt`, `new-results-sha256-pass4.txt`). Raw evidence, scripts and logs are byte-identical to v6.

## Relationship to earlier versions
Replaces `sur-besu-v4-results-integrated-package-v6.zip` (sha256 `9438ed8cc952643d209392c0e2b27f372edeefdeb3c42e1617f3e3b76d621f93`; its contents are in Plan commit `a6eb708`) and, through it, v5 and v4. Does not replace the L05 v2 or v3 text-fix packages. Plan documents the owner edited after v6 (`economics/sur-tokenomics.md`, `technical-design/sur-contracts-oracles-accounts-report.md`, `offchain-services/sur-reward-router-spec.md`, …) are taken as they are in the Plan; the package manifest records their current hashes (the v6 manifest in the Plan no longer matched six files for that reason).

## Result (unchanged from v6) and what stays open
**97 rows = 90 PASS, 0 FAIL, 1 NOT-RUN, 6 SUPERSEDED** (script-counted). Not executed: the combined real-time path L (only `PLAN-path-L-real-time.md` exists). Fourth-pass results: A09 fixed in the TEST genesis builder and verified on fresh networks with a negative control (the 33 earlier networks keep value 0 and were not rebuilt; no earlier row depends on it); C-L04-6b PASS (already-voted re-added member is rejected with `already voted`). Limits: the 30-day boundary and the success path of `refreshBoard()` after 30 days were not exercised; Group A on the earlier follow-up networks was done on twins; one run each for C-L04-6 and C-L04-6b; the production genesis tool (T02), RewardRouter, the production `gasLimit` decision, the repair path for "actual reward > cap" on a past range and the rate-governance dashboard page remain open project items.

## Verification
Extract at the Plan root and run `sha256sum -c MANIFEST.sha256`. Test-extracted (a) into an empty directory and (b) over a copy of the Plan tree; results (root and inner manifests, both hash lists, contracts-unchanged comparison, counts recomputed from the extracted REPORT.md) are in `extraction-test.txt`.

## Status
No contract or policy was changed (`evidence/v7-besu-results/contracts-untouched-check.txt`), no fork was used, the real-time path L was not started. **This is not a production-readiness statement.**

## Earlier "known stale reference"
The v4–v6 READMEs listed `sur-detailed-plan-and-rationale.md` (lines 14 and 793) as still saying the current code was untested on Besu. The owner updated that file in Plan commit `a6eb708`; it now states that the fourth round ran on the current code and that L4 of path L was not executed, so the note no longer applies. The file is not part of this package.
