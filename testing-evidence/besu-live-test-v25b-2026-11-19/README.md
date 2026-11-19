# Besu live test, round 1b, v2.5 contracts after the owner decisions (2026-11-19)

Start with `REPORT.md` (note the section "which bytecode was tested"), then `FINDINGS.md`, `DEVIATIONS.md`, `LIMITATIONS.md`.

This round re-tests the three behaviour changes of commit `e1a5f1f` on a live Besu QBFT chain: (a) a seat transfer keeps an Active seat Active; (b) a board seat holder in Probation cannot act (`ValidatorsBoard._canAct`); (c) `clearStaleVotes` also covers SelfSuspended. The Registry also no longer gates resume or activation on seat acceptance.

Layout:
- `scripts/`: `gen-keys.js`, `build-genesis.js` (compiles `contracts/`, writes genesis and node dirs), `netctl.sh` (Docker control), `lib.js`, `env.sh`, `hh/hardhat.config.js`, and the tests `bh01.js`, `bh02.js`, `bh03.js`, `bh06a.js`, `bh06b.js`, `bh07b.js`, `bh14.js`.
- `nets/<Net>/`: `genesis.json`, node configs and keys (throw-away, also in `TEST-KEYS-DO-NOT-REUSE.json`).
- `evidence/00-baseline` (git HEAD `fa983bf`, contracts sha256), `01-environment/env.json`, `02-genesis/<net>/build-summary.json`, `03-commands/run-all.md`, `04-results/<ID>.json` (raw per-test evidence), `05-cleanup/docker-clean.txt`.
- `logs/<Net>/`: raw Besu logs; `logs/_scriptout/`: script stdout.
- `MANIFEST.sha256`: hashes of every file.

Reproduce: see `evidence/03-commands/run-all.md`. No image is pulled; the builder needs the cached solc 0.8.24. This is test evidence on a local Besu, not a statement of production readiness.
