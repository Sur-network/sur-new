# SUR Besu soak-test kit (finding F-1), v2.5 contracts

A self-contained kit to run a 7-validator (or 4-validator) Besu QBFT contract-mode network on ONE Ubuntu server for 24 to 72 hours, with a
realistic load, and to measure **F-1** from round 1 (`../besu-live-test-v25-2026-11-19/FINDINGS.md`): Besu 26.9.0 sometimes logs

    IllegalStateException: Failed validator smart contract call: unable to execute call at block N

(8 times in about 1,100 blocks in round 1, probably a race between block import `PersistBlockTask` and the BFT message handler; one BFT message dropped each time, no block-time gap).

Questions the kit answers: how often does it happen over days; under which conditions (quiet, transactions, validator-list changes); does it ever stall or slow
consensus; does it depend on the number of validators (7 vs 4) or on the transaction load; does it also happen on Besu 26.8.1 and on the 26.9 develop build.

This is test evidence on a throw-away local network with throw-away keys. It says nothing about production readiness by itself.

## 1. What is in the kit

| Path | What |
| --- | --- |
| `run-soak.sh <hours> [besu-image-tag] [4\|7] [options]` | starts everything, runs the bootstrap, supervises for `<hours>`, then writes the results |
| `stop-soak.sh` | ends the run early and writes the results (also works after a crash/reboot) |
| `status.sh` | one-screen state of the run |
| `collect-results.sh [run-dir] [--tar]` | (re)builds `summary.md` and the CSV files; `--tar` packs the run for download |
| `cleanup.sh [--yes] [--purge-runs]` | removes ONLY `sur25s-*` containers, volumes and the network `sur25s-net` |
| `RUN-CHECKLIST.md` | the printable checklist (prerequisites, start, watch, stop, bring results back) |
| `nets/n7/`, `nets/n4/` | PRE-BUILT genesis, node keys, node configs (`config.toml`, `key`, `static-nodes.json`) for 7 and 4 validators, `nodes.tsv`, `soak-net.json` |
| `TEST-KEYS-DO-NOT-REUSE.json` | the throw-away test keys (see section 8) |
| `vendor/node_modules.tgz` | ethers 6.17.0 and its dependencies, pre-vendored (1.2 MB compressed, 4.2 MB unpacked), so the server needs no npm |
| `runtime/` | container-side scripts (plain Node.js): `bootstrap.js`, `loadgen.js`, `collector.js`, `analyze.js`, `chain.js`, `common.js`, `abi.json` |
| `lib/common.sh` | shared shell code |
| `tools/` | genesis builder and key generator (used on the PC that built the kit, not needed on the server), `test-parser.sh`, `soak.service.example` |
| `verification/` | evidence that the kit was run and checked on the build PC |
| `runs/<run-id>/` | created by each run: all results (not committed) |

Containers (all named `sur25s-*`, label `sur25s.kit=1`): `sur25s-n1..n7` (validators; `n1..n4` in the 4-validator variant), `sur25s-x1` and `sur25s-x2` (two extra Besu
nodes, see 3.2), `sur25s-collector`, `sur25s-loadgen`. Network `sur25s-net` = 172.29.71.0/24 (fixed IPs; the enodes are baked into the node files). Volumes `sur25s-<node>-data`.
JSON-RPC of every node is published on **127.0.0.1 only**, ports 19611..19617 (n1..n7), 19621 (x1), 19622 (x2); in the 4-validator variant 19611..19614, 19621, 19622. Nothing listens on a public interface.

## 2. Prerequisites on the server

