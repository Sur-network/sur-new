// B02: verifier suspends V5 (g5_v5) via recordSuspension on Net-B.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const RPC = "http://127.0.0.1:8701";
const REGISTRY = "0x3333333333333333333333333333333333333333";
const ABI = [
  "function recordSuspension(address,bytes32) external returns (uint256)",
  "function isValidator(address) view returns (bool)",
  "function getValidators() view returns (address[])",
  "function getActiveValidatorCount() view returns (uint256)",
];
async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const verifier = new ethers.Wallet(accounts.verifier.privateKey, provider);
  const registry = new ethers.Contract(REGISTRY, ABI, verifier);
  const v5 = accounts.g5_v5.address;
  const blockBefore = await provider.getBlockNumber();
  const countBefore = await registry.getActiveValidatorCount();
  const submittedAt = new Date().toISOString();
  const evidence = ethers.keccak256(ethers.toUtf8Bytes("B02-suspend-v5"));
  const tx = await registry.recordSuspension(v5, evidence, { gasLimit: 600000 });
  const receipt = await tx.wait();
  const countAfter = await registry.getActiveValidatorCount();
  const validatorsAfter = await registry.getValidators();
  const result = {
    scenario: "B02", submittedAt, txHash: receipt.hash, status: receipt.status, gasUsed: receipt.gasUsed.toString(),
    minedInBlock: receipt.blockNumber, blockBefore, countBefore: countBefore.toString(), countAfter: countAfter.toString(),
    isValidatorAfter: await registry.isValidator(v5), validatorsAfter,
  };
  console.log(JSON.stringify(result, null, 2));
  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-B-B02.json"), JSON.stringify(result, null, 2));
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
