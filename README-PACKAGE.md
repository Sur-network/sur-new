# Incremental package v2 — L05 corrections (completion re-check, status 7), L08 wording, fee-text alignment, cost evidence

## What this package is
**Incremental, not a full copy of the project.** It SUPERSEDES `sur-L05-incremental-package.zip` (v1) entirely: every file below is a complete current version.
If v1 was already applied, applying v2 over it is correct (v2 contains everything v1 changed, in its latest state).

## Required extraction base
The Plan folder after `sur-L04-incremental-package.zip` was applied (same base as v1; pre-L05 `contracts/BlockRewardDistributor.sol` sha256 = 0fb27a03c046ab82…).
Extract the whole ZIP at the Plan root (overwrite); verify with `sha256sum -c MANIFEST.sha256` run at the Plan root.

## Files that REPLACE existing Plan files
- `business/sur-whitepaper.md`
- `contracts-fa/BlockRewardDistributor.sol`
- `contracts/BlockRewardDistributor.sol`
- `economics/sur-tokenomics.md`
- `offchain-services/sur-genesis-builder-tool-spec.md`
- `offchain-services/sur-governance-dashboard-claudecode-brief.md`
- `offchain-services/sur-reward-router-spec.md`
- `technical-design/sur-audit-2026-09-30-final-status.md`
- `technical-design/sur-smart-contracts-reference.md`
- `testing-evidence/hardhat-regression/contracts-fa.sha256`
- `testing-evidence/hardhat-regression/contracts-tested.sha256`
- `testing-evidence/hardhat-regression/run_L01_L03_suite.sh`
- `testing-evidence/hardhat-regression/scripts/test_L05_rate_governance.js`
- `testing-evidence/hardhat-regression/scripts/test_L05_reward_cap.js`
- `testing-evidence/hardhat-regression/scripts/test_L07_strict_ascending.js`
- `testing-evidence/hardhat-regression/scripts/verify_everActivated_policy.js`

Already written to Plan and re-read this round: both contracts (byte-compared with `cmp`, identical), tokenomics, whitepaper, the status table and the contracts reference.
The three `offchain-services/*.md` files were not edited this round (byte-equal to the v1 package copies). Tests and tooling are NOT yet in Plan — they come from this ZIP.

## What changed since v1 (diffs in `results/audit-2026-09-30-L05-v2/diffs/`)
1. `_markRateApprovedIfComplete` re-checks the board composition version when both chambers complete; the completing validator vote is refused after a board change (no `approvedAt`, no `RateChangeApproved`).
2. `rateChangeStatus`: new status 7 = not approved and unable to continue (reasons 1–4; every reason is permanent); expiry (2) takes precedence over 7.
3. Tests: governance 57 → 72 checks (S1–S15), cap 22 → 25 checks (cost vs k).
4. Status table: L08 = approved policy + ready spec; Router implementation/test open; execution of stop-and-alert is the Router's job, not the contract's. E01–E05 stay as five separate rows; cost stated as O(log n + k) with separate evidence per case.
5. tokenomics + whitepaper: fee and membership-fee split aligned with historical eligibility (producers of the blocks of the same range, proportional to blocks); also corrected in the contracts reference (it omitted the 30% burn).

## Evidence — `testing-evidence/hardhat-regression/results/audit-2026-09-30-L05-v2/`
- `full-suite/`: all 12 scripts on the FINAL sources, solc 0.8.37 and 0.8.24, 0 failures; `_compiler_and_source.txt` binds each run to the sha256 of every staged source.
- `persian-l05-tests/`: both L05 tests on the Persian Distributor, both compilers (25/25 and 72/72).
- `mutations/`: 21 mutants as diffs against the final source + raw outputs + `l05-mutations-v2.txt` (all detected). Notes: M32 is caught by G1 and by the behavioural B5 (the abort after B5 is a cascade);
  M40 (linear scan, returns correct values) is caught only by the cost checks D3/E3; M36/PRE_L05_M36 abort at the first payment (identical behaviour before/after the fixture edit).
- `cost-vs-history.txt`: gas vs history length and vs k (not generalised from the k = 0 case); `storage-abi-effect.txt`: no existing slot moved, new slots 24–28, runtime 12,197 → 18,177 bytes;
  `static-checks/`: compile/optimizer/layout/parity on both compilers; `fixture-purpose.txt`; `plan-vs-package-hash-check.txt`; fingerprints before (`*.pre-L05.sha256`, `*.v1-package.sha256`) and after (`../../contracts*.sha256`).

## Scope and status
Hardhat only. **Not** a Besu run; **not** production readiness. Besu independent test: **environment ready (Besu 26.9.0, OpenJDK 25); not run** — by owner instruction.
Open: repair path for "actual reward > cap" on a past range; effect of a rate-change transition on a real Besu (operational assumption, unverified); Router implementation and tests (L06, L08);
L08 proven-ineligible-producer exception (separate decision); a stale mention of the removed `_checkPhysicalMaximum` in the contracts reference (registered, not edited).
