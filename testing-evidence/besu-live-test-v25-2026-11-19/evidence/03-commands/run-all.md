# How this campaign was run (commands, in order)

All commands are run from `testing-evidence/besu-live-test-v25-2026-11-19/` in Git Bash. `scripts/env.sh` sets `NODE_PATH` to
`contracts-tests/node_modules` (Hardhat 2.29.1, ethers 6.17.0; nothing is installed), `SUR25_BUILD` (compiler output, scratch dir) and defines `hh`.
The paths inside `env.sh` are those of the machine used; adjust them to reproduce.

```bash
source scripts/env.sh

# 0. keys (throw-away; the file in this folder was generated once and is not overwritten)
node scripts/gen-keys.js

# 1. genesis for each net: compile contracts/ (read only), simulate-and-extract, write nets/<net>/{genesis.json,nN/*} and evidence/02-genesis/<net>/build-summary.json
SUR25_NET=A  hh run scripts/build-genesis.js     # Net-A : 7 founders, blockreward 2 Suren           (BG-01..07, 09, 11, 12, 13, BG-08a)
SUR25_NET=S  hh run scripts/build-genesis.js     # Net-S : 1 founder,  blockreward 3 Suren           (BG-10, BG-10-BH, BG-08b)
SUR25_NET=L2 hh run scripts/build-genesis.js     # Net-L2: 1 founder,  blockreward 2 Suren           (BG-10b)
SUR25_NET=T  hh run scripts/build-genesis.js     # Net-T : 1 founder + overlay of 4 Registry time variables (BG-05b)

# 2. docker (image hyperledger/besu:26.9.0 already present, never pulled; every object is named sur25-*)
bash scripts/netctl.sh netcreate A ; bash scripts/netctl.sh start A n1
bash scripts/netctl.sh start A n2 n3 n4 n5 n6 n7            # followers, synced before activation

# 3. tests (each writes evidence/04-results/<ID>.json; stdout of the long ones is in logs/_scriptout/)
node scripts/bg01.js ; node scripts/bg02.js                  # BG-01, BG-02 + BG-12
node scripts/bg09.js ; node scripts/bg05.js ; node scripts/bg05neg.js ; node scripts/bg11.js
node scripts/bg03.js ; node scripts/bg04.js ; node scripts/bg06.js ; node scripts/bg07.js ; node scripts/bg07b.js
SUR25_BG08_NET=A node scripts/bg08.js                        # BG-08a (re-run in post-hoc mode with SUR25_BG08_TX=<tx>, see DEVIATIONS D-9)
node scripts/bg12b.js ; node scripts/bg13.js
# Net-S / Net-L2 / Net-T (started with netctl.sh netcreate/start S|L2|T n1 [nC]):
node scripts/bg10.js ; node scripts/bg10bh.js ; node scripts/bg10post.js ; SUR25_BG08_NET=S node scripts/bg08.js
node scripts/bg10b.js ; node scripts/bg05b.js
node scripts/br-size.js                                       # derived from BG-01/BG-02/BG-09 results

# 4. logs and cleanup
for n in A S L2 T; do bash scripts/netctl.sh destroy $n; done   # saves the raw logs to logs/Net-*/, removes containers, volumes and the network
docker ps -a ; docker volume ls ; docker network ls            # no sur25-* object remains
```
