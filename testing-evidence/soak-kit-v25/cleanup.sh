#!/bin/bash
# Removes ONLY what this kit created: containers named sur25s-*, volumes sur25s-*, network sur25s-net. The runs/ folder (results) is kept
# unless you pass --purge-runs. Other containers, volumes and networks on the host are never touched.
#   ./cleanup.sh [--yes] [--force] [--purge-runs]
set -u
source "$(dirname "$0")/lib/common.sh"
YES=0; FORCE=0; PURGE=0
for a in "$@"; do case "$a" in --yes) YES=1;; --force) FORCE=1;; --purge-runs) PURGE=1;; *) die "unknown option $a";; esac; done
runner_alive && [ "$FORCE" = 0 ] && die "run-soak.sh is still running (use ./stop-soak.sh first, or --force)"
C="$(kit_containers)"; V="$(kit_volumes)"; N="$(kit_networks)"
echo "containers: $(echo $C)"; echo "volumes   : $(echo $V)"; echo "networks  : $(echo $N)"
[ -z "$C$V$N" ] && [ "$PURGE" = 0 ] && { say "nothing to clean"; exit 0; }
if [ "$YES" = 0 ]; then read -r -p "Remove exactly these (results in runs/ stay)? [y/N] " r; [ "$r" = y ] || [ "$r" = Y ] || die "aborted"; fi
for c in $C; do docker rm -f -v "$c" >/dev/null && say "removed container $c"; done
for v in $V; do docker volume rm -f "$v" >/dev/null && say "removed volume $v"; done
for n in $N; do docker network rm "$n" >/dev/null && say "removed network $n"; done
rm -f "$STATE_DIR/run.pid"
if [ "$PURGE" = 1 ]; then rm -rf "$RUNS_DIR"/* "$STATE_DIR/current-run"; say "runs/ purged"; fi
say "left over with prefix ${PREFIX}: containers [$(kit_containers | tr '\n' ' ')] volumes [$(kit_volumes | tr '\n' ' ')] networks [$(kit_networks | tr '\n' ' ')]"
