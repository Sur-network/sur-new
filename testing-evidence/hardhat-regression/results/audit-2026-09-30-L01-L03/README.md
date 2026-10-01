# Integrated package — audit 2026-09-30: stages 1–5 (contracts, documents, diagrams, presentations)

**This ZIP is incremental.** It contains only the files added or changed in stage 1. It does NOT contain the compile
scripts, the pre-existing regression scripts, `node_modules`, or any other dependency. Extract ALL of it at the root of the Plan
folder on top of the base package below; paths inside the ZIP are Plan-relative. There are no files to skip: every
document in the ZIP is the current Plan version (see `MANIFEST.sha256` at the ZIP root).

## Base package (what this applies on top of)
The Plan-folder snapshot `sur-project-all-files(20260930-050101).zip`, identified by its contract fingerprints:
`testing-evidence/hardhat-regression/contracts-tested.baseline-pre-L01-L03.sha256` and
`contracts-fa.baseline-pre-L01-L03.sha256` (copies of the base `contracts-tested.sha256` / `contracts-fa.sha256`).
`BlockRewardDistributor.sol` base: EN `b0a5d9cc…4b071`, FA `9e36be11…ffc9f`.

Base harness files this package's runner uses unchanged (sha256 of the copies actually used):
| file (in `testing-evidence/hardhat-regression/`) | sha256 |
|---|---|
| `compile3.js` | `cf5bf8819eb0b19634950d56d931332960510585f9c8a2eed88635b39da5cbc1` |
| `compile_board_treasury.js` | `3b46ba63c940419d6bbb7e23a4f7ec03a2f430a52cda29962d408f9463b8433c` |
| `compile_distributor.js` | `d9d1505e68f017cae3dbdf028551db1fdae75fe427e75d67800e4d8292693d0e` |
| `scripts/test_P05_distributor_ranges.js` | `8783ff1c55d7b9e0b8efc8aa4f8270c8710801125e6bef328f90e313da022b28` |
| `scripts/verify_everActivated_policy.js` | `1ded32d2af9df10b9c0b13e23f7585ad03474814fbffe7b95026f625787bd722` |
| `scripts/test_P01_P02_board.js` | `091212d43bdecc517331c3efbfd2c9a50e8ba39499d62cb07f665ddee89d09ae` |
| `static-checks/check_compile_all.js` | `484a2ba751881b7757c8abc055177a178c56c681612978eb8dd66c9317703eb6` |
| `static-checks/check_en_fa_parity.py` | `10a96236d287bd8eaae945bd06f0ec3c9f46804144b504abe4b8999c39ef6cd2` |
| `static-checks/check_genesis_helper_layout.js` | `0eac152a21ce99d91a7a866b995a924fc445e66ae7b19420896ea6e3a0c9a1c0` |
| `static-checks/check_optimizer_all_files.js` | `2ae305e4a240f99a971026afba685c4de076a91f2f9c7159fd0eb031a7256910` |

## Tool versions actually used
Node v22.22.2 · hardhat 2.29.1 · ethers 6.17.0 · @nomicfoundation/hardhat-toolbox 6.1.2 · solc-js 0.8.37 (default) and
0.8.24 (`npm:solc@0.8.24`) — exactly the pins in the base `package.json`. Compiler settings (from the base compile
scripts): optimizer enabled, runs 200, no viaIR. `hardhat.config.js`: `solidity: "0.8.24"` (only used by Hardhat itself;
the contracts are compiled by the solc-js scripts above).

## Reproduce
```bash
cd testing-evidence/hardhat-regression
npm install                                              # base package.json pins
./run_L01_L03_suite.sh ../../contracts/BlockRewardDistributor.sol my-run-0.8.37
./run_L01_L03_suite.sh ../../contracts/BlockRewardDistributor.sol my-run-0.8.24 "$PWD/node_modules/solc-0.8.24"
# pre-fix comparison (a copy of the base BlockRewardDistributor.sol, fingerprint b0a5d9cc…):
TESTS="test_L01_L02_share_change test_L02_real_board_integration test_L03_settlement_backlog" \
  ./run_L01_L03_suite.sh /path/to/base/BlockRewardDistributor.sol my-run-prefix
```
The runner first deletes every previously staged `contracts_src_*.sol` and compiled artifact, then copies each
contract it needs from `../../contracts` (override with `CONTRACTS_DIR`). If any input is missing or any copy fails it
clears the staging area and **stops with exit 3 before compiling — no test is started**. It then compiles (exit 2 on
failure), runs each test with a per-test timeout (`TEST_TIMEOUT`, default 900 s), writes each test's full output to
`results/<run>/<test>.txt` and each exit code to `results/<run>/_exit_codes.txt`, and exits 1 if any test fails or
times out, 0 only if all pass. `runner-demo/` shows every path with the final runner:
`runner-demo.txt` — A all pass → 0; B a failing test followed by a passing one → 1; C forced 1-second timeout →
`exit=124 TIMEOUT` → 1. `runner-demo-missing-input.txt` — with a stale pre-fix staged set and artifacts planted
beforehand: D non-existent distributor path → 3; E non-existent `CONTRACTS_DIR` → 3; in both, no results directory,
no test output, and no staged source or artifact left.

