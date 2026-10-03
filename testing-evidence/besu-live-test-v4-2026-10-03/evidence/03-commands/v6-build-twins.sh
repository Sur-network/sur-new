#!/bin/bash
# Builds the fresh "twin" networks (same builder recipe as an original follow-up network, new timestamp/chainId) and the C-L04-6 network Net-L04f.
# usage: v6-build-twins.sh [name ...]   (default: all)
set -f
ROOT=/d/Amir/Business/SUR/Test/besu-test-v4
B="$ROOT/evidence/03-commands/v5-build-net.sh"
T300='[{"block":300,"blockreward":"3000000000000000000"}]'
T6='[{"block":100,"blockreward":"3000000000000000000"},{"block":150,"blockreward":"2000000000000000000"},{"block":200,"blockreward":"4000000000000000000"}]'
H6='[[100,"3000000000000000000"]]'
# name  founders cand chainId gas p2p rpc transitions history payees
declare -A R
R[Net-T-F1]="G5 0 424501 30000000 34001 9401 $T300 F300 0"
R[Net-T-F2]="G5 0 424502 30000000 34011 9411 $T300 - 0"
R[Net-T-F3]="G5 0 424503 30000000 34021 9421 - F300 0"
R[Net-T-F4]="G5 0 424504 30000000 34031 9431 - - 0"
R[Net-T-F6]="G5 1 424505 30000000 34041 9441 $T6 $H6 0"
R[Net-T-L05]="G5 0 424506 30000000 34051 9451 - - 0"
R[Net-T-D3]="G6 1 424507 30000000 34061 9461 - - 0"
R[Net-T-E15]="G5 0 424508 15000000 34071 9471 - E399 150"
R[Net-T-E30]="G5 0 424509 30000000 34081 9481 - E399 150"
R[Net-T-E60]="G5 0 424510 60000000 34091 9491 - E399 150"
R[Net-L04f]="G5 0 424511 30000000 34101 9501 - - 0"
NAMES="$@"; [ -z "$NAMES" ] && NAMES="Net-T-F1 Net-T-F2 Net-T-F3 Net-T-F4 Net-T-F6 Net-T-L05 Net-T-D3 Net-T-E15 Net-T-E30 Net-T-E60 Net-L04f"
for n in $NAMES; do
  set -- ${R[$n]}
  echo "== building $n"
  "$B" "$n" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" 2>&1 | tail -2
done
