// Net-D3 (fresh baseline G6 network, epochCount==0): generate the three non-reward inflows so the §D conservation equation has non-trivial F, M and X terms:
//   F  = ordinary transaction fees (several plain transfers; with zeroBaseFee the whole gas price goes to the coinbase = the distributor)
//   M  = one real membership fee: candidate C6 calls requestMembership (fee forwarded by the Registry via receiveMembershipFee). C6 is NEVER activated
//        and has no node, so QBFT quorum is unaffected.
//   X  = one plain value transfer into the distributor (receive()), i.e. an "other inflow"
const { ethers, ADDR, accounts, saveEvidence, sleep } = require("./v5-lib");
const URL = "http://127.0.0.1:8871";
const REG_ABI = ["function requestMembership() external payable", "function currentEntryThreshold() view returns (uint256)", "function currentMembershipFee() view returns (uint256)", "function getActiveValidatorCount() view returns (uint256)"];

async function main() {
  const provider = new ethers.JsonRpcProvider(URL);
  const oracle = new ethers.Wallet(accounts.distributionOracle.privateKey, provider);
  const verifier = new ethers.Wallet(accounts.verifier.privateKey, provider);
  const c6 = new ethers.Wallet(accounts.g5_c6.privateKey, provider);
  const reg = new ethers.Contract(ADDR.REGISTRY, REG_ABI, c6);
  const out = { startedAt: new Date().toISOString(), txs: [] };
  out.preconditions = { head: await provider.getBlockNumber(), activeValidators: Number(await reg.getActiveValidatorCount()), distributorBalance: (await provider.getBalance(ADDR.DISTRIBUTOR)).toString() };

  // F: ordinary fee-paying transfers from the oracle (default gas price from eth_gasPrice)
  for (let i = 0; i < 8; i++) {
    const t = await oracle.sendTransaction({ to: ethers.getAddress("0x" + ethers.keccak256(ethers.toUtf8Bytes(`d3-sink-${i}`)).slice(26)), value: 1n + BigInt(i), gasLimit: 21000 });
    const r = await t.wait();
    out.txs.push({ kind: "fee-transfer", hash: r.hash, block: r.blockNumber, gasUsed: r.gasUsed.toString(), effectiveGasPrice: r.gasPrice.toString() });
    await sleep(2500);
  }
  // M: membership request by the candidate
  const threshold = await reg.currentEntryThreshold(), fee = await reg.currentMembershipFee();
  out.membership = { threshold: threshold.toString(), fee: fee.toString() };
  const mt = await reg.requestMembership({ value: threshold + fee, gasLimit: 800000 });
  const mr = await mt.wait();
  out.txs.push({ kind: "requestMembership(C6)", hash: mr.hash, block: mr.blockNumber, status: mr.status, gasUsed: mr.gasUsed.toString(), effectiveGasPrice: mr.gasPrice.toString() });
  // X: plain inflow into the distributor from the verifier
  const xt = await verifier.sendTransaction({ to: ADDR.DISTRIBUTOR, value: ethers.parseEther("7"), gasLimit: 100000 });
  const xr = await xt.wait();
  out.txs.push({ kind: "plain-transfer-into-distributor", hash: xr.hash, block: xr.blockNumber, status: xr.status, valueWei: ethers.parseEther("7").toString(), gasUsed: xr.gasUsed.toString(), effectiveGasPrice: xr.gasPrice.toString() });
  out.postconditions = { head: await provider.getBlockNumber(), activeValidatorsStill: Number(await reg.getActiveValidatorCount()) };
  saveEvidence("Net-D3-activity.json", out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
