# Integrated package — audit 2026-09-30, stages 1–5

## What this package is
**Incremental, not a full copy of the project.** It contains complete, current versions of every file that changed in this
audit round (no partial files or patches), plus new evidence files. Files of the project that did not change are NOT in it.

## Required extraction base
The Plan folder as it was in the snapshot `sur-project-all-files(20260930-050101).zip` (the audit's baseline), or a later
Plan folder into which earlier packages of this round were already extracted — both lead to the same result, because every
changed file here is a complete version. Base fingerprints for verification: `testing-evidence/hardhat-regression/contracts-tested.baseline-pre-L01-L03.sha256`,
`contracts-fa.baseline-pre-L01-L03.sha256`, `testing-evidence/audit-2026-09-30-stage3-docs/docs-baseline-pre-stage3.sha256`,
`testing-evidence/audit-2026-09-30-stage4-5/docs-baseline-pre-stage4.sha256`, `testing-evidence/audit-2026-09-30-stage4-5/decks-svgs-baseline.sha256`.

## How to apply
Extract the whole ZIP at the root of the Plan folder, overwriting. Verify with `sha256sum -c MANIFEST.sha256` (run at the Plan root).

### Files that REPLACE existing Plan files (39 files, all Plan-relative)
- `business/sur-marketing-roadmap.md`
- `business/sur-whitepaper.md`
- `contracts-fa/BlockRewardDistributor.sol`
- `contracts-fa/FoundationDAO.sol`
- `contracts/BlockRewardDistributor.sol`
- `contracts/FoundationDAO.sol`
- `diagrams/sur_foundation_org_chart.svg`
- `diagrams/sur_validators_assembly_org_chart.svg`
- `economics/sur-tokenomics.md`
- `governance/sur-organizational-structure.md`
- `offchain-services/sur-contracts-ui-review.md`
- `offchain-services/sur-genesis-builder-tool-spec.md`
- `offchain-services/sur-governance-dashboard-claudecode-brief.md`
- `offchain-services/sur-reward-router-spec.md`
- `offchain-services/sur-software-inventory.md`
- `offchain-services/sur-suren-sale-portal-claudecode-brief.md`
- `offchain-services/sur-verifier-service-spec.md`
- `presentations/Sur - Board Presentation.pptx`
- `presentations/Sur - Technical Team Presentation.pptx`
- `sur-comprehensive-project-document.md`
- `sur-final-decisions-2026-09-28.md`
- `sur-master-open-items.md`
- `technical-design/sur-audit-2026-09-30-final-status.md`
- `technical-design/sur-audit-2026-09-30-stage1-report.md`
- `technical-design/sur-audit-2026-09-30-stage3-summary.md`
- `technical-design/sur-blockchain-design-doc.md`
- `technical-design/sur-contracts-deploy-notes.md`
- `technical-design/sur-reward-policy-decision-2026-09-29.md`
- `technical-design/sur-smart-contracts-reference.md`
- `testing-evidence/hardhat-regression/contracts-fa.baseline-pre-L01-L03.sha256`
- `testing-evidence/hardhat-regression/contracts-fa.sha256`
- `testing-evidence/hardhat-regression/contracts-tested.baseline-pre-L01-L03.sha256`
- `testing-evidence/hardhat-regression/contracts-tested.sha256`
- `testing-evidence/hardhat-regression/run_L01_L03_suite.sh`
- `testing-evidence/hardhat-regression/scripts/characterize_L07_duplicate_addresses.js`
- `testing-evidence/hardhat-regression/scripts/test_D05_proposal_read_paths.js`
- `testing-evidence/hardhat-regression/scripts/test_L01_L02_share_change.js`
- `testing-evidence/hardhat-regression/scripts/test_L02_real_board_integration.js`
- `testing-evidence/hardhat-regression/scripts/test_L03_settlement_backlog.js`

Note: the two `presentations/*.pptx` files and the other files above that were changed in Plan earlier in this round are
already identical in Plan EXCEPT the two presentations, which could not be written to Plan directly and must come from here.

### New evidence files (do not replace anything; 127 files)
Under `testing-evidence/audit-2026-09-30-*/` and `testing-evidence/hardhat-regression/results/` — raw test outputs, diffs,
renders, validation output, baseline hashes.

