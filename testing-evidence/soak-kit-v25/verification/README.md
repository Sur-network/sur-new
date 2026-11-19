# Verification of the soak kit on the build PC (2026-11-19)

Build PC: Windows 11, Docker Desktop (Linux engine, 29.7.2), 16 CPUs, 15.5 GB, Git Bash. Images already local: `hyperledger/besu:26.9.0`, `26.8.1`, `26.9-develop-260f602`, `node:22` (Debian; used for the long runs instead of the kit's default `node:22-alpine`, which was not local).

**Disclosure: an accidental pull.** The first run of `tools/test-parser.sh` happened before `--pull never` was added to the kit's `docker run` calls; Docker therefore tried to pull `node:22-alpine` (239 MB on disk). The command was stopped, but the Docker daemon finished the pull, so `node:22-alpine` is now present on this PC although nothing was meant to be downloaded. It was used for one short smoke run (below). Removing it was attempted and refused by the permission system, so it is still there (`docker rmi node:22-alpine` removes it). All `docker run` calls of the kit now have `--pull never`.
Everything the kit created was named `sur25s-*`; the other containers on the machine (`sur25b-*` of round 1b, which finished while this ran) were never touched. Data volumes and the network were removed after every run (`cleanup-evidence.txt` in each folder; `docker ps -a | grep sur25s` is empty).

**Genesis versions.** Runs 1 and 2 and the image/Alpine smoke runs used the genesis first built at 16:31 (local time) from `contracts/` at HEAD `07d61fd` plus its working tree. While they were running, the Registry changed (commit `0bf7e75`, 16:37: a seat transfer clears the seller's open node-key proposal). The genesis files in `nets/` were therefore rebuilt from the then-current `contracts/` (HEAD `16fe576`, Registry runtime-code hash in `nets/_build-summaries/`) and the 7-validator flow was run once more with them (run 3, the shipped genesis). The kit is not a snapshot of any later commit: `nets/_build-summaries/contracts-sha256.txt` says exactly what was used.

## Run 1: 7 validators, Besu 26.9.0, 27 minutes (`run1-n7-26.9.0-27min/`)

Command: `./run-soak.sh 0.45 26.9.0 7 --loadgen-image node:22 --interval-minutes 2 --phase-plan "idle:3:0:0,transfers:4:0.5:0,changes:6:0.5:2,heavy:4:5:0:2,changes-heavy:5:5:2:2" --entrant-frac 0.4 --tag verify`
(the default plan compressed from 210 to 22 minutes; rows every 2 minutes instead of hourly).

What it shows (all in `summary.md`, `hourly.csv`, `load/`, `runs` copies):

- Bootstrap: 1 to 7 validators through `setOperator` + `recordActivation`, 100 s (`load/bootstrap.log`); soak clock started 15:57:14Z.
- 845 blocks recorded (808 in the window), every block time 2 s except one 9 s block (see below); no fork at any of the 14 rows (same hashes at the same heights on all 9 nodes).
- Load generator: 3,359 transfers sent (1 error), 63 IdentityRegistry oracle calls, 5 bursts, getValidators poller 1,586 ok / 6 failed (while node n5 was down), list changes: 3 swaps, 2 selfSuspend, 2 recordResume, 1 recordActivation (the entrant: 7 became 8 validators); 8 validator-set changes seen in the blocks.
- Collector: 14 rows (13 full + 1 partial) in `hourly.csv` / `hourly.jsonl`, `status.txt`, `docker-events.jsonl`, `blocks.csv`, `valsets.jsonl`; `summary.md` written by the end-of-run step; 0 collector errors.
- **F-1 reproduced**: 10 occurrences on 7 of the 9 nodes (n1, n3 x2, n7 x3, x1 x2, x2 x2), 1 during the bootstrap and 9 in the window = 11.1 per 1000 window blocks (round 1: 7.3 per 1000). `occurrences/` holds the 15 + 1 + 45 lines of each (10 files); every one has a `PersistBlockTask` import line within 50 ms of the ERROR line; none was followed by a gap (next block always 2 s later), none in a round > 0.
  They were not spread evenly: none between block 31 and block 692, nine between block 693 and block 837 (all after the last `swap`, block 691, and after the two deliberate node kills below). This is one short run and is NOT a finding; it only shows what the summary's "blocks since last change" and "node restarted < 30 min" columns are for.

Deliberate fault injection during this run (so that the kit's crash handling could be seen; NOT part of a real soak):

- 16:05:00Z `docker kill sur25s-x2` (a manual kill is not restarted by Docker's restart policy): it stayed down until the author started it by hand at 16:05:46Z (the supervisor's own node restart did not exist yet in this run; it was added afterwards and tested in run 2). x2 logged an `InvalidBlockException` ERROR class on restart, visible in the "Other ERROR / WARN classes" table.
- 16:13:04Z `kill -9` of the Besu JVM in `sur25s-n5` (a real crash): Docker restarted the container at once (`restarts` = 1 from row 8 on, `die` exit 137 + `start` in `docker-events.jsonl`); n5 was the proposer of block 517, which came 9 s after its parent (the only gap > 2.5 s in the run); QBFT round stayed 0 (n5 was back before the round timer).
  These two events are the "Containers" table and the `Restarts` column of `summary.md`.

## Run 2: 4 validators, Besu 26.9.0, stopped early after 13 minutes (`run2-n4-26.9.0-13min-early-stop/`)

Command: `./run-soak.sh 0.35 26.9.0 4 --loadgen-image node:22 --interval-minutes 2 --phase-plan "idle:2:0:0,changes:4:0.5:1.5,heavy:3:5:0:2,changes-heavy:3:5:1.5:2" --entrant-frac 0.4 --tag verify4`, then `./stop-soak.sh` at 16:41:00Z.

- The 4-validator genesis works: bootstrap 1 to 4 validators in 50 s; list changes (2 swaps of owner3, selfSuspend/recordResume of owner4, entrant activation: 4 became 5 validators); 405 blocks recorded, all 2 s; no fork; 0 occurrences of F-1 in 383 window blocks (too short to say anything about the 4-validator rate).
- **Supervisor test**: `docker kill sur25s-x2` at 16:34:00Z; the runner started it again at 16:35:08Z ("SUPERVISOR: node sur25s-x2 has been down for 60 s", `meta/supervisor-restarts.log`); `docker-events.jsonl` shows kill, die, start, healthy.
- **Early stop**: `./stop-soak.sh` made the runner stop the load generator, let the collector write the final partial row (row 7) and the final fork check, stop the nodes and write `summary.md` and `RESULT-READY` (`injection-and-stop-soak.txt`).

## Run 3: shipped genesis (rebuilt), 7 validators, Besu 26.9.0, default image `node:22-alpine`, 13 minutes (`final-rebuilt-genesis-n7-13min/`)

Command: `./run-soak.sh 0.22 26.9.0 7 --interval-minutes 2 --phase-plan "idle:2:0:0,transfers:2:0.5:0,changes:4:0.5:1.5,heavy:2:5:0:1,changes-heavy:3:5:1.5:1" --entrant-frac 0.4 --tag final7` (no `--loadgen-image`, so the kit's default image was used; no fault injection).

- Bootstrap to 7 validators, 332 window blocks all 2 s, no fork, 0 restarts, 1,980 transfers (0 errors), poller 779 ok / 0 failed, 7 validator-set changes (2 swaps, 2 selfSuspend, 2 recordResume, 1 recordActivation: 7 became 8 validators), 6 rows + final summary, `cleanup-evidence.txt` clean.
- 1 occurrence of F-1 (n4, block 391, `changes-heavy`, 27 blocks after the last swap; PersistBlockTask line in the same ms; next block 2 s later).

## Other checks

- `parser-selftest-round1-logs.txt`: the collector's log parser (the real `runtime/collector.js` in self-test mode) replayed over all nine Net-A logs of round 1 finds exactly the 8 occurrences of F-1 documented there (n1 3, n2 1, n2b 2, n3b 1, n5 1, others 0) and writes the context files.
- `stale-genesis-test.txt`: one Besu node started from a copy of the 4-validator genesis whose header timestamp is 10 days old produces blocks normally (19 blocks in 45 s).
- `image-smoke-26.8.1/`, `image-smoke-26.9-develop-260f602/`: the 4-validator net for 1.8 minutes of window each on Besu 26.8.1 and on the develop build already on the PC (version lines inside): config files accepted, bootstrap to 4 validators, load and list changes (4 each), 56 window blocks each, all 2 s, no fork, 0 occurrences (too short to mean anything).
- `alpine-default-image-smoke/`: the same with the kit's default image `node:22-alpine` (no `--loadgen-image`): bootstrap, load, collector and analysis all worked (73 window blocks, 6 list changes, 263 transfers).
- `cleanup-evidence.txt` (both runs): containers, volumes and network of the kit removed; nothing with the prefix `sur25s` left.
- An earlier 9-minute smoke run (same net, same commands) found a syntax error in `analyze.js` (fixed; summary regenerated) and the generic container name of the bootstrap step (now named). Its output was not kept.
- The scripts were developed under Git Bash on Windows and run against Docker Desktop. They use only POSIX tools plus `docker` and were written to be the same on Ubuntu, but **they were not run on Ubuntu** (the Alpine image was run, but only on the build PC).

## What was NOT verified here

- A real 24 to 72 hour run: log rotation (100 MB threshold), the gzip step, the disk and RAM extrapolations (section 5 of the kit README) and the long-run behaviour of the collector are untested beyond 27 minutes. The rotation code path was not executed.
- Long runs on Besu 26.8.1 and the develop image (only a few minutes each; the configuration was accepted by both).
- Hourly rows with the default 60-minute interval (the 2-minute interval exercises the same code).
- The Docker restart policy `on-failure:20` after the 20th restart; the supervisor then starts a node that stays down after 60 s.
