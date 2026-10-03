// Net-F6 combined test, activity phase (corrected version; the first attempt skipped the M and X transactions because it only sent on every other block).
// NON-EMPTY blocks around the reward transition X=100 (3 SUR from block 100):
//   * an ordinary fee-paying transfer EVERY block, blocks ~92..110 (fees F)
//   * one real membership fee (candidate C6, never activated, no node) sent so that it lands in block 99/100        (M)
//   * one direct extra inflow into the distributor (plain transfer to receive()) sent so that it lands in block 100 (X)
// Transactions are sent right after a new block appears and are NOT awaited one by one, so every block gets one.
const { ethers, ADDR, accounts, sleep, saveEvidence } = require("./v5-lib");
const URL = "http://127.0.0.1:8911";
const REG_ABI = ["function requestMembership() external payable", "function currentEntryThreshold() view returns (uint256)", "function currentMembershipFee() view returns (uint256)", "function getActiveValidatorCount() view returns (uint256)"];

async function main() {
  const provider = new ethers.JsonRpcProvider(URL);
  const oracle = new ethers.Wallet(accounts.distributionOracle.privateKey, provider);
  const verifier = new ethers.Wallet(accounts.verifier.privateKey, provider);
  const c6 = new ethers.Wallet(accounts.g5_c6.privateKey, provider);
  const reg = new ethers.Contract(ADDR.REGISTRY, REG_ABI, c6);
  const out = { startedAt: new Date().toISOString(), plan: "fee transfer each block 92..110; membership sent after block 98 (lands ~99); plain inflow sent after block 99 (lands in 100)", txs: [] };
  const FIRST = 92, LAST = 110;
  for (;;) { if ((await provider.getBlockNumber()) >= FIRST - 1) break; await sleep(500); }
  out.preconditions = { head: await provider.getBlockNumber(), activeValidators: Number(await reg.getActiveValidatorCount()), distributorBalance: (await provider.getBalance(ADDR.DISTRIBUTOR)).toString() };
  const threshold = await reg.currentEntryThreshold(), fee = await reg.currentMembershipFee();
  out.membership = { threshold: threshold.toString(), fee: fee.toString() };
  const pending = [];
  let seen = await provider.getBlockNumber(), i = 0;
  const track = (kind, sentAfter, promise) => pending.push(promise.then(async (t) => { const r = await t.wait(); out.txs.push({ kind, sentAfterBlock: sentAfter, minedInBlock: r.blockNumber, hash: r.hash, status: r.status, gasUsed: r.gasUsed.toString(), effectiveGasPrice: r.gasPrice.toString() }); console.log(kind, "sent after", sentAfter, "mined in", r.blockNumber); }));
  let oracleNonce = await oracle.getNonce("pending");
  while (seen < LAST) {
    for (;;) { const h = await provider.getBlockNumber(); if (h > seen) { seen = h; break; } await sleep(200); }
    track("fee-transfer", seen, oracle.sendTransaction({ to: ethers.getAddress("0x" + ethers.keccak256(ethers.toUtf8Bytes(`f6-sink-${i}`)).slice(26)), value: 1n + BigInt(i), gasLimit: 21000, nonce: oracleNonce++ }));
    if (seen === 98) track("requestMembership(C6)", seen, reg.requestMembership({ value: threshold + fee, gasLimit: 800000 }));
    if (seen === 99) track("plain-transfer-into-distributor", seen, verifier.sendTransaction({ to: ADDR.DISTRIBUTOR, value: ethers.parseEther("7"), gasLimit: 100000 }));
    i++;
  }
  await Promise.all(pending);
  while ((await provider.getBlockNumber()) < 113) await sleep(500);
  out.blocksNonEmpty = [];
  for (let n = 90; n <= 112; n++) { const b = await provider.send("eth_getBlockByNumber", ["0x" + n.toString(16), false]); out.blocksNonEmpty.push({ n, txs: b ? b.transactions.length : null }); }
  out.postconditions = { head: await provider.getBlockNumber(), activeValidatorsStill: Number(await reg.getActiveValidatorCount()) };
  out.kindsMined = out.txs.reduce((m, t) => { m[t.kind] = (m[t.kind] || 0) + 1; return m; }, {});
  saveEvidence("Net-F6-activity.json", out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
