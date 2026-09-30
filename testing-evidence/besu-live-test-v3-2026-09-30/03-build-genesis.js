// v3: assemble the full genesis.json from genesis-alloc.json + QBFT config.
// extraData = 0 validators (contract-validator mode reads the live set entirely from
// ValidatorsRegistry.getValidators(), seeded via genesis-alloc.json) — per the corrected format
// established in round 2 and restated as guidance in the v3 runbook §2.1.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "accounts.json"), "utf8"));
const alloc = JSON.parse(fs.readFileSync(path.join(ROOT, "genesis-alloc.json"), "utf8"));

const GENESIS_TIMESTAMP = 1790742970;

const extraData = ethers.encodeRlp([
  "0x" + "00".repeat(32), // vanity
  [], // validators — EMPTY in contract-validator mode
  [], // vote
  "0x", // round = 0
  [], // seals
]);

const finalAlloc = {};
for (const [addr, data] of Object.entries(alloc)) {
  finalAlloc[addr] = { code: data.code, storage: data.storage };
}

const BIG_BALANCE = "0x" + ethers.parseEther("2000000").toString(16); // founders — plenty for gas at min-gas-price
const VALIDATOR_JOIN_BALANCE = "0x" + ethers.parseEther("10000000").toString(16); // newValidator1 — must clear entryThresholdBase (500k+) plus gas
const ORACLE_BALANCE = "0x" + ethers.parseEther("50000").toString(16); // verifier / distributionOracle — gas only, several calls

for (const role of ["founder1", "founder2", "founder3"]) {
  finalAlloc[accounts[role].address.toLowerCase()] = { balance: BIG_BALANCE };
}
finalAlloc[accounts.newValidator1.address.toLowerCase()] = { balance: VALIDATOR_JOIN_BALANCE };
for (const role of ["verifier", "distributionOracle"]) {
  finalAlloc[accounts[role].address.toLowerCase()] = { balance: ORACLE_BALANCE };
}
// fakeAddress deliberately gets NO balance and NO history — it sends no transaction itself, it is
// only ever referenced as a payload address inside a distributeRewards() call (Phase D).

const genesis = {
  config: {
    chainId: 424244, // distinct from v1 (424242) and v2 (424243) — avoids any accidental cross-talk
    homesteadBlock: 0,
    eip150Block: 0,
    eip155Block: 0,
    eip158Block: 0,
    byzantiumBlock: 0,
    constantinopleBlock: 0,
    petersburgBlock: 0,
    istanbulBlock: 0,
    berlinBlock: 0,
    londonBlock: 0,
    zeroBaseFee: true,
    qbft: {
      blockperiodseconds: 3,
      epochlength: 30000,
      requesttimeoutseconds: 10,
      validatorcontractaddress: "0x3333333333333333333333333333333333333333",
      miningbeneficiary: "0x2222222222222222222222222222222222222222",
      blockreward: "2000000000000000000",
    },
  },
  gasLimit: "0x1fffffffffffff",
  difficulty: "0x1",
  timestamp: "0x" + GENESIS_TIMESTAMP.toString(16),
  extraData,
  alloc: finalAlloc,
};

const outPath = path.join(ROOT, "besu", "genesis.json");
fs.writeFileSync(outPath, JSON.stringify(genesis, null, 2));
console.log("Wrote", outPath);
console.log("extraData (0 validators):", extraData);
console.log("genesis timestamp:", GENESIS_TIMESTAMP, new Date(GENESIS_TIMESTAMP * 1000).toISOString());
console.log("chainId:", genesis.config.chainId);
