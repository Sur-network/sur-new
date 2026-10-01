#!/usr/bin/env bash
# L01-L03 test runner (audit 2026-09-30, stage 1). Run from testing-evidence/hardhat-regression/.
# Usage: ./run_L01_L03_suite.sh <BlockRewardDistributor.sol> <results-subdir> [solc-path]
#   env TESTS="a b c"      subset of scripts/*.js to run (default: full L01-L03 suite)
#   env CONTRACTS_DIR=dir  source of the other contracts (default: ../../contracts)
#   env TEST_TIMEOUT=sec   per-test timeout (default 900)
# Exit code: 0 only if staging and compilation succeeded AND every test exited 0.
#   3 = missing input or failed copy (stops BEFORE compiling; stale staged files are deleted first)
#   2 = compilation failed   1 = at least one test failed or timed out
# Every test's output is kept in results/<subdir>/<test>.txt and its exit code in results/<subdir>/_exit_codes.txt.
set -u
SRC=${1:?distributor source path required}; RUN_NAME=${2:?results subdir required}; OUT=results/$RUN_NAME
CONTRACTS_DIR=${CONTRACTS_DIR:-../../contracts}; TEST_TIMEOUT=${TEST_TIMEOUT:-900}
if [ -n "${3:-}" ]; then export SOLC_PATH=$3; else unset SOLC_PATH; fi
# Remove every previously staged source and compiled artifact FIRST, so a failed copy can never leave an older file
# behind to be compiled and tested by mistake.
rm -f contracts_src_*.sol distributor_artifact.json artifacts3.json board_artifact.json treasury_artifact.json
stage() { # stage <source> <destination>: exits 3 before any compilation if the source is missing or the copy fails
  if [ ! -f "$1" ]; then rm -f contracts_src_*.sol; echo "${RUN_NAME} | INPUT MISSING: $1 — staging cleared, nothing compiled, no test started"; exit 3; fi
  if ! cp "$1" "$2"; then rm -f contracts_src_*.sol; echo "${RUN_NAME} | COPY FAILED: $1 -> $2 — staging cleared, nothing compiled, no test started"; exit 3; fi
}
stage "$SRC" contracts_src_BlockRewardDistributor.sol
for f in ValidatorsRegistry ValidatorsBoard ValidatorsTreasury SurAddresses; do stage "$CONTRACTS_DIR/$f.sol" contracts_src_$f.sol; done
stage "$CONTRACTS_DIR/genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol" contracts_src_ValidatorsRegistry_GenesisSeed.sol
mkdir -p "$OUT"
{ node -p "require(process.env.SOLC_PATH||'solc').version()"; sha256sum contracts_src_*.sol; } > "$OUT/_compiler_and_source.txt"
if ! { node compile3.js && node compile_board_treasury.js && node compile_distributor.js; } > "$OUT/_compile.txt" 2>&1; then
  echo "$RUN_NAME | COMPILE FAILED (see $OUT/_compile.txt)"; exit 2; fi
: > "$OUT/_exit_codes.txt"; failed=0
for t in ${TESTS:-test_L01_L02_share_change test_L02_real_board_integration test_L03_settlement_backlog test_L07_strict_ascending test_L05_reward_cap test_L05_rate_governance test_L04_electorate_snapshot test_L04_real_registry_integration test_D05_proposal_read_paths test_P05_distributor_ranges verify_everActivated_policy test_P01_P02_board}; do
  timeout "$TEST_TIMEOUT" npx hardhat run "scripts/$t.js" > "$OUT/$t.txt" 2>&1; ec=$?
  if [ $ec -eq 124 ]; then status="TIMEOUT(${TEST_TIMEOUT}s)"; elif [ $ec -eq 0 ]; then status=PASS; else status=FAIL; fi
  [ $ec -ne 0 ] && failed=$((failed+1))
  echo "$t exit=$ec $status" >> "$OUT/_exit_codes.txt"
  echo "$RUN_NAME | $t | exit=$ec | $status | $(tail -1 "$OUT/$t.txt")"
done
echo "$RUN_NAME | SUMMARY: $failed failing/timed-out test(s)" | tee -a "$OUT/_exit_codes.txt"
[ $failed -eq 0 ] && exit 0 || exit 1