- Ubuntu 22.04 or 24.04, Docker Engine (`docker ps` must work for your user, i.e. you are in the `docker` group or use sudo for every script), `bash`, `tar`, `df`, `awk`, `sed`. Nothing else: no Node.js, no Python, no npm, no jq.
- Internet access ONLY for pulling the images (once). **The kit never pulls**: every `docker run` has `--pull never`; if an image is missing `run-soak.sh` prints the exact `docker pull` line and stops (`--pull` lets it pull after printing the list).
- Images (you run the pulls):

      docker pull hyperledger/besu:26.9.0        # about 0.9 GB   baseline (round 1 used 26.9.0)
      docker pull node:22-alpine                 # about 0.15 GB  load generator, collector, analysis (runs vendored ethers, no npm)
      docker pull hyperledger/besu:26.8.1        # comparison run (optional)
      docker pull hyperledger/besu:develop       # comparison run (optional); any other tag works the same way

  The second argument of `run-soak.sh` is the Besu tag (`26.9.0`, `26.8.1`, `develop`, `26.9-develop-260f602`) or a full image reference (anything containing `:` or `/`).
- Free disk and RAM: see section 5. Free local ports: 19611 to 19622.
- The server clock should be synchronised (`timedatectl`).

## 3. What a run does

### 3.1 Start (about 2 minutes, before the clock starts)

1. Preflight (docker reachable, no leftovers of an earlier run, subnet free, images present, disk and RAM report). It prints a banner with everything it will use.
2. Creates network and volumes, starts the Besu nodes (`--restart on-failure:20`, memory and CPU limits, log driver json-file 20 MB x 3 as a safety net).
3. Starts the collector (it follows the logs from the first line).
4. **Bootstrap** (`runtime/bootstrap.js`): waits until all nodes are up and synced; genesis has only owner1/op1 Active, owners 2..N are founders in Probation, so for each of them the script does `setOperator(op_i)` (owner) and
   `recordActivation` (Verifier test key), exactly the Registry flow of round 1, and waits until the QBFT set has grown (1, 2, ... N validators). The entrant (owner8) gets its operator key set now. Four load accounts register an identity.
   F-1 occurrences during this phase are counted separately as "bootstrap".
5. Writes `meta/window.json` and **the soak clock starts**; the load generator starts.

### 3.2 Load (container `sur25s-loadgen`), configurable with `--phase-plan`

The default plan is a cycle of 3.5 hours (repeats for the whole run, so a 72 h run sees about 20 cycles):

| Phase | Minutes | Plain transfers | Validator-list change | What it isolates |
| --- | --- | --- | --- | --- |
| `idle` | 30 | none (empty blocks) | none | pure consensus, quiet |
| `transfers` | 60 | 0.5 tx/s (1 tx / 2 s) | none | transactions, no list change |
| `changes` | 60 | 0.5 tx/s | one every ~15 min (+-30 %) | list changes (round 1 coincidence) |
| `heavy` | 30 | 5 tx/s plus a 60-tx burst every 5 min | none | transaction load |
| `changes-heavy` | 30 | 5 tx/s plus bursts | one every ~10 min | both |

Plan syntax: `name:minutes:txPerSec:changeEveryMin[:burstEveryMin]` separated by commas, e.g. `--phase-plan "steady:1440:0.5:15"` for one flat profile, or `"quiet:1440:0:0"` for no load at all.

Always on while a phase has `txPerSec > 0`: every 20 s an IdentityRegistry oracle call that changes state (`setPhoneVerified` / `setTelegramVerified` toggles). Always on (unless `--poll-hz 0`): an `eth_call getValidators()` poller, 1 per second, rotating over all nodes (a dashboard mimic).

**Validator-list changes** are real Registry transactions, rotating (each is one change of what `getValidators()` returns, mined in one block):

