# Evidence — first live Besu/QBFT run (2026-09-27/28)

Four reports produced by Claude Code, stored verbatim. NOT included (must be requested to make the run independently reproducible):
test scripts, genesis.json / config.toml, compiler input/output JSON, transaction receipts, raw node logs.

`BlockRewardDistributor.sol` used in that run was a **test-fork** (test parameters + the `_prepareEpoch` fix). The production fix
lives in `contracts/BlockRewardDistributor.sol` and `contracts-fa/BlockRewardDistributor.sol`.
