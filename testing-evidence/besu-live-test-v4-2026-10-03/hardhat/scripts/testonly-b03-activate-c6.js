// B03 on Net-B: C6 requestMembership -> real 300s probation wait -> verifier recordActivation.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const RPC = "http://127.0.0.1:8701";
const REGISTRY = "0x3333333333333333333333333333333333333333";
const ABI = [
  "function requestMembership() external payable",
  "function currentEntryThreshold() view returns (uint256)",
  "function currentMembershipFee() view returns (uint256)",
  "function getValidatorInfo(address) view returns (uint8,uint256,uint256,uint256,uint256,bool)",
  "function recordActivation(address,bytes32) external returns (uint256)",
  "function isValidator(address) view returns (bool)",
  "function getValidators() view returns (address[])",
  "function getActiveValidatorCount() view returns (uint256)",
];
async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const c6 = new ethers.Wallet(accounts.g5_c6.privateKey, provider);
  const verifier = new ethers.Wallet(accounts.verifier.privateKey, provider);
  const registry = new ethers.Contract(REGISTRY, ABI, c6);

  const threshold = await registry.currentEntryThreshold();
  const fee = await registry.currentMembershipFee();
  const joinTx = await registry.requestMembership({ value: threshold + fee, gasLimit: 600000 });
  const joinRcpt = await joinTx.wait();
  console.log("C6 join tx:", joinRcpt.hash, "status:", joinRcpt.status);

  const info = await registry.getValidatorInfo(c6.address);
  const readyAt = Number(info[2]) + 300;
  const waitMs = Math.max(0, readyAt - Math.floor(Date.now() / 1000) + 3) * 1000;
  console.log(`Waiting ${waitMs}ms for probation...`);
  await new Promise((r) => setTimeout(r, waitMs));

  const regVerifier = new ethers.Contract(REGISTRY, ABI, verifier);
  const actTx = await regVerifier.recordActivation(c6.address, ethers.keccak256(ethers.toUtf8Bytes("b03-c6-activation")), { gasLimit: 600000 });
  const actRcpt = await actTx.wait();
  const result = {
    joinTxHash: joinRcpt.hash, joinStatus: joinRcpt.status,
    activateTxHash: actRcpt.hash, activateStatus: actRcpt.status, activatedInBlock: actRcpt.blockNumber,
    isValidatorAfter: await registry.isValidator(c6.address),
    activeCountAfter: (await registry.getActiveValidatorCount()).toString(),
    validatorsAfter: await registry.getValidators(),
  };
  console.log(JSON.stringify(result, null, 2));
  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-B-B03.json"), JSON.stringify(result, null, 2));
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
