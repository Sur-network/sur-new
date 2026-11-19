# Besu live test, round 1, v2.5 contracts (2026-11-19)

Start with `REPORT.md` (result table), then `FINDINGS.md`, `DEVIATIONS.md`, `LIMITATIONS.md`.

Layout:
- `scripts/`: genesis builder, Docker control (`netctl.sh`), the test scripts (run order in `evidence/03-commands/run-all.md`), `hh/hardhat.config.js`.
- `nets/<Net>/`: `genesis.json` and node configs; node keys in `nets/*/nN/key` (throw-away test keys, also in `TEST-KEYS-DO-NOT-REUSE.json`).
- `evidence/00-baseline`: sha256 of the `contracts/` sources tested; `01-environment/env.json`; `02-genesis/<net>/build-summary.json` (hashes of compiled runtime code, oracle overrides); `04-results/<ID>.json` raw per-test evidence.
- `logs/<Net>/`: raw Besu node logs; `logs/_scriptout/`: script stdout.
- `MANIFEST.sha256`: hashes of every file (computed on LF working copies; may differ after a CRLF checkout).

Repo HEAD was `c10ff59` at the start of the run; `contracts/` was unchanged during it.

Reproduce: see `evidence/03-commands/run-all.md`. In short: `source scripts/env.sh`, build a genesis with `SUR25_NET=<A|S|L2|T> hh run scripts/build-genesis.js`, create and start the containers with `scripts/netctl.sh`, run the `bg*.js` scripts, then destroy the nets. No image is pulled; the builder needs the cached solc 0.8.24.

This is test evidence on a local Besu with test tooling, not a statement of production readiness.
