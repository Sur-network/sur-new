# Incremental package — L05 (reward cap + rate governance), L08 approved policy, dashboard brief

## What this package is
**Incremental, not a full copy of the project.** It holds complete current versions of every file changed in this round plus new evidence.
Files of the project that did not change are NOT in it.

## Required extraction base
The Plan folder after `sur-L04-incremental-package.zip` was applied (the Plan state before L05 is byte-identical to `preL05` used for the diffs;
`contracts/BlockRewardDistributor.sol` pre-L05 sha256 = 0fb27a03c046ab82…). Extract the whole ZIP at the Plan root (overwrite);
verify with `sha256sum -c MANIFEST.sha256` run at the Plan root.

## Files that REPLACE existing Plan files
- `contracts-fa/BlockRewardDistributor.sol`
- `contracts/BlockRewardDistributor.sol`
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

Already written to Plan and re-read this round (byte/hash-identical to this ZIP): both contracts (byte-compared with `cmp`), the two RewardRouter/genesis specs,
the contracts reference, the final-status table and the dashboard brief. Tooling and tests (`testing-evidence/hardhat-regression/run_L01_L03_suite.sh`,
`scripts/*.js`, `contracts-tested.sha256`, `contracts-fa.sha256`) are NOT yet in Plan — they must come from this ZIP.

## Evidence — `testing-evidence/hardhat-regression/results/audit-2026-09-30-L05/`
- `full-suite/`: all 12 scripts on the FINAL sources, solc 0.8.37 and 0.8.24, 0 failures; `_compiler_and_source.txt` in each run binds the result to the sha256 of every staged source.
- `l05-tests/`: both L05 tests (22/22 and 57/57) on the English and Persian Distributor, both compilers.
- `mutations/`: 18 mutant trees as diffs against the final source, raw outputs, summaries. `l05-mutations.txt` is the first run; `l05-mutations-rerun.txt` re-runs M23, M24, M29, M32
  after the governance test was strengthened (B5/B6, clean-failure helper) and SUPERSEDES the first-run lines for those four.
  M32 (board quorum 2) is caught by G1 and by the behavioural check B5; the abort after B5 is a cascade (a later vote hits "voting closed").
- `fixture-purpose.txt`: what changed in the two modified fixtures and the evidence that their purpose is preserved.
- `cost-vs-history.txt`: gas versus history length (before/after the binary-search rewrite) and governance-operation cost.
- `storage-abi-effect.txt`: compiler-derived — no existing slot moved; new slots 24–28; new functions/events; `distributeRewards` signature unchanged; runtime 12,197 → 18,009 bytes (limit 24,576).
- `static-checks/`: compile (no viaIR, no warnings), optimizer (26 files), layout, EN/FA parity (13/13), both compilers.
- `diffs/`, `contracts*.pre-L05.sha256` (fingerprints before) next to `testing-evidence/hardhat-regression/contracts*.sha256` (after).

## Scope and status
Hardhat only. **Not** a Besu run; **not** production readiness. Besu independent test: **environment ready (Besu 26.9.0, OpenJDK 25); not run** — by owner instruction.
L05 governance, cap and rate history are implemented and tested in Hardhat. Open: the repair path for "actual reward > cap" on a past range; the effect of a rate-change
transition on a real Besu (restart / config file) — an operational assumption, not verified; RewardRouter implementation; L06 on-chain proof; L08 proven-ineligible-producer exception (separate decision).
