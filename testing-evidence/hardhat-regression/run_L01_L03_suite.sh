#!/usr/bin/env bash
# L01-L03 test runner (audit 2026-09-30, stage 1). Run from testing-evidence/hardhat-regression/.
# Usage: ./run_L01_L03_suite.sh <BlockRewardDistributor.sol> <results-subdir> [solc-path]
#   env TESTS="a b c"      subset of scripts/*.js to run (default: full L01-L03 suite)
#   env CONTRACTS_DIR=dir  source of the other contracts (default: ../../contracts)
#   env TEST_TIMEOUT=sec   per-test timeout (default 900)
# Exit code: 0 only if compilation succeeded AND every test exited 0. Any failing or timed-out test -> exit 1.
# Every test's output is kept in results/<subdir>/<test>.txt and its exit code in results/<subdir>/_exit_codes.txt.
set -u
SRC=${1:?distributor source path required}; OUT=results/${2:?results subdir required}; mkdir -p "$OUT"
CONTRACTS_DIR=${CONTRACTS_DIR:-../../contracts}; TEST_TIMEOUT=${TEST_TIMEOUT:-900}
if [ -n "${3:-}" ]; then export SOLC_PATH=$3; else unset SOLC_PATH; fi
cp "$SRC" contracts_src_BlockRewardDistributor.sol
for f in ValidatorsRegistry ValidatorsBoard ValidatorsTreasury SurAddresses; do cp "$CONTRACTS_DIR/$f.sol" contracts_src_$f.sol; done
cp "$CONTRACTS_DIR/genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol" contracts_src_ValidatorsRegistry_GenesisSeed.sol
{ node -p "require(process.env.SOLC_PATH||'solc').version()"; sha256sum contracts_src_*.sol; } > "$OUT/_compiler_and_source.txt"
if ! { node compile3.js && node compile_board_treasury.js && node compile_distributor.js; } > "$OUT/_compile.txt" 2>&1; then
  echo "$2 | COMPILE FAILED (see $OUT/_compile.txt)"; exit 2; fi
: > "$OUT/_exit_codes.txt"; failed=0
for t in ${TESTS:-test_L01_L02_share_change test_L02_real_board_integration test_L03_settlement_backlog characterize_L07_duplicate_addresses test_P05_distributor_ranges verify_everActivated_policy test_P01_P02_board}; do
  timeout "$TEST_TIMEOUT" npx hardhat run "scripts/$t.js" > "$OUT/$t.txt" 2>&1; ec=$?
  if [ $ec -eq 124 ]; then status="TIMEOUT(${TEST_TIMEOUT}s)"; elif [ $ec -eq 0 ]; then status=PASS; else status=FAIL; fi
  [ $ec -ne 0 ] && failed=$((failed+1))
  echo "$t exit=$ec $status" >> "$OUT/_exit_codes.txt"
  echo "$2 | $t | exit=$ec | $status | $(tail -1 "$OUT/$t.txt")"
done
echo "$2 | SUMMARY: $failed failing/timed-out test(s)" | tee -a "$OUT/_exit_codes.txt"
[ $failed -eq 0 ] && exit 0 || exit 1