- `swap`: owner(N-1) (owner6 / owner3 on the 4-validator net) `proposeOperator(new key)`, a short pause plus a lag check of the new node (the Verifier's health check, simulated), then Verifier `confirmOperatorReady`. The owner alternates between its original node and the extra node `x1`; both always run.
- `selfSuspend` of owner(N) (owner7 / owner4; not a board member), later `requestResume` plus Verifier `recordResume`: the validator count drops by one for a while and comes back.
- once, at 40 % of the run (`--entrant-frac`), during a change phase: Verifier `recordActivation` of the extra entrant owner8 (node `x2`): 7 becomes 8 validators for the rest of the run (4 becomes 5). `0` disables it.
- when a phase without list changes starts, a suspended validator is resumed first, so quiet phases run at full strength.

### 3.3 Collector (container `sur25s-collector`; Docker Engine API through the mounted socket + JSON-RPC)

- Follows every node's log, keeps it (`logs/<node>.log`, rotated at 100 MB into `.log.gz`, 12 files kept per node), counts per node and per interval the F-1 line and other ERROR/WARN classes (message normalised: numbers and hashes replaced).
- **Every occurrence of F-1**: 15 lines before + the matching line + 45 lines after go to `occurrences/<node>__<seq>__block<N>__<time>.txt`, indexed in `occurrences.jsonl`. One occurrence = one log entry (the message appears twice in the stack trace).
- Every block into `blocks.csv`: number, timestamp, hash, miner (proposer), transaction count, gas, QBFT round (from `extraData`), validator count, validator-set id (the sets are in `valsets.jsonl`).
- **One row per interval** (default 60 min; `--interval-minutes N` shortens it) in `hourly.csv` (flat) and `hourly.jsonl` (detail): head, blocks, tx count, validator count range, list changes, block-time p50/p95/p99/max from header timestamps, gaps > 2.5 s, gaps >= 10 s, blocks mined in a round > 0,
  F-1 per node, other ERROR classes (top 8) and WARN count, container restarts / OOM / not-running, peer counts, **fork check** (same hash at the same heights on every node: the common head minus 3, one before it, and 6 random older heights), docker stats (memory and CPU per node), Docker volume sizes, run folder size, free disk, load generator counters.
- `docker-events.jsonl`: every die / oom / kill / start / restart event of the kit's containers. `status.txt`: refreshed every 15 s (what `status.sh` shows).
- Restarts are **recorded, not hidden**: Besu containers have `--restart on-failure:20`; each restart shows in the events file, in `restarts` of the row and in the summary. The runner restarts a dead collector or load generator (both resume where they stopped) and a Besu node that stayed down for 60 s, and writes each intervention to `meta/supervisor-restarts.log`.

### 3.4 End

After `<hours>` the runner stops the load generator, lets the collector write the last (partial) row and do a final fork check, stops the Besu containers, runs the analysis (`summary.md`) and writes the file `RESULT-READY`.
Containers and volumes stay (so you can still look at the chain data) until `./cleanup.sh`.

## 4. Commands (copy and paste)

Copy the kit (from your PC; the kit without `runs/` is a few MB):

    rsync -a --exclude runs --exclude .state soak-kit-v25/ user@server:~/soak-kit-v25/
    # or: scp -r soak-kit-v25 user@server:~/

Pull the images (on the server, once; see section 2). If the copy lost the execute bits run `chmod +x *.sh lib/*.sh tools/*.sh` once (or start the scripts with `bash run-soak.sh ...`); the files must have LF line endings (a `.gitattributes` in the kit enforces it for git checkouts; do not edit them with a CRLF editor). Then, on the server:

    cd ~/soak-kit-v25
    ./run-soak.sh 1 26.9.0 7 --interval-minutes 5 --tag smoke      # optional 1 h smoke test; read runs/*/summary.md; then ./cleanup.sh --yes

    tmux new -s soak                                               # survives a closed SSH session
    ./run-soak.sh 72 26.9.0 7                                      # THE soak: 72 h, 7 validators, Besu 26.9.0 (detach: Ctrl-b d, back: tmux attach -t soak)

or without tmux: `nohup ./run-soak.sh 72 26.9.0 7 > soak.out 2>&1 &`, or as a service: `tools/soak.service.example` (do not enable at boot).

Watch: `./status.sh`. Stop early: `./stop-soak.sh`. Bring the results home:

    ./collect-results.sh runs/<run-id> --tar                       # on the server
    scp user@server:~/soak-kit-v25/runs/<run-id>.tar.gz .          # on your PC
    ./cleanup.sh --yes                                             # on the server, after the tar is safe

Comparison runs (one at a time, `./cleanup.sh --yes` between them):

    ./run-soak.sh 24 26.8.1 7                    # previous Besu release
    ./run-soak.sh 24 develop 7                   # develop build (or the exact tag you pulled)
    ./run-soak.sh 24 26.9.0 4                    # 4 validators
    ./run-soak.sh 24 26.9.0 7 --poll-hz 0 --tag nopoll          # without the dashboard poller
    ./run-soak.sh 24 26.9.0 7 --phase-plan "quiet:1440:0:0" --poll-hz 0 --entrant-frac 0 --tag quiet   # no transactions, no list changes

All options: `./run-soak.sh` without arguments prints them; `--dry-run` shows the banner and checks without starting anything.
Useful extras: `--log-level DEBUG` (VERY verbose; only for a short run: the logs grow by a factor of 10 or more), `--node-mem`, `--node-cpus`, `--java-xmx`, `--loadgen-image`.

## 5. Resources (measured on the build PC, 7 validators + x1 + x2, see `verification/`)

Measured in a 27-minute run of the 7-validator net (9 Besu nodes, 3,359 transfers, 808 blocks in the window, `verification/run1-n7-26.9.0-27min/`) and extrapolated. A 72 h run was not done here; treat the extrapolation as an estimate and watch the first rows.

| Resource | Measured in 27 min | Estimate for 72 h, 7 validators (9 Besu nodes) | 4 validators (6 nodes) |
| --- | --- | --- | --- |
| RAM per Besu node (docker stats, without page cache) | 380 to 490 MB (limit set to 1.5 GB, JVM `-Xmx768m`) | plan 1 GB per node: **about 10 GB** for 9 nodes + 0.1 GB collector/loadgen; **server with 16 GB** | about 7 GB; server with 8 to 12 GB |
| CPU | per node 3 to 28 % of one core at the sampling instants, mean about 10 % | **4 vCPUs minimum** (about 1 to 1.5 cores busy on average, bursts higher; a starved CPU delays blocks and would spoil the measurement) | 2 to 4 vCPUs |
| Chain data (Docker volumes, under /var/lib/docker) | 1 MB per node at the start, 7 MB per node after 850 blocks and 3,400 transactions (about 1.8 KB per transaction per node, empty blocks cost almost nothing) | default plan sends about 440,000 transfers in 72 h: **about 0.9 GB per node, about 8 GB** for 9 nodes (RocksDB can temporarily need more) | about 5.5 GB |
| Logs in `runs/<id>/logs` | 2.7 MB for all nodes in 27 min (about 6 MB/h; about 430 MB for 72 h raw); rotated at 100 MB per node into .gz, 12 kept | 0.2 to 0.5 GB | 0.15 to 0.3 GB |
| Docker's own json logs | capped at 20 MB x 3 per container | at most 0.7 GB (11 containers) | 0.5 GB |
| `blocks.csv`, `hourly.*`, occurrences | 128 KB for 850 blocks | about 20 MB for 130,000 blocks | same |
| Images | besu 0.9 GB, node:22-alpine 0.15 GB | 1.1 GB (shared by all runs) | |
| **Free disk to plan for** | | **25 GB** (run-soak.sh prints its own estimate: about 16 GB for 72 h) | 15 GB |

Block rate is 1 block per 2 s = 1,800 per hour = about 130,000 in 72 h per node. Everything above scales linearly with the transaction rate you configure.

## 6. How to read the results

Start with `runs/<id>/summary.md`:

1. **"Answer in numbers"**: F-1 total, in the window, rate per 1000 blocks (round 1 baseline: 8 in about 1,100 blocks = 7.3 per 1000, bootstrap included), block-time percentiles and maximum, gaps, round changes, forks, container deaths.
2. **F-1 per phase**: compare the rate per 1000 blocks across `idle`, `transfers`, `changes`, `heavy`, `changes-heavy`. A rate that is zero in `idle` and `transfers` but not in the `changes` phases means list changes trigger it; a similar rate everywhere means it is a property of the node under any consensus.
3. **"Where in the chain"**: for the occurrences inside the window, the share that fall on a block with a list change, within 3 blocks of one, in a block with transactions, in a round change, against the base rate of such blocks. Few occurrences prove nothing; with 20 or more the difference is meaningful.
4. **Each occurrence**: block N from the message, whether N is the first block of a new validator set, transactions in N-1/N/N+1, the proposer of N and N+1 (position in the sorted validator set) and whether the logging node is that proposer, the gap to the next block (**time-to-next-block**), the log time relative to block N, and whether a `PersistBlockTask` import line is within 50 ms of the error (the round 1 hypothesis).
   Raw context in `occurrences/`; CSV `occurrences-analysis.csv`.
5. **Harm**: "Longest gaps", "gaps >= 10 s", "round > 0 blocks" and the per-row table. In round 1 each occurrence cost one BFT message and no time. Harm would show as gaps >= 10 s or round changes at the same blocks as occurrences, or as repeated occurrences on the same node in a row. **Forks** must be 0 and container restarts 0.
6. **Per row table** (`per-hour.csv` = `hourly.csv`): look for trends: memory (`Mem MB`), block time drifting, run folder and volume growth.
7. **Other ERROR / WARN classes**: anything new beside the startup warnings is a finding of its own.

Things that make a row less comparable (the summary shows them, check them before concluding): the bootstrap period (excluded from the rate), a node that was down (`restarts`, `docker-events.jsonl`), validator count 6 or 8 by design (`Val.` column), the rows with `p` (partial, final).

If the occurrence count is high enough for statistics, send `runs/<id>.tar.gz`; `occurrences-analysis.csv` and `blocks.csv` allow further cuts (for example per proposer index).

## 7. Deviations from round 1 and limits (be aware of them)

- **D-1 Genesis validators.** Same as round 1: owner1/op1 Active at genesis, others joined by the real flow (`setOperator` in Probation plus Verifier `recordActivation`), scripted in the bootstrap. The alternative (all N Active from block 0 through a storage overlay) was not used: it needs a test-only overlay of the Registry's active-set arrays and would hide the activation path that round 1 saw F-1 around. A small cost: each run starts with a growth phase from 1 to N validators (about 1.5 to 2 minutes at 10 s per activation); it is reported as "bootstrap" and excluded from the rate.
- **D-2 Oracle overlay** (as round 1 D-2): `Registry.verifier`, `Distributor.distributionOracle`, `IdentityRegistry.identityOracle` storage slots hold throw-away test-key addresses; runtime bytecode is unchanged.
- **D-3 Contracts**: built from `contracts/` as of repo HEAD `16fe576` (working tree identical to HEAD at the build; includes the two-step operator change of `07d61fd` and the seat-transfer cleanup of `0bf7e75`). Sources are not modified; the list of source hashes is `nets/_build-summaries/contracts-sha256.txt`, the hashes of the compiled runtime code are in `nets/_build-summaries/*-build-summary.json`. The genesis contains the same ten contracts as round 1. If `contracts/` changes later, rebuild with `tools/build-genesis.js` (section 10).
- **D-4 Extra accounts and balances**: eight load accounts with 1,000,000,000 Suren each (a transfer costs 2.1 Suren at the 1e14 wei minimum gas price, so days of load need it); owners 1,000,000, Verifier and identity oracle 10,000,000.
- **D-5 Nodes**: JSON-RPC APIs ETH, NET, QBFT, ADMIN, WEB3, TXPOOL (no DEBUG/TRACE), `-Xmx768m` (round 1: 640m), memory limit 1.5 GB and 1.5 CPUs per node, Docker restart policy `on-failure:20`. `blockperiodseconds` 2, `requesttimeoutseconds` 10, `zeroBaseFee`, London genesis: as round 1.
- **D-6 Genesis timestamp** is the build time of the kit (2026-11-19), not the start time of your run. The Registry's own time fields (board term, probation start) refer to it. Besu starts normally with an old genesis timestamp (verified here with a 10-day-old header, see `verification/`). Nothing in the soak depends on the board term lasting: the owners the load generator suspends are not board members.
- **D-7 Verifier health check** in the swap is simulated (lag check of the new node plus a pause); the Verifier service itself is not part of the kit.
- **D-8 Images**: the long verification runs used `node:22` (Debian) for the load generator/collector; one short 4-validator run (2.4 minutes) was also made with the kit's default `node:22-alpine` and worked (`verification/alpine-default-image-smoke/`). Besu 26.9.0, 26.8.1 and `26.9-develop-260f602` were each run for a few minutes (see `verification/`); only 26.9.0 was run for 27 minutes.
- **D-9 One host.** All nodes share one machine, one kernel and one clock, and the network is a local bridge: no packet loss, latency or clock skew between nodes. A real multi-host network may behave differently. CPU contention on a small server can itself delay blocks: check `cpu_pct_max` and the block-time gaps against the CPU of the server.
- **D-10** The poller and the identity-flag calls add load that the real chain will also have (dashboards, oracles) but at an arbitrary rate.
- **Not covered**: network partitions, node crashes under load on purpose (the kit records crashes but does not cause them), chain growth beyond 72 h, Besu versions other than the ones you run.

## 8. Test keys

`TEST-KEYS-DO-NOT-REUSE.json` holds throw-away private keys generated for this kit (`tools/gen-keys.js`) and published in the repository on purpose. They exist only on local Docker dev chains
(chain id 725007 for the 7-validator net and 725004 for the 4-validator net). Never fund them on any real network and never reuse them for anything. The kit does not read or write any other secret.

## 9. Troubleshooting

- `ERROR: objects of an earlier run exist`: `./stop-soak.sh` if it is still running, copy the results, `./cleanup.sh`.
- Bootstrap fails (`runs/<id>/load/bootstrap.log`): usually the nodes could not peer (subnet clash, firewall rules on the docker bridge) or the server is too slow: check `docker logs sur25s-n1`.
- `cannot talk to the docker daemon`: add your user to the `docker` group (log out and in) or run the scripts with sudo.
- `status.txt is old`: the collector container is down; the runner restarts it. `docker logs sur25s-collector` shows why.
- A node keeps restarting: `docker logs sur25s-<node>`; out-of-memory kills show as `oom_total` in the rows (raise `--node-mem` and `--java-xmx`).
- To look at a node by hand: `curl -s -X POST -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"qbft_getValidatorsByBlockNumber","params":["latest"]}' http://127.0.0.1:19611`.

## 10. How the kit was built and checked

Rebuild the genesis files after a change of `contracts/` (on a PC with the repository; keys are kept, the genesis timestamp becomes the build time; the compiler Hardhat 2.29 / solc 0.8.24 comes from `contracts-tests/node_modules`, nothing is installed):

    export NODE_PATH=<repo>/contracts-tests/node_modules SOAK_BUILD=<scratch dir>
    for n in n7 n4; do SOAK_NET=$n node $NODE_PATH/hardhat/internal/cli/cli.js --config tools/hh/hardhat.config.js run tools/build-genesis.js; done


`tools/gen-keys.js` made the keys; `tools/build-genesis.js` (adapted from round 1's builder; uses the Hardhat in `contracts-tests/node_modules` as compiler and in-process EVM, "simulate-and-extract") made `nets/n7` and `nets/n4` from the real contracts;
`tools/make-vendor.sh` made the vendored ethers; `tools/test-parser.sh` replays round 1's logs through the collector's parser (it finds the 3 occurrences of n1 and 8 in all of Net-A); `tools/test-stale-genesis.sh` starts one node from a 10-day-old genesis header. The run on the build PC is documented in `verification/README.md`.
`MANIFEST.sha256` lists the hashes of every file of the kit (without `runs/`).
