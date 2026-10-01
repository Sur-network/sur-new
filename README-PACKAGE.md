# Incremental package — L04 (owner decision): electorate snapshot at proposal creation

**Incremental.** Complete current versions of every file changed for L04, plus evidence.
**Extraction base:** the Plan folder after the L07-A package (`sur-L07A-incremental-package.zip`) was applied.
Extract the whole ZIP at the Plan root (overwrite); verify with `sha256sum -c MANIFEST.sha256`.

## Files that REPLACE Plan files
- Contracts (EN + FA): `FoundationDAO.sol`, `ValidatorsRegistry.sol`, `ValidatorsTreasury.sol`, `BlockRewardDistributor.sol`,
  `genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol` — already written to Plan and byte-compared (identical).
- Docs (already in Plan, re-read): `technical-design/sur-smart-contracts-reference.md`, `technical-design/sur-audit-2026-09-30-final-status.md`,
  `offchain-services/sur-governance-dashboard-claudecode-brief.md`, `offchain-services/sur-genesis-builder-tool-spec.md`.
- Tooling (NOT yet in Plan — must come from this ZIP): `testing-evidence/hardhat-regression/run_L01_L03_suite.sh`,
  `static-checks/check_genesis_helper_layout.js` (fixed: recursive structural shape comparison), `scripts/test_L01_L02_share_change.js` and
  `scripts/test_L02_real_board_integration.js` (mocks made checkpoint-faithful), `contracts-tested.sha256`, `contracts-fa.sha256`.
- New tests: `scripts/test_L04_electorate_snapshot.js`, `scripts/test_L04_real_registry_integration.js`.

## Evidence (`testing-evidence/hardhat-regression/results/audit-2026-09-30-L04/`)
- `l04-final-solc-0.8.37/`, `l04-final-solc-0.8.24/`: full suite (10 scripts) on the FINAL sources, 0 failures; `_compiler_and_source.txt` binds each run to sha256 of every staged source.
- `runs-fa/`: both L04 tests on the Persian sources, both compilers (41/41, 30/30).
- `mutations/`: M17–M21 on final sources — every mutant detected; notes on M18 and on the unreachable defense-in-depth `isMember` check.
- `static-checks/`: compile/optimizer/layout/parity on both compilers + `negative-control-helper-struct-swapped.txt` (fixed checker still fails on a real layout error).
- `storage-abi-effect.txt`: compiler-derived — no existing slot moved; new slots; getter output changes; new public functions.
- `diffs/`: every changed contract/helper vs pre-L04, the two mock changes, the layout-checker fix. Previous fingerprints kept as `*.pre-L04.sha256`.

## Scope / status
Hardhat only. **Not** a Besu run; **not** production readiness. Besu independent test: OPEN until executed with recorded evidence.
`isValidator ⇔ getValidators`: confirmed by source review; needs runtime and genesis testing on Besu. L05 undecided; L08 interim policy = stop and alert.
