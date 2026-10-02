# Package v3 — text-only correction (stale `_checkPhysicalMaximum` / `deployTime` text), status table, search coverage

## Relationship to v2 — read this first
**v3 is NOT a replacement for `sur-L05-incremental-package-v2.zip`; it must be applied ON TOP of v2.**
v2 stays valid for everything it contains (both contracts, tests, evidence, the other documents). v3 only overwrites the seven files listed below.
No contract changed and no contract test was run (none was required): the two Distributor files re-read from Plan are byte-identical to the tested v2 files (`evidence/contracts-untouched-check.txt`).

## Extraction and verification
Extract this ZIP at the Plan root (overwrite). Verify with `sha256sum -c MANIFEST.sha256` run at the Plan root; this manifest covers ONLY the files of this ZIP.
Consequence: v2's own `MANIFEST.sha256` will intentionally fail on exactly three files after v3 is applied, because v3 supersedes them: `technical-design/sur-smart-contracts-reference.md`,
`technical-design/sur-audit-2026-09-30-final-status.md` and `README-PACKAGE.md`. The other four files below did not exist in v2's manifest.

## Files that REPLACE Plan files
- `technical-design/sur-smart-contracts-reference.md` — the paragraph that presented `_checkPhysicalMaximum` as a current function is rewritten: current structure stated first, the original version kept as an explicitly dated, "no longer valid" historical explanation.
- `technical-design/sur-reward-policy-decision-2026-09-29.md` — control list aligned with the contract (P05, L05, L07; time-based cap marked historical); the old advice to stay under that cap marked "no longer valid".
- `technical-design/sur-contracts-deploy-notes.md` — historical marker on the removed function inside the correction narrative.
- `technical-design/sur-audit-2026-09-30-final-status.md` — the stale-text item is now "fixed"; the four declared open items are listed explicitly (1 repair path "actual reward > cap" for a past range; 2 operational gasLimit check; 3 RewardRouter implementation and tests; 4 rate-governance page in the dashboard), plus the earlier open item (transition on real Besu / the Besu run); L05 row carries them too; E01–E05 remain five separate rows.
- `sur-besu-test-status.md` — the unmarked "Router must stay under the physical cap" note split into a dated historical part and what is still true.
- `sur-master-open-items.md` — genesis-tool overlay list no longer names `deployTime` as current; two historical rows marked.
- `README-PACKAGE.md` — the v2 README: open-items line corrected and a superseded note added (it had listed the stale text as "registered, not edited").
- New: this file.

## Evidence (`evidence/`)
`diffs/` (every changed file vs its pre-round version), `search-coverage.txt` (47 of 47 current Markdown files, 27 remaining mentions all in removal/historical context, 0 unmarked; both decks' slide and notes text: 0 hits),
`plan-vs-package-hash-check.txt` (all seven re-read from Plan: EQUAL), `contracts-untouched-check.txt`.
Scope note: the search ran on the latest copy of each file fetched from Plan in this conversation; dated audit findings (stage1/stage3 reports) were left as written because they describe the finding itself.

## Status
Hardhat evidence only; no production-readiness claim. Besu independent test: environment ready (Besu 26.9.0, OpenJDK 25), not run. The four declared open items above remain open.
