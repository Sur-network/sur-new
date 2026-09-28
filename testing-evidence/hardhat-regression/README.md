# Hardhat regression suite for the Sur contracts

**What this is:** local-EVM (Hardhat in-process network) tests of the six structural contracts.
**What this is NOT:** a Besu / QBFT test. Nothing here proves consensus behaviour, genesis injection, or wall-clock timing on a real
network — see `../../sur-besu-test-status.md` (phases 5–12, not yet run).

Only the **English** contracts (`contracts/`) are executed. The Persian contracts (`contracts-fa/`) are checked for *logical parity*
(identical after stripping comments/whitespace) by `static-checks/check_en_fa_parity.py`, not by running these tests.

## Versions actually used
Node v22.22.2 · Hardhat 2.29.1 · ethers 6.17.0 · solc-js **0.8.37** (default) and **0.8.24** (the version named in the deploy notes).
All results were produced with both compilers. Contract fingerprints: `contracts-tested.sha256` (English), `contracts-fa.sha256`.

## How to run
```bash
cd testing-evidence/hardhat-regression
npm install                                   # installs the pinned versions (package.json)
# copy the contracts next to the compile scripts under the names the scripts expect:
for f in ValidatorsRegistry ValidatorsBoard ValidatorsTreasury BlockRewardDistributor SurAddresses; do
  cp ../../contracts/$f.sol contracts_src_$f.sol; done
# build artifacts (default solc 0.8.37; for 0.8.24: export SOLC_PATH=$PWD/node_modules/solc-0.8.24)
node compile3.js && node compile_board_treasury.js && node compile_distributor.js
# run one test (each prints ✅/❌ lines; exit code 1 if any ❌)
npx hardhat run scripts/test_P04_exit_cases.js
```
Static checks run from the **project root** (folder that contains `contracts/` and `contracts-fa/`):
```bash
NODE_PATH=testing-evidence/hardhat-regression/node_modules node testing-evidence/hardhat-regression/static-checks/check_compile_all.js
NODE_PATH=... node .../static-checks/check_optimizer_all_files.js     # 26 files, optimizer on, no viaIR
NODE_PATH=... node .../static-checks/check_genesis_helper_layout.js   # helper vs real storage layout (shared variables)
python3 testing-evidence/hardhat-regression/static-checks/check_en_fa_parity.py
```

## Suite and real results (all exit code 0 with both compilers)
| script | what it checks | result |
|---|---|---|
| `test_verification_flow.js` | 6 core paths: activation, uncontested slash, mass-failure exemption, successful appeal, appeal without quorum (suspension stays), delivery dispute | 12 ✅, 0 ❌ |
| `reproduce_bug1_mass_failure_bypass.js` | a case cannot advance before its own mass-failure check | pass |
| `reproduce_bug2_delivery_conflict.js` | validator self-confirmation closes an open delivery dispute | pass |
| `reproduce_bug4_partial_exemption.js` | mass-failure check is per decision, not per epoch | pass |
| `reproduce_N01_stale_lock_wipe.js` | an exempted (closed) case cannot be reopened through `assertDeliveryDisputed` | pass |
| `test_N01_layer2_lock_binding.js` | a resolver clears the pending-slash lock only if the lock belongs to its own decision | pass |
| `test_recovery_period_bound.js` | `recoveryPeriod` must exceed `MASS_DEMOTION_WINDOW` (proposal time) | pass |
| `test_stale_votes.js` | cross-contract: `Board.clearStaleVotes` reads `demotedAt` through the 6-output `getValidatorInfo` | pass |
| `test_P04_exit_cases.js` | exit: 72 h pre-exit claim, 7-day withdrawal, fixed reserved amount (even if `slashBps` changes later), mass-failure reuse, `exitCooldown` floor | **29/29** |
| `test_P01_P02_board.js` | free voting, 30-day refresh, immediate authority loss on exit, succession, `syncBoard`, explicit reverts, <3 halt, payments vs caps, genesis-seeded `lastBoardRefreshAt` | **32/32** |
| `test_P05_distributor_ranges.js` | block-range control: duplicate / overlap / gap / inverted / future / oversize rejected | **15/15** |
| `test_P06_treasury_caps.js` | initial caps 50,000 / 200,000; 7-day timelock only for cap changes | **12/12** |

Raw output for every run: `results/solc-0.8.37/` and `results/solc-0.8.24/`.
Mutation checks (tests can really fail): `results/mutation-checks.txt` (3 mutations, all detected).

## Behaviour documented by tests but NOT decided (read before relying on it)
* `G-e`: if `lastBoardRefreshAt` is not overlaid at genesis (value 0), the first `refreshBoard()` is accepted immediately.
* `G-f`: an ordinary `refreshBoard()` with **zero votes** empties the whole board. The P01 decision does not cover this.
* Test 4 of `test_P06_treasury_caps.js` (no ratio function in the ABI) is a weak proxy for "no automatic 25 % rule".

## Known limits
Hardhat only · English contracts only · a few contracts are mocked (`MockRegistry`, `AllValid`, etc.) · not a full mutation campaign ·
the tests do not exercise `FoundationDAO`, `IdentityRegistry`, `ServiceStaking` or `SurenSale`.
