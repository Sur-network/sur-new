// Hardhat project used ONLY as a compiler + temporary in-process EVM for the genesis builder (simulate-and-extract), as in
// testing-evidence/besu-live-test-v25-2026-11-19/scripts/hh. Sources: <repo>/contracts (read only). Build output goes to SOAK_BUILD
// (scratch dir); nothing is written into contracts/. NOT needed on the server (the generated files are in nets/).
const path = require("path");
const repoRoot = path.resolve(__dirname, "../../../..");
const build = process.env.SOAK_BUILD || path.resolve(__dirname, "../../.build");
module.exports = {
  solidity: { version: "0.8.24", settings: { optimizer: { enabled: true, runs: 200 }, evmVersion: "paris", outputSelection: { "*": { "*": ["storageLayout"] } } } },
  networks: { hardhat: { allowUnlimitedContractSize: true, hardfork: "cancun", blockGasLimit: 60000000 } },
  paths: { root: repoRoot, sources: path.join(repoRoot, "contracts"), cache: path.join(build, "cache"), artifacts: path.join(build, "artifacts") },
};
