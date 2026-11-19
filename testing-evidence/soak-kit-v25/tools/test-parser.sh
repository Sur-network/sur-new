#!/bin/bash
# Self-test of the collector's log parser against a saved Besu log (default: round 1's Net-A n1.log, which contains 3 occurrences of F-1).
#   tools/test-parser.sh [logfile] [expected-count]
# Needs only the loadgen image locally and the log file (round 1 evidence folder is used when it is present).
source "$(dirname "$0")/../lib/common.sh"
LOGF="${1:-$KIT_DIR/../besu-live-test-v25-2026-11-19/logs/Net-A/n1.log}"; EXP="${2:-3}"
IMG="${LOADGEN_IMAGE:-$LOADGEN_IMAGE_DEFAULT}"
T="$RUNS_DIR/_parser-selftest"; rm -rf "$T"; mkdir -p "$T"; cp "$LOGF" "$T/input.log"
docker run --rm --pull never -v "$KIT_DIR_HOST:/kit:ro" -v "$(host_path "$T"):/run-data" -e NET=n7 -e RUN_DIR=/run-data -e KIT_DIR=/kit -e NODE_PATH=/opt/node_modules \
  -e SOAK_SELFTEST_LOG=/run-data/input.log -e SOAK_SELFTEST_NODE=n1 "$IMG" sh -c "mkdir -p /opt && tar -xzf /kit/vendor/node_modules.tgz -C /opt && node /kit/runtime/collector.js" > "$T/selftest.out" 2>&1
head -30 "$T/selftest.out"
N=$(sed -n 's/.*"f1Total": *\([0-9]*\).*/\1/p' "$T/selftest.out"); echo "F-1 found: $N, expected $EXP"; ls "$T/occurrences"
[ "$N" = "$EXP" ] && echo "PARSER SELFTEST PASS" || { echo "PARSER SELFTEST FAIL"; exit 1; }
