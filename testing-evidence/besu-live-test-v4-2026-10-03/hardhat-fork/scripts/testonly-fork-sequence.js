// Net-Fork (TEST-FORK, compressed MIN_DISTRIBUTION_INTERVAL=90s): corrected D01 edge cases
// (duplicate/zero/never-activated address, with correct block-count accounting) BEFORE the first
// distribution, then D02'-equivalent, wait compressed interval, D04'-equivalent, wait again,
// D05'-equivalent (backlog settle of 2 skipped windows in one call).
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const RPC = "http://127.0.0.1:8791";
const DISTRIBUTOR = "0x2222222222222222222222222222222222222222";
const FOUNDATION = "0x1111111111111111111111111111111111111111";
const TREASURY = "0x5555555555555555555555555555555555555555";

const DIST_ABI = [
  "function distributeRewards((uint256 fromBlock,uint256 toBlock) range, address[] validators, uint256[] blocksMined, uint256 totalRewards, uint256 totalFees) external",
  "function lastSettledBlock() view returns (uint256)",
  "function epochCount() view returns (uint256)",
  "function lastDistributionTime() view returns (uint256)",
  "function MIN_DISTRIBUTION_INTERVAL() view returns (uint256)",
  "function maxRewardsForRange(uint256,uint256) view returns (uint256)",
  "function FOUNDATION_SHARE_BPS() view returns (uint256)",
  "function validatorDirectShareBps() view returns (uint256)",
];

async function countBlocksByMiner(provider, fromBlock, toBlock, addresses) {
  const counts = Object.fromEntries(addresses.map((a) => [a.toLowerCase(), 0]));
  for (let i = fromBlock; i <= toBlock; i++) {
    const blk = await provider.getBlock(i);
    const m = blk.miner.toLowerCase();
    if (m in counts) counts[m]++;
  }
  return counts;
}

