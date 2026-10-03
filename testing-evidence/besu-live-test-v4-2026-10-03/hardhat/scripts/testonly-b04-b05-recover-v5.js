// B04: after real recoveryPeriod (3700s) since B02's suspension, verifier recordRecovery(V5) -> 5->6.
// B05: precondition getActiveValidatorCount()==6; two pre-signed recordSuspension txs (V4,V5) sent
// back-to-back (<100ms apart); check same-block landing; full recordRecovery of both after another
// recoveryPeriod wait; repeat up to 3 attempts total.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const RPC = "http://127.0.0.1:8701";
const REGISTRY = "0x3333333333333333333333333333333333333333";
const ABI = [
  "function recordSuspension(address,bytes32) external returns (uint256)",
  "function recordRecovery(address,bytes32) external returns (uint256)",
  "function getActiveValidatorCount() view returns (uint256)",
  "function getValidatorInfo(address) view returns (uint8,uint256,uint256,uint256,uint256,bool)",
  "function getValidators() view returns (address[])",
];

async function waitForRecovery(provider, registry, addr, label) {
  const info = await registry.getValidatorInfo(addr);
  const readyAt = Number(info[3]) + 3700; // demotedAt + recoveryPeriod
  const waitMs = Math.max(0, readyAt - Math.floor(Date.now() / 1000) + 3) * 1000;
  console.log(`[${label}] demotedAt=${info[3]} readyAt=${readyAt} waiting ${waitMs}ms...`);
  if (waitMs > 0) await new Promise((r) => setTimeout(r, waitMs));
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const verifier = new ethers.Wallet(accounts.verifier.privateKey, provider);
  const registry = new ethers.Contract(REGISTRY, ABI, verifier);
  const out = {};

  // === B04: recover V5 ===
  await waitForRecovery(provider, registry, accounts.g5_v5.address, "B04-V5");
  const countBefore04 = await registry.getActiveValidatorCount();
  const recTx = await registry.recordRecovery(accounts.g5_v5.address, ethers.keccak256(ethers.toUtf8Bytes("b04-recover-v5")), { gasLimit: 600000 });
  const recRcpt = await recTx.wait();
  const countAfter04 = await registry.getActiveValidatorCount();
  out.b04 = { txHash: recRcpt.hash, status: recRcpt.status, minedInBlock: recRcpt.blockNumber, countBefore: countBefore04.toString(), countAfter: countAfter04.toString() };
  console.log("=== B04 ===", JSON.stringify(out.b04));

  // === B05 ===
  // TIME-BUDGET NOTE: the document allows up to 3 attempts, each requiring a FULL recoveryPeriod
  // (3700s) wait for BOTH suspended validators before the next attempt can be tried (precondition:
  // getActiveValidatorCount()==6). That is up to ~3 x 2 x 3700s = ~6.2 hours in the worst case --
  // far beyond this session's ~5-6 hour budget. Per owner instruction, this round makes exactly
  // ONE attempt, reports its real outcome (same-block or not), and does NOT spend a further ~2
  // hours recovering afterward -- the post-attempt active-validator count is reported honestly as
  // the network's actual final state, not silently restored to look complete.
  const activeCount = await registry.getActiveValidatorCount();
  out.b05 = { precondition_activeCount: activeCount.toString(), note: "Only 1 of the document's allowed 3 attempts was made, and the full post-attempt recovery wait (~2h for both validators) was deliberately skipped, given the session's time budget. See DEVIATIONS.md." };
  if (Number(activeCount) !== 6) {
    out.b05.result = "BLOCKED - precondition getActiveValidatorCount()==6 not met";
    console.log("B05 BLOCKED:", out.b05.result);
  } else {
    const nonceBase = await provider.getTransactionCount(verifier.address, "pending");
    const txV4 = await registry.recordSuspension.populateTransaction(accounts.g5_v4.address, ethers.keccak256(ethers.toUtf8Bytes("b05-a1-v4")));
    const txV5 = await registry.recordSuspension.populateTransaction(accounts.g5_v5.address, ethers.keccak256(ethers.toUtf8Bytes("b05-a1-v5")));
    const signedV4 = await verifier.signTransaction({ ...txV4, nonce: nonceBase, gasLimit: 600000, gasPrice: 100000000000000n, chainId: (await provider.getNetwork()).chainId, type: 0 });
    const signedV5 = await verifier.signTransaction({ ...txV5, nonce: nonceBase + 1, gasLimit: 600000, gasPrice: 100000000000000n, chainId: (await provider.getNetwork()).chainId, type: 0 });
    const t0 = Date.now();
    const [respV4, respV5] = await Promise.all([provider.broadcastTransaction(signedV4), provider.broadcastTransaction(signedV5)]);
    const t1 = Date.now();
    const [rcptV4, rcptV5] = await Promise.all([respV4.wait(), respV5.wait()]);
    const sameBlock = rcptV4.blockNumber === rcptV5.blockNumber;
    const countAfterAttempt = await registry.getActiveValidatorCount();
    out.b05.attempt1 = { sendGapMs: t1 - t0, blockV4: rcptV4.blockNumber, blockV5: rcptV5.blockNumber, sameBlock, statusV4: rcptV4.status, statusV5: rcptV5.status, countAfter: countAfterAttempt.toString(), neverDroppedBelow4: Number(countAfterAttempt) >= 4 };
    console.log("B05 attempt 1 result:", JSON.stringify(out.b05.attempt1));
  }

  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-B-B04-B05.json"), JSON.stringify(out, null, 2));
  console.log("\nWrote evidence file.");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
