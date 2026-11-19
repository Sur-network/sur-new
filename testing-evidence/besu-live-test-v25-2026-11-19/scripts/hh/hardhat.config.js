// Hardhat project used ONLY as a compiler + temporary in-process EVM for the genesis builder
// (simulate-and-extract). Mirrors contracts-tests/hardhat.config.js (solc 0.8.24, optimizer 200, evmVersion paris,
// allowUnlimitedContractSize for the in-process network only).
// Sources: <repo>/contracts (read only). Build output goes to SUR25_BUILD (scratch dir); nothing is written into contracts/.
const path = require("path");
const repoRoot = path.resolve(__dirname, "../../../..");
const build = process.env.SUR25_BUILD || path.resolve(__dirname, "../../.build");
module.exports = {
  solidity: { version: "0.8.24", settings: { optimizer: { enabled: true, runs: 200 }, evmVersion: "paris", outputSelection: { "*": { "*": ["storageLayout"] } } } },
  networks: { hardhat: { allowUnlimitedContractSize: true, hardfork: "cancun", blockGasLimit: 60000000 } },
  paths: { root: repoRoot, sources: path.join(repoRoot, "contracts"), cache: path.join(build, "cache"), artifacts: path.join(build, "artifacts") },
};
