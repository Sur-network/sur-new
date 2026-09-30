#!/bin/bash
# Usage: ./run_L01_L03_suite.sh <path-to-BlockRewardDistributor.sol> <results-subdir> [solc-path]
SRC=$1; OUT=results/$2; mkdir -p $OUT
if [ -n "$3" ]; then export SOLC_PATH=$3; else unset SOLC_PATH; fi
cp $SRC contracts_src_BlockRewardDistributor.sol
( node -p "require(process.env.SOLC_PATH||'solc').version()"; sha256sum contracts_src_BlockRewardDistributor.sol ) > $OUT/_compiler_and_source.txt
node compile3.js >/dev/null && node compile_board_treasury.js >/dev/null && node compile_distributor.js >/dev/null || { echo COMPILE FAIL; exit 1; }
for t in ${TESTS:-test_L01_L02_share_change test_L02_real_board_integration test_L03_settlement_backlog characterize_L07_duplicate_addresses test_P05_distributor_ranges verify_everActivated_policy test_P01_P02_board}; do
  timeout 900 npx hardhat run scripts/$t.js > $OUT/$t.txt 2>&1; echo "$2 | $t | exit=$? | $(tail -1 $OUT/$t.txt)"
done
