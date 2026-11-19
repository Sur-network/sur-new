#!/bin/bash
# SUR Besu soak test kit: starts the net, the collector and the load generator and supervises them for <hours>.
#
#   ./run-soak.sh <hours> [besu-image-tag] [validators 4|7] [options]
#
#   hours              soak duration after the bootstrap (24 .. 72 recommended; fractions allowed, e.g. 0.5)
#   besu-image-tag     26.9.0 (default) | 26.8.1 | develop | 26.9-develop-260f602 | a full image reference (anything with ':' or '/')
#   validators         7 (default) | 4
#
# options:
#   --interval-minutes N   minutes per collector row (default 60; use 2 for a short test)
#   --phase-plan "name:min:txPerSec:changeEveryMin[:burstEveryMin],..."   load phases, cycled (default: see README)
#   --poll-hz N            getValidators() eth_call poller rate (default 1; 0 = off)
#   --entrant-frac F       activate the extra entrant (owner8/node x2) at this fraction of the run (default 0.4; 0 = never)
#   --loadgen-image IMG    image for load generator/collector/analysis (default node:22-alpine; needs node >= 20)
#   --node-mem MB          container memory limit per Besu node (default 1536)   --node-cpus N (default 1.5)   --java-xmx 768m
#   --log-level L          Besu log level (default INFO)
#   --tag NAME             free text added to the run directory name
#   --pull                 allow `docker pull` of missing images (the list is printed first); without it missing images stop the run
#   --dry-run              print what would be done and exit
#
# It never pulls anything by itself. Needs: bash, docker. Results: runs/<run-id>/  (summary.md at the end).
set -u
source "$(dirname "$0")/lib/common.sh"

HOURS="${1:-}"; [ -n "$HOURS" ] || { sed -n '2,24p' "$0"; exit 2; }
shift
BESU_TAG="26.9.0"; VALS="7"
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then BESU_TAG="$1"; shift; fi
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then VALS="$1"; shift; fi
INTERVAL_MIN=60; POLL_HZ=1; ENTRANT_FRAC=0.4; LOADGEN_IMAGE="$LOADGEN_IMAGE_DEFAULT"; NODE_MEM=1536; NODE_CPUS=1.5; JAVA_XMX=768m
LOG_LEVEL=INFO; TAG=""; PULL=0; DRY=0
PHASE_PLAN="idle:30:0:0,transfers:60:0.5:0,changes:60:0.5:15,heavy:30:5:0:5,changes-heavy:30:5:10:5"
while [ $# -gt 0 ]; do
  case "$1" in
    --interval-minutes) INTERVAL_MIN="$2"; shift 2;;
    --phase-plan) PHASE_PLAN="$2"; shift 2;;
    --poll-hz) POLL_HZ="$2"; shift 2;;
    --entrant-frac) ENTRANT_FRAC="$2"; shift 2;;
    --loadgen-image) LOADGEN_IMAGE="$2"; shift 2;;
    --node-mem) NODE_MEM="$2"; shift 2;;
    --node-cpus) NODE_CPUS="$2"; shift 2;;
    --java-xmx) JAVA_XMX="$2"; shift 2;;
    --log-level) LOG_LEVEL="$2"; shift 2;;
    --tag) TAG="$2"; shift 2;;
    --pull) PULL=1; shift;;
    --dry-run) DRY=1; shift;;
    *) die "unknown option $1";;
  esac
done
case "$VALS" in 4|7) ;; *) die "validators must be 4 or 7";; esac
NET="n$VALS"
BESU_IMAGE="$(resolve_besu_image "$BESU_TAG")"
NETDIR="$KIT_DIR/nets/$NET"
[ -f "$NETDIR/genesis.json" ] || die "missing $NETDIR/genesis.json"
[ -f "$KIT_DIR/vendor/node_modules.tgz" ] || die "missing vendor/node_modules.tgz"

