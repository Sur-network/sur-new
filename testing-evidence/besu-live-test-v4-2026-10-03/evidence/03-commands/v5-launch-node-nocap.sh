#!/bin/bash
# usage: v5-launch-node-nocap.sh NET NODE  -- starts ONE node WITHOUT the test-wide JAVA_OPTS heap cap (JVM/Besu default heap sizing)
ROOT="D:/Amir/Business/SUR/Test/besu-test-v4"
cd "$ROOT/nets/$1" || exit 1
mkdir -p "$ROOT/logs/$1"
(env -u JAVA_OPTS "$ROOT/besu-binary/bin/besu.bat" --config-file="$2/config.toml" >> "$ROOT/logs/$1/$2.log" 2>&1 &)
echo "launched $1/$2 WITHOUT heap cap (JAVA_OPTS unset)"
