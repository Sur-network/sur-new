#!/bin/bash
# Builds summary.md (+ occurrences-analysis.csv, per-phase.csv, per-hour.csv) from a run directory. Safe to run during or after a run.
#   ./collect-results.sh [run-dir] [--tar]
# Needs the loadgen image (node:22-alpine by default) locally; no network. --tar also writes <run-dir>.tar.gz next to it.
set -u
source "$(dirname "$0")/lib/common.sh"
RD=""; TAR=0
for a in "$@"; do case "$a" in --tar) TAR=1;; *) RD="$a";; esac; done
[ -n "$RD" ] || RD="$(current_run)"
[ -n "$RD" ] && [ -d "$RD" ] || die "no run directory (pass one, e.g. runs/<run-id>)"
RD="$(cd "$RD" && pwd)"
NET="$(sed -n 's/.*"net": *"\([^"]*\)".*/\1/p' "$RD/meta/run.json" | head -1)"
IMG="$(sed -n 's/.*"loadgenImage": *"\([^"]*\)".*/\1/p' "$RD/meta/run.json" | head -1)"
docker image inspect "$IMG" >/dev/null 2>&1 || die "image $IMG not present (docker pull $IMG)"
say "analysing $RD"
TOOL_NETWORK=none run_tool "$IMG" "$RD" "$NET" analyze.js
if [ "$TAR" = 1 ]; then
  say "packing $RD.tar.gz"
  tar -czf "$RD.tar.gz" -C "$(dirname "$RD")" "$(basename "$RD")" && ls -l "$RD.tar.gz"
fi
echo "summary: $RD/summary.md"