# ---------------------------------------------------------------- preflight
command -v docker >/dev/null || die "docker not found"
docker info >/dev/null 2>&1 || die "cannot talk to the docker daemon (is the user in the docker group?)"
[ -z "$(kit_containers)$(kit_networks)" ] || die "objects of an earlier run exist (sur25s-*). Save its results, then run ./cleanup.sh"
runner_alive && die "another run-soak.sh is running (pid $(cat "$STATE_DIR/run.pid"))"
for n in $(docker network ls -q); do
  for cidr in $(docker network inspect "$n" --format '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null); do
    case "$cidr" in *:*) continue;; esac
    subnet_overlaps "$cidr" && die "docker network $(docker network inspect "$n" --format '{{.Name}}') ($cidr) overlaps ${SUBNET_BASE}.0/24, which is baked into the node configs (nets/*/*/static-nodes.json). Remove that network or rebuild the genesis with another subnet."
  done
done
MISSING=""
docker image inspect "$BESU_IMAGE" >/dev/null 2>&1 || MISSING="$MISSING $BESU_IMAGE"
docker image inspect "$LOADGEN_IMAGE" >/dev/null 2>&1 || MISSING="$MISSING $LOADGEN_IMAGE"
if [ -n "$MISSING" ]; then
  say "Docker images missing on this host:$MISSING"
  if [ "$PULL" = 1 ]; then
    say "--pull given: pulling now (download sizes: besu ~0.9 GB, node:22-alpine ~0.15 GB)"
    for i in $MISSING; do say "docker pull $i"; docker pull "$i" || die "pull failed: $i"; done
  else
    say "Run these yourself (internet needed), then start again:"; for i in $MISSING; do echo "    docker pull $i"; done
    exit 3
  fi
fi
NEED_GB=$(awk -v h="$HOURS" -v n="$VALS" 'BEGIN{printf "%d", 3 + (n+2)*(0.4 + 0.015*h) + 1}')
FREE_GB=$(df -Pk "$KIT_DIR" | awk 'NR==2{printf "%d", $4/1048576}')
say "disk: ${FREE_GB} GB free where the kit lives, estimate for this run ${NEED_GB} GB (docker volumes live under /var/lib/docker, check there too)"
if [ -r /proc/meminfo ]; then MEM_GB=$(awk '/MemAvailable/{printf "%d", $2/1048576}' /proc/meminfo); say "RAM available: ${MEM_GB} GB; this run uses about $(( (VALS + 2) * 700 / 1024 + 1 )) GB (limit per node ${NODE_MEM} MB)"; fi
[ "$FREE_GB" -ge "$NEED_GB" ] 2>/dev/null || say "WARNING: less free disk than the estimate"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_ID="${STAMP}-besu-$(echo "$BESU_TAG" | tr -c 'A-Za-z0-9.\n-' '_')-n${VALS}-${HOURS}h${TAG:+-$TAG}"
RUN_DIR="$RUNS_DIR/$RUN_ID"

echo "================================================================"
echo " SUR soak: ${HOURS} h, Besu ${BESU_IMAGE}, ${VALS} validators (net $NET)"
echo " run dir        : $RUN_DIR"
echo " containers     : ${PREFIX}n1..n${VALS}, ${PREFIX}x1, ${PREFIX}x2 (Besu), ${PREFIX}collector, ${PREFIX}loadgen   network ${NETWORK} ${SUBNET_BASE}.0/24"
echo " JSON-RPC       : 127.0.0.1 only, host ports 19611.. (see nets/$NET/nodes.tsv)"
echo " load phases    : $PHASE_PLAN"
echo " getValidators  : ${POLL_HZ} Hz poller; entrant activation at ${ENTRANT_FRAC} of the run; rows every ${INTERVAL_MIN} min"
echo " limits per node: ${NODE_MEM} MB RAM, ${NODE_CPUS} CPUs, JVM -Xmx${JAVA_XMX}; restart policy on-failure:20 (restarts are recorded, never hidden)"
echo " NOT pulled     : nothing is downloaded by this script (images checked above are local)"
echo "================================================================"
[ "$DRY" = 1 ] && { say "dry run: nothing started"; exit 0; }

