#!/bin/bash
# Shared shell helpers of the soak kit (sourced by run-soak.sh, stop-soak.sh, status.sh, cleanup.sh, collect-results.sh).
# Only Docker and bash are needed on the host. Everything the kit creates is named sur25s-* and labelled sur25s.kit=1.

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Path form that `docker run -v` understands: on Git Bash for Windows `pwd -W` gives D:/..., on Linux plain pwd.
KIT_DIR_HOST="$(cd "$KIT_DIR" && (pwd -W 2>/dev/null || pwd))"
export MSYS_NO_PATHCONV=1
PREFIX="sur25s-"
NETWORK="${PREFIX}net"
SUBNET_BASE="172.29.71"
STATE_DIR="$KIT_DIR/.state"
RUNS_DIR="$KIT_DIR/runs"
LOADGEN_IMAGE_DEFAULT="node:22-alpine"
mkdir -p "$STATE_DIR" "$RUNS_DIR"

say() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }
die() { say "ERROR: $*" >&2; exit 1; }
now_ms() { date +%s%3N; }

# besu image: "26.9.0" -> hyperledger/besu:26.9.0 ; anything containing ':' or '/' is taken as a full reference
resolve_besu_image() { case "$1" in *:*|*/*) echo "$1";; *) echo "hyperledger/besu:$1";; esac; }

kit_containers() { docker ps -a --format '{{.Names}}' | grep "^${PREFIX}" || true; }
kit_volumes() { docker volume ls --format '{{.Name}}' | grep "^${PREFIX}" || true; }
kit_networks() { docker network ls --format '{{.Name}}' | grep "^${PREFIX}" || true; }

current_run() { [ -f "$STATE_DIR/current-run" ] && cat "$STATE_DIR/current-run"; }
runner_alive() { [ -f "$STATE_DIR/run.pid" ] && kill -0 "$(cat "$STATE_DIR/run.pid")" 2>/dev/null; }

# node_mount_path RUN_DIR: the run dir in the form docker -v wants
host_path() { (cd "$1" && (pwd -W 2>/dev/null || pwd)); }

# run_tool IMAGE RUN_DIR NET SCRIPT  : one-shot node container with kit (ro) + run dir (rw) mounted, vendored ethers extracted at start
DOCKER_EXTRA="${DOCKER_EXTRA:-}"
# subnet_overlaps A.B.C.D/M : true if it overlaps SUBNET_BASE.0/24
subnet_overlaps() {
  awk -v c="$1" -v base="$SUBNET_BASE" 'BEGIN{ split(c,p,"/"); split(p[1],o,"."); s=((o[1]*256+o[2])*256+o[3])*256+o[4]; sz=2^(32-p[2]);
    split(base,b,"."); t=((b[1]*256+b[2])*256+b[3])*256; exit !(s < t+256 && s+sz > t) }'
}
run_tool() { # extra docker args may be passed in DOCKER_EXTRA
  local image="$1" rundir="$2" net="$3" script="$4"
  docker run --rm --pull never $DOCKER_EXTRA --name "${PREFIX}${script%.js}-$$" --label sur25s.kit=1 --network "${TOOL_NETWORK:-$NETWORK}" \
    -v "$KIT_DIR_HOST:/kit:ro" -v "$(host_path "$rundir"):/run-data" \
    -e NET="$net" -e RUN_DIR=/run-data -e KIT_DIR=/kit -e NODE_PATH=/opt/node_modules -e SOAK_PREFIX="$PREFIX" \
    "$image" sh -c "mkdir -p /opt && tar -xzf /kit/vendor/node_modules.tgz -C /opt && exec node /kit/runtime/$script"
}

# finish_run RUN_DIR : idempotent end-of-run sequence (also used by stop-soak.sh when the runner is gone)
finish_run() {
  local rd="$1"
  [ -d "$rd" ] || return 0
  local net image
  net="$(sed -n 's/.*"net": *"\([^"]*\)".*/\1/p' "$rd/meta/run.json" | head -1)"
  image="$(sed -n 's/.*"loadgenImage": *"\([^"]*\)".*/\1/p' "$rd/meta/run.json" | head -1)"
  say "finishing run $(basename "$rd"): stopping load generator and collector"
  : > "$rd/STOP"
  # collector does a final drain (blocks, fork check, last row) while the nodes are still up
  for i in $(seq 1 60); do
    [ "$(docker inspect -f '{{.State.Running}}' ${PREFIX}collector 2>/dev/null)" = "true" ] || break
    sleep 3
  done
  docker stop -t 10 ${PREFIX}loadgen >/dev/null 2>&1 || true
  docker stop -t 10 ${PREFIX}collector >/dev/null 2>&1 || true
  mkdir -p "$rd/meta"
  for c in $(kit_containers); do docker inspect "$c" > "$rd/meta/inspect-$c.json" 2>/dev/null || true; done
  docker logs ${PREFIX}loadgen > "$rd/load/loadgen.log" 2>&1 || true
  docker logs ${PREFIX}collector > "$rd/collector/collector-container.log" 2>&1 || true
  say "stopping the Besu nodes (containers and volumes are kept until cleanup.sh)"
  for c in $(kit_containers | grep -v -e "${PREFIX}collector" -e "${PREFIX}loadgen" -e "${PREFIX}bootstrap"); do docker stop -t 30 "$c" >/dev/null 2>&1 || true; done
  if [ -n "$net" ] && [ -n "$image" ] && docker image inspect "$image" >/dev/null 2>&1; then
    "$KIT_DIR/collect-results.sh" "$rd" || say "collect-results failed (run it again by hand)"
  fi
  : > "$rd/RESULT-READY"
  say "run finished. Results: $rd  (summary.md, hourly.csv, occurrences/)"
}