async function tryStatic(label, distributor, args) {
  try {
    await distributor.distributeRewards.staticCall(...args);
    return { label, result: "UNEXPECTED_SUCCESS" };
  } catch (err) {
    return { label, revertReason: err.reason || err.shortMessage || err.message };
  }
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const oracleWallet = new ethers.Wallet(accounts.distributionOracle.privateKey, provider);
  const distributor = new ethers.Contract(DISTRIBUTOR, DIST_ABI, oracleWallet);
  const founders = [1, 2, 3, 4, 5].map((i) => accounts[`g5_v${i}`].address);
  const sortedFounders = [...founders].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
  console.log("sorted founders:", sortedFounders);

  const results = {};

  // --- Corrected D01 edge cases, pre-first-distribution ---
  const currentBlock0 = await provider.getBlockNumber();
  const fromBlock0 = 1, toBlock0 = currentBlock0 - 1;
  const counts0 = await countBlocksByMiner(provider, fromBlock0, toBlock0, sortedFounders);
  const blocksMined0 = sortedFounders.map((a) => counts0[a.toLowerCase()]);
  console.log("pre-dist range", fromBlock0, toBlock0, "blocksMined0", blocksMined0);

  const dupVals = [sortedFounders[0], sortedFounders[0], ...sortedFounders.slice(1)];
  const dupBm = [blocksMined0[0], 0, ...blocksMined0.slice(1)];
  results.duplicate_address = await tryStatic("duplicate_address", distributor, [{ fromBlock: fromBlock0, toBlock: toBlock0 }, dupVals, dupBm, 1n, 0n]);

  const zeroVals = [ethers.ZeroAddress, ...sortedFounders];
  const zeroBm = [1, ...blocksMined0.slice(0, blocksMined0.length - 1), Math.max(0, blocksMined0[blocksMined0.length - 1] - 1)];
  results.zero_address = await tryStatic("zero_address", distributor, [{ fromBlock: fromBlock0, toBlock: toBlock0 }, zeroVals, zeroBm, 1n, 0n]);

  const withFake = [...sortedFounders, accounts.fakeAddress.address].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
  const lastRealIdx = sortedFounders.indexOf(sortedFounders[sortedFounders.length - 1]);
  const fakeBm = withFake.map((a) => (a === accounts.fakeAddress.address ? 1 : blocksMined0[sortedFounders.indexOf(a)]));
  const posOfLastReal = withFake.indexOf(sortedFounders[sortedFounders.length - 1]);
  fakeBm[posOfLastReal] = Math.max(0, fakeBm[posOfLastReal] - 1);
  results.never_activated_address = await tryStatic("never_activated_address", distributor, [{ fromBlock: fromBlock0, toBlock: toBlock0 }, withFake, fakeBm, 1n, 0n]);

  console.log("\n=== corrected D01 edge cases ===");
  console.log(JSON.stringify(results, null, 2));

  // --- D02'-equivalent: first real distribution ---
  const maxRewards0 = await distributor.maxRewardsForRange(fromBlock0, toBlock0);
  const balBefore0 = {};
  for (const a of [...sortedFounders, FOUNDATION, TREASURY]) balBefore0[a] = await provider.getBalance(a);
  const tx0 = await distributor.distributeRewards({ fromBlock: fromBlock0, toBlock: toBlock0 }, sortedFounders, blocksMined0, maxRewards0, 0n, { gasLimit: 5_000_000 });
  const rcpt0 = await tx0.wait();
  const balAfter0 = {};
  for (const a of [...sortedFounders, FOUNDATION, TREASURY]) balAfter0[a] = await provider.getBalance(a);
  const d02prime = { txHash: rcpt0.hash, status: rcpt0.status, gasUsed: rcpt0.gasUsed.toString(), fromBlock: fromBlock0, toBlock: toBlock0, totalRewards: maxRewards0.toString(), deltas: Object.fromEntries([...sortedFounders, FOUNDATION, TREASURY].map((a) => [a, (balAfter0[a] - balBefore0[a]).toString()])) };
  console.log("\n=== D02' (fork) ===", JSON.stringify(d02prime, null, 2));

  // --- wait compressed MIN_DISTRIBUTION_INTERVAL (90s) ---
  const minInterval = await distributor.MIN_DISTRIBUTION_INTERVAL();
  console.log(`\nWaiting ${minInterval}s for MIN_DISTRIBUTION_INTERVAL...`);
  await new Promise((r) => setTimeout(r, (Number(minInterval) + 5) * 1000));

  // --- D04'-equivalent: second consecutive distribution ---
  const lastSettled1 = await distributor.lastSettledBlock();
  const currentBlock1 = await provider.getBlockNumber();
  const fromBlock1 = Number(lastSettled1) + 1, toBlock1 = currentBlock1 - 1;
  const counts1 = await countBlocksByMiner(provider, fromBlock1, toBlock1, sortedFounders);
  const blocksMined1 = sortedFounders.map((a) => counts1[a.toLowerCase()]);
  const maxRewards1 = await distributor.maxRewardsForRange(fromBlock1, toBlock1);
  const balBefore1 = {};
  for (const a of [...sortedFounders, FOUNDATION, TREASURY]) balBefore1[a] = await provider.getBalance(a);
  const tx1 = await distributor.distributeRewards({ fromBlock: fromBlock1, toBlock: toBlock1 }, sortedFounders, blocksMined1, maxRewards1, 0n, { gasLimit: 5_000_000 });
  const rcpt1 = await tx1.wait();
  const balAfter1 = {};
  for (const a of [...sortedFounders, FOUNDATION, TREASURY]) balAfter1[a] = await provider.getBalance(a);
  const d04prime = { txHash: rcpt1.hash, status: rcpt1.status, gasUsed: rcpt1.gasUsed.toString(), fromBlock: fromBlock1, toBlock: toBlock1, totalRewards: maxRewards1.toString(), deltas: Object.fromEntries([...sortedFounders, FOUNDATION, TREASURY].map((a) => [a, (balAfter1[a] - balBefore1[a]).toString()])), noGapFromPrevious: fromBlock1 === toBlock0 + 1 };
  console.log("\n=== D04' (fork) ===", JSON.stringify(d04prime, null, 2));

  // --- wait again, then skip ONE window deliberately, then settle a backlog spanning >=2 windows (D05'-equivalent) ---
  console.log(`\nWaiting ${Number(minInterval) * 2 + 10}s (skip one window, then settle backlog)...`);
  await new Promise((r) => setTimeout(r, (Number(minInterval) * 2 + 10) * 1000));

  const lastSettled2 = await distributor.lastSettledBlock();
  const currentBlock2 = await provider.getBlockNumber();
  const fromBlock2 = Number(lastSettled2) + 1, toBlock2 = currentBlock2 - 1;
  const counts2 = await countBlocksByMiner(provider, fromBlock2, toBlock2, sortedFounders);
  const blocksMined2 = sortedFounders.map((a) => counts2[a.toLowerCase()]);
  const maxRewards2 = await distributor.maxRewardsForRange(fromBlock2, toBlock2);
  const balBefore2 = {};
  for (const a of [...sortedFounders, FOUNDATION, TREASURY]) balBefore2[a] = await provider.getBalance(a);
  const tx2 = await distributor.distributeRewards({ fromBlock: fromBlock2, toBlock: toBlock2 }, sortedFounders, blocksMined2, maxRewards2, 0n, { gasLimit: 5_000_000 });
  const rcpt2 = await tx2.wait();
  const balAfter2 = {};
  for (const a of [...sortedFounders, FOUNDATION, TREASURY]) balAfter2[a] = await provider.getBalance(a);
  const d05prime = { txHash: rcpt2.hash, status: rcpt2.status, gasUsed: rcpt2.gasUsed.toString(), fromBlock: fromBlock2, toBlock: toBlock2, rangeSizeBlocks: toBlock2 - fromBlock2 + 1, totalRewards: maxRewards2.toString(), deltas: Object.fromEntries([...sortedFounders, FOUNDATION, TREASURY].map((a) => [a, (balAfter2[a] - balBefore2[a]).toString()])), blocksMinedSum: blocksMined2.reduce((a, b) => a + b, 0) };
  console.log("\n=== D05' (fork, backlog settle) ===", JSON.stringify(d05prime, null, 2));

  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-Fork-D01-D02-D04-D05.json"), JSON.stringify({ correctedD01: results, d02prime, d04prime, d05prime }, null, 2));
  console.log("\nWrote evidence file.");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
