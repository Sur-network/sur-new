#!/bin/bash
# usage: v5-launch-net.sh NET [nodeN ...]   (default: all nodes). Besu 26.9.0, JVM heap capped (FINDINGS item 2).
ROOT="D:/Amir/Business/SUR/Test/besu-test-v4"
BESU="$ROOT/besu-binary/bin/besu.bat"
NET=$1; shift
cd "$ROOT/nets/$NET" || exit 1
mkdir -p "$ROOT/logs/$NET"
NODES="$@"
[ -z "$NODES" ] && NODES=$(ls -d node*/ | tr -d /)
for n in $NODES; do
  (JAVA_OPTS="-Xmx512m -Xms256m" "$BESU" --config-file="$n/config.toml" >> "$ROOT/logs/$NET/$n.log" 2>&1 &)
done
echo "launched $NET: $NODES"
