#!/bin/bash
# Checks that Besu starts and produces blocks when the genesis header timestamp is old (the pre-built genesis is dated the day the kit was built,
# a run may start days later). Runs ONE validator (n1 of the 4-validator net, the only Active validator at genesis) from a temporary copy of
# nets/n4 whose "timestamp" is 10 days in the past. Needs the besu image locally and a free sur25s-net subnet. Cleans up after itself.
#   tools/test-stale-genesis.sh [besu-tag]
source "$(dirname "$0")/../lib/common.sh"
IMAGE="$(resolve_besu_image "${1:-26.9.0}")"
[ -z "$(kit_containers)$(kit_networks)" ] || die "sur25s-* objects exist; run ./cleanup.sh first"
T="$RUNS_DIR/_stale-genesis"; rm -rf "$T"; mkdir -p "$T"; cp -r "$KIT_DIR/nets/n4/." "$T/"
OLD=$(( $(date +%s) - 10*86400 ))
# patch only the header timestamp (hex) of the temporary copy; contract storage is untouched
sed -i "s/^  \"timestamp\": \"0x[0-9a-f]*\"/  \"timestamp\": \"$(printf '0x%x' $OLD)\"/" "$T/genesis.json"
grep -m1 '"timestamp"' "$T/genesis.json"
docker network create --subnet "${SUBNET_BASE}.0/24" --gateway "${SUBNET_BASE}.1" --label sur25s.kit=1 "$NETWORK" >/dev/null
docker volume create --label sur25s.kit=1 ${PREFIX}stale-data >/dev/null
docker run -d --pull never --name ${PREFIX}stale --network "$NETWORK" --ip ${SUBNET_BASE}.11 --label sur25s.kit=1 -e JAVA_OPTS="-Xms128m -Xmx768m" \
  -v "$(host_path "$T"):/net:ro" -v ${PREFIX}stale-data:/data "$IMAGE" --config-file=/net/n1/config.toml >/dev/null
sleep 45
echo "--- last log lines (blocks should be produced with the current time, 2 s apart):"
docker logs ${PREFIX}stale 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Produced|Imported" | tail -4 | cut -c1-140
N=$(docker logs ${PREFIX}stale 2>&1 | grep -c "Produced")
echo "blocks produced in 45 s: $N"
docker rm -f ${PREFIX}stale >/dev/null; docker volume rm ${PREFIX}stale-data >/dev/null; docker network rm "$NETWORK" >/dev/null; rm -rf "$T"
[ "$N" -ge 5 ] && echo "STALE GENESIS TEST PASS" || { echo "STALE GENESIS TEST FAIL"; exit 1; }
