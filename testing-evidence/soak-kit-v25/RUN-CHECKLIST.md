# Run checklist (print this)

Kit: `soak-kit-v25`. Question: how often does Besu print `Failed validator smart contract call` (finding F-1), under what conditions, and does it ever slow or stop consensus?

## A. Before you start (once per server)

- [ ] Ubuntu 22.04 or 24.04, `docker version` works for your user (`docker ps` without sudo).
- [ ] RAM: 16 GB free for the 7-validator run (9 Besu nodes, about 0.6 to 1 GB each); 8 GB is enough for the 4-validator run (6 nodes).
- [ ] Disk: at least 20 GB free on the disk of the kit folder AND of `/var/lib/docker` for a 72 h run (see README for the measured numbers).
- [ ] Clock: `timedatectl` shows "System clock synchronized: yes" (block timestamps and log lines are compared with each other).
- [ ] The server will not reboot or auto-update Docker during the run (`sudo systemctl stop unattended-upgrades` if unsure). A reboot ends the run; results so far are kept.
- [ ] You pulled the images yourself (internet needed, once):
  - [ ] `docker pull hyperledger/besu:26.9.0`
  - [ ] `docker pull node:22-alpine`
  - [ ] (later, for the comparison runs) `docker pull hyperledger/besu:26.8.1` and `docker pull hyperledger/besu:develop`
- [ ] Ports 19611 to 19622 are free on localhost (the kit binds JSON-RPC to 127.0.0.1 only; nothing is reachable from the network).
- [ ] No other Docker network uses 172.29.71.0/24 (`docker network ls`; the script checks this too).

## B. Start

- [ ] Copy the kit: `rsync -a --exclude runs --exclude .state soak-kit-v25/ user@server:~/soak-kit-v25/` (or `scp -r`). Then `cd ~/soak-kit-v25` and, if the execute bits were lost, `chmod +x *.sh lib/*.sh tools/*.sh`. Optional integrity check: `sha256sum -c MANIFEST.sha256`.
- [ ] `./run-soak.sh 1 26.9.0 7 --interval-minutes 5 --tag smoke` as a 1 hour smoke test (optional, recommended the first time). Check `./status.sh`, wait for `RESULT-READY`, read `runs/*/summary.md`, then `./cleanup.sh --yes`.
- [ ] Start the real run inside tmux (survives a closed SSH session):
  `tmux new -s soak` then `./run-soak.sh 72 26.9.0 7` then detach with `Ctrl-b d`.
  The script prints what it will use and where results go; the SOAK CLOCK starts after the bootstrap (about 1.5 minutes).
- [ ] Write down: start time (UTC), Besu image id (printed in `runs/<id>/meta/run.json`), server model.

## C. During the run (any time)

- [ ] `./status.sh` : one screen. Look at: `last block age` (should be 0 to 3 s), `validators` (7, sometimes 6 or 8 by design), `restarts` (0), `F-1` counters.
- [ ] After the first row (60 min) open `runs/<id>/hourly.csv`: blocks per row ~1800, `bt_p50` 2, `fork_mismatches` 0, `containers_not_running` 0.
- [ ] If `status.sh` says "status.txt is old": the collector is dead. The runner restarts it by itself within 10 s and logs it in `runs/<id>/meta/supervisor-restarts.log`; if it keeps failing, copy `runs/<id>/collector/collector.log` aside.
- [ ] Do NOT run `docker system prune`, `docker stop` or `docker rm` on `sur25s-*` containers by hand during the run (use `./stop-soak.sh`).

## D. Stop

- [ ] Normal end: after the planned hours the runner stops by itself, stops the Besu containers, writes `summary.md` and the marker file `runs/<id>/RESULT-READY`.
- [ ] Early stop (any reason): `./stop-soak.sh` (writes the final row and the summary).
- [ ] The server crashed or rebooted: `./stop-soak.sh` also works then (it finishes the run from the files on disk).

## E. Bring the results back

- [ ] `./collect-results.sh runs/<id> --tar` (re-creates `summary.md` and makes `runs/<id>.tar.gz`).
- [ ] From your PC: `scp user@server:~/soak-kit-v25/runs/<id>.tar.gz .`
- [ ] Check the tar is complete (`tar -tzf <id>.tar.gz | tail`), then on the server: `./cleanup.sh` (removes only `sur25s-*` containers, volumes and the network; results in `runs/` stay) and, once the tar is safe, `./cleanup.sh --purge-runs`.
- [ ] `docker ps -a | grep sur25s` is empty afterwards.

## F. Comparison runs (one at a time, same server, same hours)

- [ ] 7 validators, Besu 26.9.0 (the baseline of round 1)
- [ ] 7 validators, Besu 26.8.1: `./run-soak.sh 24 26.8.1 7`
- [ ] 7 validators, develop: `./run-soak.sh 24 develop 7` (or the exact tag you pulled, e.g. `26.9-develop-260f602`)
- [ ] 4 validators, Besu 26.9.0: `./run-soak.sh 24 26.9.0 4`
- [ ] 7 validators, Besu 26.9.0, poller off: `./run-soak.sh 24 26.9.0 7 --poll-hz 0 --tag nopoll`
- [ ] Optional: only quiet blocks: `./run-soak.sh 24 26.9.0 7 --phase-plan "quiet:1440:0:0" --poll-hz 0 --entrant-frac 0 --tag quiet`

Always `./cleanup.sh --yes` between runs.
