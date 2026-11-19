#!/bin/bash
# One-screen state of the current soak run.
source "$(dirname "$0")/lib/common.sh"
RD="$(current_run)"
if [ -z "$RD" ] || [ ! -d "$RD" ]; then echo "no run yet"; exit 0; fi
echo "run: $(basename "$RD")   runner: $(runner_alive && echo "alive (pid $(cat "$STATE_DIR/run.pid"))" || echo "NOT running")   $([ -f "$RD/RESULT-READY" ] && echo "[finished: see summary.md]")"
if [ -f "$RD/status.txt" ]; then
  AGE=$(( $(date +%s) - $(stat -c %Y "$RD/status.txt" 2>/dev/null || stat -f %m "$RD/status.txt" 2>/dev/null || date +%s) ))
  cat "$RD/status.txt"; [ "$AGE" -gt 60 ] && echo "!! status.txt is ${AGE}s old: the collector is not running"
else echo "(collector has not written status.txt yet)"; fi
echo "--- containers"
docker ps -a --filter "label=sur25s.kit=1" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | head -20
echo "--- last supervisor lines"; tail -n 3 "$RD/supervisor.log" 2>/dev/null
[ -s "$RD/meta/supervisor-restarts.log" ] && echo "!! the supervisor restarted collector/loadgen: see $RD/meta/supervisor-restarts.log"
DF="$(df -Pk "$KIT_DIR" | awk 'NR==2{printf "%.1f GB free", $4/1048576}')"; echo "--- disk: $DF; run dir $(du -sm "$RD" 2>/dev/null | cut -f1) MB"
