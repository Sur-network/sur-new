#!/bin/bash
# Local Docker control for the v2.5 Besu test. Everything is prefixed "sur25-". Image: hyperledger/besu:26.9.0 (already present locally; never pulled).
# usage:
#   netctl.sh netcreate A|S|L2          create the docker bridge network (fixed subnet)
#   netctl.sh start A n1 [n2 ...]       start nodes (creates the container + data volume the first time, `docker start` afterwards)
#   netctl.sh stop A n2                 stop (container + data kept)
#   netctl.sh logs A n1 > file          raw logs
#   netctl.sh status                    docker ps of sur25-* only
#   netctl.sh saveall A                 copy the logs of all nodes of a net into $EVID/logs/<net>/
#   netctl.sh destroy A                 remove containers, volumes and network of the net (saves logs first)
source "$(dirname "$0")/env.sh"
IMAGE="hyperledger/besu:26.9.0"
cmd=$1; net=$2; shift 2 2>/dev/null
case "$net" in A) NETNAME=Net-A; SUBNET=172.29.51.0/24; GW=172.29.51.1;; S) NETNAME=Net-S; SUBNET=172.29.52.0/24; GW=172.29.52.1;; L2) NETNAME=Net-L2; SUBNET=172.29.53.0/24; GW=172.29.53.1;; T) NETNAME=Net-T; SUBNET=172.29.54.0/24; GW=172.29.54.1;; esac
lc=$(echo "$net" | tr 'A-Z' 'a-z')
DN="sur25-net-$lc"
nodeinfo() { node -e "const j=require('$EVID/nets/$NETNAME/nodes-info.json');const n=j.find(x=>x.node==='$1');console.log(n.ip+' '+n.rpcHostPort)"; }
case "$cmd" in
  netcreate) docker network create --driver bridge --subnet "$SUBNET" --gateway "$GW" "$DN" ;;
  start)
    for n in "$@"; do
      c="sur25-$lc-$n"
      if docker ps -a --format '{{.Names}}' | grep -qx "$c"; then docker start "$c"; continue; fi
      read ip rpc < <(nodeinfo $n)
      docker volume create "sur25-$lc-$n-data" >/dev/null
      docker run -d --name "$c" --network "$DN" --ip "$ip" -p "127.0.0.1:$rpc:8545" \
        -e JAVA_OPTS="-Xms128m -Xmx640m" \
        -v "$EVID/nets/$NETNAME:/net:ro" -v "sur25-$lc-$n-data:/data" \
        -v "$EVID/nets/$NETNAME/$n/static-nodes.json:/data/static-nodes.json:ro" \
        "$IMAGE" --config-file="/net/$n/config.toml" >/dev/null && echo "started $c ip=$ip rpc=127.0.0.1:$rpc"
    done ;;
  stop) for n in "$@"; do docker stop -t 15 "sur25-$lc-$n"; done ;;
  logs) docker logs "sur25-$lc-$1" 2>&1 ;;
  status) docker ps -a --filter "name=sur25-" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' ;;
  saveall) mkdir -p "$EVID/logs/$NETNAME"; for c in $(docker ps -a --format '{{.Names}}' | grep "^sur25-$lc-"); do docker logs "$c" > "$EVID/logs/$NETNAME/${c#sur25-$lc-}.log" 2>&1; done; ls "$EVID/logs/$NETNAME" ;;
  destroy)
    "$0" saveall $net
    for c in $(docker ps -a --format '{{.Names}}' | grep "^sur25-$lc-"); do docker rm -f "$c" >/dev/null; done
    for v in $(docker volume ls --format '{{.Name}}' | grep "^sur25-$lc-"); do docker volume rm "$v" >/dev/null; done
    docker network rm "$DN" >/dev/null; echo "destroyed $net" ;;
esac
