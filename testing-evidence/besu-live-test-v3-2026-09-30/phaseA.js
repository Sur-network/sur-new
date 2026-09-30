// Phase A: genesis verification on the REAL Besu network — everActivated(founder) from block
// zero, cross-checked via manual storage-slot computation (slot 20), plus isValidator(founder).
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "accounts.json"), "utf8"));

const RPC = "http://127.0.0.1:8651";
const REGISTRY = "0x3333333333333333333333333333333333333333";
const EVER_ACTIVATED_SLOT = 20n;

const ABI = [
  "function everActivated(address) view returns (bool)",
  "function isValidator(address) view returns (bool)",
  "function getValidators() view returns (address[])",
  "function windowStart() view returns (uint256)",
  "function verifier() view returns (address)",
];

function mappingSlot(key, baseSlot) {
  return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["address", "uint256"], [key, baseSlot]));
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const registry = new ethers.Contract(REGISTRY, ABI, provider);

  const block0 = await provider.getBlock(0);
  console.log("=== Genesis block ===");
  console.log("number:", block0.number, "hash:", block0.hash, "timestamp:", block0.timestamp);

  const founders = [accounts.founder1.address, accounts.founder2.address, accounts.founder3.address];
  console.log("\n=== Founder list (genesis-seeded) ===");
  founders.forEach((a, i) => console.log(`founder${i + 1}: ${a}`));

  const results = [];
  for (const addr of founders) {
    const everActivatedGetter = await registry.everActivated(addr, { blockTag: 0 });
    const isValidatorGetter = await registry.isValidator(addr, { blockTag: 0 });
    const slot = mappingSlot(addr, EVER_ACTIVATED_SLOT);
    const rawSlotValue = await provider.getStorage(REGISTRY, slot, 0);
    const slotBool = BigInt(rawSlotValue) === 1n;
    results.push({ addr, everActivatedGetter, isValidatorGetter, slot, rawSlotValue, slotBool });
    console.log(`\n${addr}:`);
    console.log(`  everActivated() getter @block0 = ${everActivatedGetter}`);
    console.log(`  isValidator() getter @block0   = ${isValidatorGetter}`);
    console.log(`  manual slot keccak256(addr,20) = ${slot}`);
    console.log(`  raw storage @block0             = ${rawSlotValue} (bool=${slotBool})`);
  }

  const getValidatorsResult = await registry.getValidators({ blockTag: 0 });
  console.log("\n=== getValidators() @block0 ===");
  console.log(getValidatorsResult);

  const windowStart = await registry.windowStart();
  const verifierOnChain = await registry.verifier();
  console.log("\nwindowStart():", windowStart.toString());
  console.log("verifier():", verifierOnChain);

  const allGood = results.every((r) => r.everActivatedGetter === true && r.isValidatorGetter === true && r.slotBool === true);
  console.log("\n=== PHASE A RESULT ===", allGood ? "ALL PASSED" : "FAILURE DETECTED");

  fs.writeFileSync(path.join(ROOT, "logs", "phaseA-result.json"), JSON.stringify({ block0, results, getValidatorsResult, windowStart: windowStart.toString(), verifierOnChain, allGood }, (k, v) => typeof v === "bigint" ? v.toString() : v, 2));
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
