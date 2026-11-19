#!/bin/bash
# Ends the current run early and writes the results (final row, summary.md). The containers and volumes stay until ./cleanup.sh.
set -u
source "$(dirname "$0")/lib/common.sh"
RD="$(current_run)"; [ -n "$RD" ] && [ -d "$RD" ] || die "no current run"
if runner_alive; then
  PID="$(cat "$STATE_DIR/run.pid")"
  say "run-soak.sh (pid $PID) is alive: asking it to finish"
  : > "$RD/STOP"; kill -TERM "$PID" 2>/dev/null
  for i in $(seq 1 120); do kill -0 "$PID" 2>/dev/null || break; sleep 3; done
  kill -0 "$PID" 2>/dev/null && say "runner still busy after 6 min; check $RD/supervisor.log" || say "runner finished"
else
  say "no live run-soak.sh: finishing the run from here"
  finish_run "$RD"
fi
