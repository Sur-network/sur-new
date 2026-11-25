#!/usr/bin/env bash
# آزمون: آیا Besu 26.9.0 نام DNS را در enode یک bootnode می‌پذیرد و بعد از عوض‌شدن IP آن را دوباره پیدا می‌کند؟
# اجرا فقط روی میزبان آزمون:  ./dns-enode-test.sh <genesis.json>
# همه‌چیز در یک شبکهٔ docker جدا (surwatch-test-bootnet)، بدون پورت منتشرشده، با سقف حافظه و CPU؛ در پایان پاک می‌شود.
# هیچ ایمیجی دانلود نمی‌شود (ایمیج Besu باید از قبل روی میزبان باشد).
set -u
IMG=${IMG:-hyperledger/besu:26.9.0}
GENESIS=${1:?مسیر genesis.json را بدهید}
NETID=${NETID:-262025}
NET=surwatch-test-bootnet
SUBNET=172.29.77.0/24
W=$(mktemp -d "$HOME/surwatch-work/bootdns.XXXXXX")
PASS=0; FAIL=0

cleanup() {
  docker rm -f surwatch-test-boot-a surwatch-test-boot-a2 surwatch-test-boot-b0 surwatch-test-boot-b surwatch-test-boot-c >/dev/null 2>&1
  docker network rm "$NET" >/dev/null 2>&1
  rm -rf "$W"
}
trap cleanup EXIT

ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad()  { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

rpc() { # ip method [params]
  curl -s -m 5 -X POST -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"$2\",\"params\":${3:-[]},\"id\":1}" "http://$1:8545"
}
peers() { # ip -> number
  local h; h=$(rpc "$1" net_peerCount | sed -n 's/.*"result":"0x\([0-9a-f]*\)".*/\1/p')
  echo $((16#${h:-0}))
}
wait_rpc() { # ip
  for _ in $(seq 1 60); do rpc "$1" net_peerCount | grep -q result && return 0; sleep 2; done; return 1
}
wait_peer() { # ip seconds
  local n=0
  for _ in $(seq 1 $(( $2 / 3 ))); do n=$(peers "$1"); [ "$n" -ge 1 ] && { echo "$n"; return 0; }; sleep 3; done
  echo "$n"; return 1
}

# start name ip datadir p2phost alias dns(0/1) [bootnodes]
start() {
  local name=$1 ip=$2 dir=$3 host=$4 alias=$5 dns=$6 boot=${7:-}
  local args=(--genesis-file=/cfg/genesis.json --network-id="$NETID" --data-path=/data
    --p2p-host="$host" --p2p-port=30303 --nat-method=NONE --discovery-enabled=true --sync-mode=FULL
    --min-gas-price=0 --rpc-http-enabled --rpc-http-host=0.0.0.0 --rpc-http-api=NET,ADMIN,ETH
    --host-allowlist='*' --rpc-http-cors-origins='*')
  [ "$dns" = 1 ] && args+=(--Xdns-enabled=true --Xdns-update-enabled=true)
  [ -n "$boot" ] && args+=(--bootnodes="$boot")
  local al=(); [ -n "$alias" ] && al=(--network-alias "$alias")
  docker run -d --name "$name" --network "$NET" --ip "$ip" "${al[@]}" \
    --memory 1g --cpus 1 --user "$(id -u):$(id -g)" -e BESU_OPTS=-Xmx512m \
    -v "$dir":/data -v "$W/genesis.json":/cfg/genesis.json:ro "$IMG" "${args[@]}" >/dev/null
}

cp "$GENESIS" "$W/genesis.json"; mkdir -p "$W/a" "$W/b0" "$W/b" "$W/c"
docker network create --subnet "$SUBNET" "$NET" >/dev/null || { echo "ساخت شبکه شکست خورد"; exit 2; }

echo "== ۱) bootnode A بالا می‌آید (IP .10، نام boot-node)"
start surwatch-test-boot-a 172.29.77.10 "$W/a" 172.29.77.10 boot-node 0
wait_rpc 172.29.77.10 || { echo "A بالا نیامد"; docker logs surwatch-test-boot-a 2>&1 | tail -20; exit 2; }
ENODE=$(rpc 172.29.77.10 admin_nodeInfo | sed -n 's/.*"enode":"\([^"]*\)".*/\1/p')
PUB=${ENODE#enode://}; PUB=${PUB%%@*}
echo "  enode A: enode://${PUB:0:8}…@$(echo "$ENODE" | sed 's/.*@//')"
[ -n "$PUB" ] && ok "enode گرفته شد" || bad "enode گرفته نشد"
BOOT_DNS="enode://$PUB@boot-node:30303"

echo "== ۲) شاهد: نود B0 با نام DNS ولی «بدون» پرچم‌های DNS"
start surwatch-test-boot-b0 172.29.77.20 "$W/b0" 172.29.77.20 "" 0 "$BOOT_DNS"
sleep 25
if [ "$(docker inspect -f '{{.State.Running}}' surwatch-test-boot-b0)" != true ]; then
  echo "  (B0 بالا نیامد؛ آخرین خطاها:)"; docker logs surwatch-test-boot-b0 2>&1 | grep -iE "error|exception|dns|invalid|unresolv" | tail -3 | cut -c1-220
  ok "بدون پرچم DNS نام پذیرفته نشد (انتظار می‌رفت)"
else
  N=$(wait_peer 172.29.77.20 45) && bad "بدون پرچم هم وصل شد (پرچم لازم نبود؟) peers=$N" || ok "بدون پرچم DNS وصل نشد، peers=$N"
fi
docker rm -f surwatch-test-boot-b0 >/dev/null 2>&1

echo "== ۳) نود B با نام DNS و پرچم‌های --Xdns-enabled و --Xdns-update-enabled"
start surwatch-test-boot-b 172.29.77.21 "$W/b" 172.29.77.21 "" 1 "$BOOT_DNS"
wait_rpc 172.29.77.21 || { echo "B بالا نیامد"; docker logs surwatch-test-boot-b 2>&1 | tail -20; }
N=$(wait_peer 172.29.77.21 90) && ok "B از راه نام boot-node به A وصل شد (peers=$N)" || bad "B وصل نشد (peers=$N)"
docker logs surwatch-test-boot-b 2>&1 | grep -iE "bootnode|dns" | head -3 | cut -c1-220

echo "== ۴) IP بوت‌نود عوض می‌شود: A پاک و A2 با همان کلید، IP .11 و همان نام"
docker rm -f surwatch-test-boot-a >/dev/null
start surwatch-test-boot-a2 172.29.77.11 "$W/a" 172.29.77.11 boot-node 0
wait_rpc 172.29.77.11 || { echo "A2 بالا نیامد"; docker logs surwatch-test-boot-a2 2>&1 | tail -20; }
ENODE2=$(rpc 172.29.77.11 admin_nodeInfo | sed -n 's/.*"enode":"\([^"]*\)".*/\1/p')
[ "${ENODE2#enode://}" != "$ENODE2" ] && [ "$(echo "$ENODE2" | sed 's/enode:\/\/\([0-9a-f]*\)@.*/\1/')" = "$PUB" ] \
  && ok "A2 همان کلید (enode) را دارد، آدرس تازه $(echo "$ENODE2" | sed 's/.*@//')" || bad "کلید A2 فرق کرد"

echo "== ۵) نود تازهٔ C بعد از عوض‌شدن IP، فقط با همان نام DNS"
start surwatch-test-boot-c 172.29.77.22 "$W/c" 172.29.77.22 "" 1 "$BOOT_DNS"
wait_rpc 172.29.77.22 || { echo "C بالا نیامد"; docker logs surwatch-test-boot-c 2>&1 | tail -20; }
N=$(wait_peer 172.29.77.22 90) && ok "C با نام boot-node به IP تازه رسید (peers=$N)" || bad "C وصل نشد (peers=$N)"
REMOTE=$(rpc 172.29.77.22 admin_peers | grep -o '"remoteAddress":"[^"]*"' | head -3 | tr '\n' ' ')
echo "  همتاهای C: $REMOTE"
echo "$REMOTE" | grep -q "172.29.77.11" && ok "همتا همان IP تازه (.11) است" || bad "همتا IP تازه نیست"

echo "== ۶) اطلاع‌دهنده: B (که از پیش وصل بود) بعد از عوض‌شدن IP"
N=$(wait_peer 172.29.77.21 90) && echo "  B دوباره همتا دارد (peers=$N)" || echo "  B همتا ندارد (peers=$N)"
echo "  همتاهای B: $(rpc 172.29.77.21 admin_peers | grep -o '"remoteAddress":"[^"]*"' | tr '\n' ' ')"

echo
echo "نتیجه: $PASS گذشت، $FAIL شکست"
[ "$FAIL" -eq 0 ]