mkdir -p "$RUN_DIR"/{meta,logs,occurrences,collector,load}
echo "$RUN_DIR" > "$STATE_DIR/current-run"
echo $$ > "$STATE_DIR/run.pid"
BESU_IMAGE_ID="$(docker image inspect -f '{{.Id}}' "$BESU_IMAGE")"
LG_IMAGE_ID="$(docker image inspect -f '{{.Id}}' "$LOADGEN_IMAGE")"
GENESIS_SHA="$(sha256sum "$NETDIR/genesis.json" | cut -d' ' -f1)"
cat > "$RUN_DIR/meta/run.json" <<EOF
{
  "kitVersion": "soak-kit-v25",
  "net": "$NET", "validators": $VALS, "hours": $HOURS, "intervalMinutes": $INTERVAL_MIN, "phasePlan": "$PHASE_PLAN", "pollHz": $POLL_HZ, "entrantFrac": $ENTRANT_FRAC,
  "image": "$BESU_IMAGE", "imageId": "$BESU_IMAGE_ID", "loadgenImage": "$LOADGEN_IMAGE", "loadgenImageId": "$LG_IMAGE_ID",
  "nodeMemMB": $NODE_MEM, "nodeCpus": $NODE_CPUS, "javaXmx": "$JAVA_XMX", "logLevel": "$LOG_LEVEL", "genesisSha256": "$GENESIS_SHA",
  "createdUtc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)", "host": "$(uname -sr | tr -d '"')", "dockerServer": "$(docker version -f '{{.Server.Version}}' 2>/dev/null)"
}
EOF
docker info > "$RUN_DIR/meta/docker-info.txt" 2>&1 || true
exec > >(tee -a "$RUN_DIR/supervisor.log") 2>&1

ABORT=0
trap 'ABORT=1; say "signal received: finishing the run early"' INT TERM

fail_run() { say "FATAL: $*"; finish_run "$RUN_DIR"; rm -f "$STATE_DIR/run.pid"; exit 1; }

say "creating network $NETWORK"
docker network create --driver bridge --subnet "${SUBNET_BASE}.0/24" --gateway "${SUBNET_BASE}.1" --label sur25s.kit=1 "$NETWORK" >/dev/null || fail_run "network create failed"

say "starting Besu nodes"
while IFS=$'\t' read -r name ip port opaddr; do
  [ -n "$name" ] || continue
  docker volume create --label sur25s.kit=1 "${PREFIX}${name}-data" >/dev/null
  docker run -d --pull never --name "${PREFIX}${name}" --network "$NETWORK" --ip "$ip" -p "127.0.0.1:${port}:8545" \
    --label sur25s.kit=1 --label "sur25s.node=$name" \
    --memory "${NODE_MEM}m" --memory-swap "${NODE_MEM}m" --cpus "$NODE_CPUS" --stop-timeout 30 \
    --restart on-failure:20 --log-driver json-file --log-opt max-size=20m --log-opt max-file=3 \
    -e JAVA_OPTS="-Xms128m -Xmx${JAVA_XMX}" \
    -v "$KIT_DIR_HOST/nets/$NET:/net:ro" -v "${PREFIX}${name}-data:/data" \
    -v "$KIT_DIR_HOST/nets/$NET/$name/static-nodes.json:/data/static-nodes.json:ro" \
    "$BESU_IMAGE" --config-file="/net/$name/config.toml" --logging="$LOG_LEVEL" >/dev/null || fail_run "could not start $name"
  say "  started ${PREFIX}${name} ip=$ip rpc=127.0.0.1:$port"
done < "$NETDIR/nodes.tsv"

say "starting collector"
docker run -d --pull never --name "${PREFIX}collector" --network "$NETWORK" --label sur25s.kit=1 --restart no \
  -v "$KIT_DIR_HOST:/kit:ro" -v "$(host_path "$RUN_DIR"):/run-data" -v /var/run/docker.sock:/var/run/docker.sock \
  -e NET="$NET" -e RUN_DIR=/run-data -e KIT_DIR=/kit -e NODE_PATH=/opt/node_modules -e SOAK_PREFIX="$PREFIX" -e INTERVAL_MIN="$INTERVAL_MIN" \
  "$LOADGEN_IMAGE" sh -c "mkdir -p /opt && tar -xzf /kit/vendor/node_modules.tgz -C /opt && exec node /kit/runtime/collector.js" >/dev/null || fail_run "could not start the collector"

say "bootstrap: waiting for the nodes, then activating validators 2..$VALS through the Registry (setOperator + recordActivation)"
TOOL_NETWORK="$NETWORK" run_tool "$LOADGEN_IMAGE" "$RUN_DIR" "$NET" bootstrap.js 2>&1 | tee "$RUN_DIR/load/bootstrap.log"
[ "${PIPESTATUS[0]}" = 0 ] || fail_run "bootstrap failed (see $RUN_DIR/load/bootstrap.log)"
[ "$ABORT" = 1 ] && fail_run "aborted during bootstrap"

