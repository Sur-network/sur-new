// Hardhat project for the v2.5 contracts. Sources live in ../contracts (English contracts only;
// contracts-fa/ is checked for logical parity separately). Set SUR_FILES="A.sol,B.sol" to compile
// only some files (the other v2.2 files are migrated one by one and may not compile meanwhile).
require("@nomicfoundation/hardhat-toolbox");
const { subtask } = require("hardhat/config");
const { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } = require("hardhat/builtin-tasks/task-names");
const path = require("path");

subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(async (_, hre, runSuper) => {
  const all = await runSuper();
  const fs = require("fs");
  const mocks = fs.readdirSync(path.join(__dirname, "mocks")).filter((f) => f.endsWith(".sol")).map((f) => path.join(__dirname, "mocks", f));
  const only = process.env.SUR_FILES;
  if (!only) return all.concat(mocks);
  const wanted = only.split(",").map((s) => s.trim());
  return all.filter((p) => wanted.includes(path.basename(p))).concat(mocks);
});

module.exports = {
  solidity: { version: "0.8.24", settings: { optimizer: { enabled: true, runs: 200 }, evmVersion: "paris" } },
  // FoundationDAO is injected into the genesis alloc (no CREATE, so the 24576-byte limit does not apply on the real chain);
  // the tests deploy the seed helper, which does CREATE, so the limit is lifted for the in-process network only.
  networks: { hardhat: { allowUnlimitedContractSize: true } },
  paths: {
    root: path.resolve(__dirname, ".."),
    sources: path.resolve(__dirname, "../contracts"),
    tests: path.resolve(__dirname, "test"),
    cache: path.resolve(__dirname, "cache"),
    artifacts: path.resolve(__dirname, "artifacts"),
  },
};
