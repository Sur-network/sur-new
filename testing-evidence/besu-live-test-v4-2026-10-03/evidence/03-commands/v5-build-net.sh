#!/bin/bash
# usage: v5-build-net.sh NET FOUNDERS(G5|G6) CANDIDATE(0|1) CHAINID GASLIMIT P2P_BASE RPC_BASE [TRANSITIONS_JSON|-] [RATE_HISTORY|-] [PAYEES|0]
# Builds genesis.json + node dirs for one network with the UNMODIFIED baseline contracts (TEST-ONLY-SEED only when RATE_HISTORY/PAYEES given).
ROOT="D:/Amir/Business/SUR/Test/besu-test-v4"
NET=$1; FOUNDERS=$2; CAND=$3; CHAIN=$4; GAS=$5; P2P=$6; RPC=$7; TR=${8:--}; RH=${9:--}; PAY=${10:-0}
cd "$ROOT/hardhat" || exit 1
export BUILDER_PROJECT_ROOT="$ROOT" BUILDER_NET="$NET" BUILDER_FOUNDERS="$FOUNDERS" BUILDER_CANDIDATE="$CAND" BUILDER_CHAINID="$CHAIN" BUILDER_GASLIMIT="$GAS" BUILDER_SEED_BOARD=1 BUILDER_SEED_FOUNDATION=1 BUILDER_IS_FORK=0
[ "$TR" != "-" ] && export BUILDER_TRANSITIONS="$TR" || unset BUILDER_TRANSITIONS
[ "$RH" != "-" ] && export BUILDER_RATE_HISTORY="$RH" || unset BUILDER_RATE_HISTORY
export BUILDER_PAYEES="$PAY"
npx hardhat run scripts/testonly-build-one-v5.js --network hardhat || exit 1
# node dirs: candidate node is NOT generated (a candidate is funded for fee/membership tests only, never activated => no quorum impact)
BUILDER_CANDIDATE=0 BUILDER_P2P_BASE="$P2P" BUILDER_RPC_BASE="$RPC" node scripts/testonly-generate-nodes.js
