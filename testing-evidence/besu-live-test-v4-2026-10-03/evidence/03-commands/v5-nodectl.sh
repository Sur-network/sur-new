#!/bin/bash
# usage: v5-nodectl.sh pid|stop NET NODE   -- finds the Besu JVM by its RPC listening port (nodes are identical across nets by name, ports are unique)
ROOT="D:/Amir/Business/SUR/Test/besu-test-v4"
ACTION=$1; NET=$2; NODE=$3
PORT=$(node -e "const j=require('$ROOT/nets/$NET/nodes-info.json');const n=j.find(x=>x.dir==='$NODE');console.log(n?n.rpc:'')")
[ -z "$PORT" ] && { echo "unknown node"; exit 1; }
PID=$(netstat -ano | grep ":$PORT " | grep LISTENING | awk '{print $5}' | head -1)
[ -z "$PID" ] && { echo "no listener on $PORT"; exit 2; }
if [ "$ACTION" = "pid" ]; then echo "$NET/$NODE rpc=$PORT pid=$PID"; fi
if [ "$ACTION" = "stop" ]; then taskkill //PID $PID //F > /dev/null && echo "stopped $NET/$NODE (pid $PID, rpc $PORT)"; fi
