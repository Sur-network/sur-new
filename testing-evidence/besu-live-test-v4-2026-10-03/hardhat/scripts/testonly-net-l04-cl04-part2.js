// C-L04 part 2 on Net-L04: after real recoveryPeriod for V5 and V4, recordRecovery both; then
// C-L04-2 (V5's vote on P2/T2/D2 rejected - wasn't Active at creation), C-L04-3 part2 (V4 votes
// once successfully, second attempt "already voted"), C-L04-5 (same pattern on T2/D2).
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const RPC = "http://127.0.0.1:8731";
const REGISTRY = "0x3333333333333333333333333333333333333333";
const TREASURY = "0x5555555555555555555555555555555555555555";
const DISTRIBUTOR = "0x2222222222222222222222222222222222222222";

const REG_ABI = [
  "function recordRecovery(address,bytes32) external returns (uint256)",
  "function getValidatorInfo(address) view returns (uint8,uint256,uint256,uint256,uint256,bool)",
  "function getActiveValidatorCount() view returns (uint256)",
  "function voteParameterChange(uint256) external",
];
const TREASURY_ABI = ["function voteCapChange(uint256) external"];
const DIST_ABI = ["function validatorVoteRateChange(uint256) external"];

async function waitForRecovery(provider, registry, addr, label) {
  const info = await registry.getValidatorInfo(addr);
  const readyAt = Number(info[3]) + 3700;
  const waitMs = Math.max(0, readyAt - Math.floor(Date.now() / 1000) + 3) * 1000;
  console.log(`[${label}] demotedAt=${info[3]} readyAt=${readyAt} waiting ${waitMs}ms...`);
  if (waitMs > 0) await new Promise((r) => setTimeout(r, waitMs));
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const verifier = new ethers.Wallet(accounts.verifier.privateKey, provider);
  const registry = new ethers.Contract(REGISTRY, REG_ABI, verifier);
  const out = {};

  await waitForRecovery(provider, registry, accounts.g5_v5.address, "V5");
  const recV5 = await (await registry.recordRecovery(accounts.g5_v5.address, ethers.keccak256(ethers.toUtf8Bytes("l04-recover-v5")), { gasLimit: 600000 })).wait();
  await waitForRecovery(provider, registry, accounts.g5_v4.address, "V4");
  const recV4 = await (await registry.recordRecovery(accounts.g5_v4.address, ethers.keccak256(ethers.toUtf8Bytes("l04-recover-v4")), { gasLimit: 600000 })).wait();
  out.recovery = { v5TxHash: recV5.hash, v5Status: recV5.status, v4TxHash: recV4.hash, v4Status: recV4.status, activeCountAfter: (await registry.getActiveValidatorCount()).toString() };
  console.log("=== Recovery ===", JSON.stringify(out.recovery));

  // C-L04-2: V5's vote on P2(id=2)/T2(id=2)/D2 rejected (wasn't Active at creation)
  const regV5 = new ethers.Contract(REGISTRY, REG_ABI, accounts.g5_v5.privateKey ? new ethers.Wallet(accounts.g5_v5.privateKey, provider) : null);
  out.cl04_2 = {};
  try { await regV5.voteParameterChange.staticCall(2); out.cl04_2.P2 = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl04_2.P2 = e.reason || e.message; }
  const trV5 = new ethers.Contract(TREASURY, TREASURY_ABI, new ethers.Wallet(accounts.g5_v5.privateKey, provider));
  try { await trV5.voteCapChange.staticCall(2); out.cl04_2.T2 = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl04_2.T2 = e.reason || e.message; }
  const distV5 = new ethers.Contract(DISTRIBUTOR, DIST_ABI, new ethers.Wallet(accounts.g5_v5.privateKey, provider));
  try { await distV5.validatorVoteRateChange.staticCall(2); out.cl04_2.D2 = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl04_2.D2 = e.reason || e.message; }
  console.log("=== C-L04-2 ===", JSON.stringify(out.cl04_2, null, 2));

  // C-L04-3 part2 + C-L04-5: V4 votes once successfully on P2, T2, D2; second attempt on each -> "already voted"
  const v4Wallet = new ethers.Wallet(accounts.g5_v4.privateKey, provider);
  out.cl04_3_5 = {};
  const regV4 = new ethers.Contract(REGISTRY, REG_ABI, v4Wallet);
  try {
    const tx = await regV4.voteParameterChange(2, { gasLimit: 400000 });
    const rcpt = await tx.wait();
    out.cl04_3_5.P2_firstVote = { status: rcpt.status };
  } catch (e) { out.cl04_3_5.P2_firstVote = { error: e.reason || e.message }; }
  try { await regV4.voteParameterChange.staticCall(2); out.cl04_3_5.P2_secondVote = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl04_3_5.P2_secondVote = e.reason || e.message; }

  const trV4 = new ethers.Contract(TREASURY, TREASURY_ABI, v4Wallet);
  try {
    const tx = await trV4.voteCapChange(2, { gasLimit: 400000 });
    const rcpt = await tx.wait();
    out.cl04_3_5.T2_firstVote = { status: rcpt.status };
  } catch (e) { out.cl04_3_5.T2_firstVote = { error: e.reason || e.message }; }
  try { await trV4.voteCapChange.staticCall(2); out.cl04_3_5.T2_secondVote = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl04_3_5.T2_secondVote = e.reason || e.message; }

  const distV4 = new ethers.Contract(DISTRIBUTOR, DIST_ABI, v4Wallet);
  try {
    const tx = await distV4.validatorVoteRateChange(2, { gasLimit: 400000 });
    const rcpt = await tx.wait();
    out.cl04_3_5.D2_firstVote = { status: rcpt.status };
  } catch (e) { out.cl04_3_5.D2_firstVote = { error: e.reason || e.message }; }
  try { await distV4.validatorVoteRateChange.staticCall(2); out.cl04_3_5.D2_secondVote = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl04_3_5.D2_secondVote = e.reason || e.message; }
  console.log("\n=== C-L04-3(part2) / C-L04-5 ===", JSON.stringify(out.cl04_3_5, null, 2));

  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-L04-CL04-part2.json"), JSON.stringify(out, null, 2));
  console.log("\nWrote evidence file.");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