START_MS=$(now_ms)
END_MS=$(awk -v s="$START_MS" -v h="$HOURS" 'BEGIN{printf "%.0f", s + h*3600000}')
echo "{\"startMs\": $START_MS, \"endMs\": $END_MS, \"hours\": $HOURS, \"startUtc\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$RUN_DIR/meta/window.json"
say "SOAK CLOCK STARTED: $HOURS h, ends $(date -u -d "@$((END_MS/1000))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "in $HOURS h")"

start_loadgen() {
  docker run -d --pull never --name "${PREFIX}loadgen" --network "$NETWORK" --label sur25s.kit=1 --restart no \
    -v "$KIT_DIR_HOST:/kit:ro" -v "$(host_path "$RUN_DIR"):/run-data" \
    -e NET="$NET" -e RUN_DIR=/run-data -e KIT_DIR=/kit -e NODE_PATH=/opt/node_modules -e SOAK_PREFIX="$PREFIX" \
    -e PHASE_PLAN="$PHASE_PLAN" -e POLL_HZ="$POLL_HZ" -e ENTRANT_AT_FRAC="$ENTRANT_FRAC" \
    "$LOADGEN_IMAGE" sh -c "mkdir -p /opt && tar -xzf /kit/vendor/node_modules.tgz -C /opt && exec node /kit/runtime/loadgen.js" >/dev/null
}
start_loadgen || fail_run "could not start the load generator"

# ---------------------------------------------------------------- supervision (does not hide anything: every intervention is logged)
LAST_BEAT=0
declare -A DOWN_SINCE
while [ "$ABORT" = 0 ]; do
  NOW=$(now_ms)
  [ "$NOW" -ge "$END_MS" ] && { say "duration reached"; break; }
  [ -f "$RUN_DIR/STOP" ] && { say "STOP file found"; break; }
  for c in loadgen collector; do
    if [ "$(docker inspect -f '{{.State.Running}}' ${PREFIX}$c 2>/dev/null)" != "true" ]; then
      say "SUPERVISOR: ${PREFIX}$c is not running (exit code $(docker inspect -f '{{.State.ExitCode}}' ${PREFIX}$c 2>/dev/null)); restarting it (both are resumable)"
      echo "$(date -u +%FT%TZ) $c restarted by supervisor" >> "$RUN_DIR/meta/supervisor-restarts.log"
      docker logs --tail 30 ${PREFIX}$c >> "$RUN_DIR/meta/supervisor-restarts.log" 2>&1
      docker start ${PREFIX}$c >/dev/null 2>&1 || say "SUPERVISOR: restart of $c failed"
    fi
  done
  # a Besu node that stayed down (e.g. killed by hand, or restart attempts used up) is started again after 60 s; docker's own restarts of crashed nodes are separate and visible in docker-events.jsonl
  for c in $(docker ps -a --filter label=sur25s.node --format '{{.Names}}'); do
    if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" != "true" ]; then
      [ -n "${DOWN_SINCE[$c]:-}" ] || DOWN_SINCE[$c]=$NOW
      if [ $((NOW - ${DOWN_SINCE[$c]})) -ge 60000 ]; then
        say "SUPERVISOR: node $c has been down for 60 s (exit code $(docker inspect -f '{{.State.ExitCode}}' "$c" 2>/dev/null)); starting it again"
        echo "$(date -u +%FT%TZ) node $c started again by supervisor" >> "$RUN_DIR/meta/supervisor-restarts.log"
        docker logs --tail 30 "$c" >> "$RUN_DIR/meta/supervisor-restarts.log" 2>&1
        docker start "$c" >/dev/null 2>&1 || say "SUPERVISOR: start of $c failed"
        DOWN_SINCE[$c]=""
      fi
    else DOWN_SINCE[$c]=""; fi
  done
  if [ $((NOW - LAST_BEAT)) -ge 600000 ]; then LAST_BEAT=$NOW; say "heartbeat: $(sed -n 2p "$RUN_DIR/status.txt" 2>/dev/null)"; fi
  sleep 10 & wait $! 2>/dev/null
done
finish_run "$RUN_DIR"
rm -f "$STATE_DIR/run.pid"