Static checks run from the Plan root, as in the base README (`NODE_PATH=testing-evidence/hardhat-regression/node_modules`).

## Contents
- `contracts/`, `contracts-fa/` — the one changed contract per language.
- `technical-design/sur-audit-2026-09-30-stage1-report.md` — stage report: fixes, storage/ABI effect, test matrix,
  open findings L05–L08, ABI-consumer inventory, T02 and RewardRouter-recovery specifications, limitations.
- `scripts/` — `test_L01_L02_share_change.js` (mocks), `test_L02_real_board_integration.js` (real ValidatorsBoard),
  `test_L03_settlement_backlog.js` (time model), `characterize_L07_duplicate_addresses.js` (characterization, L07 open).
- `results/audit-2026-09-30-L01-L03/` — raw outputs `solc-0.8.37/`, `solc-0.8.24/`, `prefix-solc-0.8.37/` (produced
  by the first runner version, which printed but did not propagate exit codes and did not guard its inputs — the outputs themselves are complete;
  `runner-demo/` was produced with the fixed runner); `static-checks/`; `mutation-checks-L01-L03.txt`; EN/FA diffs.
- `contracts-tested.sha256`, `contracts-fa.sha256` (new) and `*.baseline-pre-L01-L03.sha256` (base, kept).

## D05 — `FoundationDAO.getProposalMeta` (`results/audit-2026-09-30-D05/`)
`FoundationDAO.proposals` is private, so no auto-getter exists; `getProposal()` returns neither `description`,
`requiredVotes` (quorum snapshotted at creation), `createdAt` nor `expiresAt`. A read-only `getProposalMeta(id)` was
added in both languages; `getProposal()` is unchanged. `ValidatorsRegistry.paramProposals(id)` is public and already
exposes `requiredVotes`/`createdAt`/`expiresAt` — no change there. Test `scripts/test_D05_proposal_read_paths.js` runs the
REAL contracts on storage produced by the project's own genesis seed helpers (placeholder addresses substituted with test
signers): `CONTRACTS_DIR=../../contracts npx hardhat run scripts/test_D05_proposal_read_paths.js` (and
`../../contracts-fa`). Raw outputs: EN and FA on solc 0.8.37 and 0.8.24 (18/18 each); pre-change EN source fails at F2
(getter missing). Static checks rerun over all 26 files. `contracts-*.pre-D05.sha256` keep the previous fingerprints.

## Stage-3 document updates (`testing-evidence/audit-2026-09-30-stage3-docs/`)
Plan documents updated (D04, D05, D06, D15, D16 and the L01–L03 ABI follow-up) for the L01–L03 ABI change (removed `deployTime()` / `MIN_BLOCK_PERIOD_SECONDS()` getters,
removed time cap, `shareProposals(id)` now 10 outputs, L01/L02 rules) and the stage-1 report's L05 addition. The updated
documents are included at their Plan paths; `diffs/` has a unified diff of each against its pre-stage-3 version, and
`docs-baseline-pre-stage3.sha256` the pre-stage-3 hashes. Consumer search: no document or script decodes
`shareProposals(id)` positionally (details in the stage-1 report, section 5).

## Stages 4–5 (`testing-evidence/audit-2026-09-30-stage4-5/`)
Documents (D02, D03, D10–D14 and related stale statements), both SVGs (D07, D08) and both presentations. Replacement
paths: every file is at its Plan path inside this ZIP — including `presentations/Sur - Board Presentation.pptx` and
`presentations/Sur - Technical Team Presentation.pptx`, which must be copied over the Plan copies by hand (binary files
could not be written to Plan directly). `diffs/` holds unified diffs against the pre-audit versions (text diffs for the
decks, extracted with markitdown); `slide-renders/` the inspected renders (changed slides at readable size, all slides as
overview sheets, the SVG renders, the embedded-media contact sheet); `pptx-validate.txt` the validator output (both PASS);
`*-baseline*.sha256` the pre-edit hashes. Full ID status table and slide decision-coverage matrix:
`technical-design/sur-audit-2026-09-30-final-status.md`.

## Limits
All tests are Hardhat (in-process EVM). None is a Besu/QBFT run. "Both compilers" means two independent Hardhat runs.
Open after stage 1: L05–L08, a Besu run, implementation of T02 and RewardRouter recovery (specifications only).
