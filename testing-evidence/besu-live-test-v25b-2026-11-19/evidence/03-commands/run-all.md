# How round 1b was run (commands, in order)

All commands are run from `testing-evidence/besu-live-test-v25b-2026-11-19/` in Git Bash. `scripts/env.sh` sets `NODE_PATH` to
`contracts-tests/node_modules` (Hardhat 2.29.1, ethers 6.17.0; nothing is installed), `SUR25_BUILD` (compiler output, scratch dir) and defines `hh`.
The paths inside `env.sh` are those of the machine used; adjust them to reproduce. Image `hyperledger/besu:26.9.0` is already local and is never pulled.
Every Docker object is named `sur25b-*`. Chain ids 425035 (Net-A) and 425038 (Net-T); RPC only on 127.0.0.1 (19511.. and 19611..).

```bash
source scripts/env.sh

# 0. keys (throw-away; the file in this folder was generated once and is not overwritten)
node scripts/gen-keys.js

# 1. genesis from the CURRENT contracts/ (compiled by the builder): nets/<net>/{genesis.json,nN/*}, evidence/02-genesis/<net>/build-summary.json
SUR25_NET=A hh run scripts/build-genesis.js     # Net-A: 7 founders, block reward 2 Suren (BH-01, 02, 03, 06A, 14, 07b)
SUR25_NET=T hh run scripts/build-genesis.js     # Net-T: 1 founder + TEST-ONLY overlay of 4 Registry time variables (BH-06B)

# 2. Net-A: docker + tests (each writes evidence/04-results/<ID>.json; stdout in logs/_scriptout/)
bash scripts/netctl.sh netcreate A ; bash scripts/netctl.sh start A n1
bash scripts/netctl.sh start A n2 n3 n4 n5 n6 n7          # followers, synced before the first activation
node scripts/bh01.js                                       # BH-01 genesis, board authority at genesis
node scripts/bh02.js                                       # BH-02 founders join (n=1,2,3,4,7), board rule, 3-of-5 board action
node scripts/bh03.js                                       # BH-03 setOperator swap (starts n2b itself)
node scripts/bh06a.js                                      # BH-06A Active seat transfer (founder seat 6 -> buyer)
node scripts/bh14.js                                       # BH-14 selfSuspend + clearStaleVotes
node scripts/bh07b.js                                      # BH-07b recovery removal with board votes (stops n7 itself)
bash scripts/netctl.sh destroy A                           # saves logs/Net-A/*.log, removes containers, volumes and the network

# 3. Net-T
bash scripts/netctl.sh netcreate T ; bash scripts/netctl.sh start T n1
node scripts/bh06b.js                                      # BH-06B paid-entrant seat: Probation sale, activation without acceptance, Active sale with collateral, exit
bash scripts/netctl.sh destroy T

# 4. confirm clean
docker ps -a ; docker volume ls ; docker network ls        # no sur25b-* object remains

# 5. manifest
find . -type f ! -name MANIFEST.sha256 | sort | xargs sha256sum > MANIFEST.sha256
```
