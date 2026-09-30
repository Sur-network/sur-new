// Phase D (reject a fake address) tried FIRST — a revert leaves lastSettledBlock/epochCount
// unchanged, so it can safely precede Phase C's real, successful call for the same range.
// Phase C: the second (real) distributeRewards() call, covering the range since Phase B, with
// founder3 STILL included even though it exited mid-range (requestExit() in phaseC-exit.js) —
// must succeed and pay founder3 its full proportional share for the blocks it mined before exit.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "accounts.json"), "utf8"));
const RPC = "http://127.0.0.1:8651";
const DISTRIBUTOR = "0x2222222222222222222222222222222222222222";
const FOUNDATION = "0x1111111111111111111111111111111111111111";
const TREASURY = "0x5555555555555555555555555555555555555555";

const DIST_ABI = [
  "function distributeRewards((uint256 fromBlock,uint256 toBlock) range, address[] validators, uint256[] blocksMined, uint256 totalRewards, uint256 totalFees) external",
  "function lastSettledBlock() view returns (uint256)",
  "function epochCount() view returns (uint256)",
  "function lastDistributionTime() view returns (uint256)",
  "function MIN_DISTRIBUTION_INTERVAL() view returns (uint256)",
  "function FOUNDATION_SHARE_BPS() view returns (uint256)",
  "function validatorDirectShareBps() view returns (uint256)",
];

async function countBlocksByMiner(provider, fromBlock, toBlock, addresses) {
  const counts = Object.fromEntries(addresses.map((a) => [a.toLowerCase(), 0]));
  let unaccounted = 0;
  for (let i = fromBlock; i <= toBlock; i++) {
    const blk = await provider.getBlock(i);
    const miner = blk.miner.toLowerCase();
    if (miner in counts) counts[miner]++;
    else unaccounted++;
  }
  return { counts, unaccounted };
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const oracleWallet = new ethers.Wallet(accounts.distributionOracle.privateKey, provider);
  const distributor = new ethers.Contract(DISTRIBUTOR, DIST_ABI, oracleWallet);

  const founders = [accounts.founder1.address, accounts.founder2.address, accounts.founder3.address];

  const lastSettled = await distributor.lastSettledBlock();
  const lastDistTime = await distributor.lastDistributionTime();
  const minInterval = await distributor.MIN_DISTRIBUTION_INTERVAL();
  console.log("lastSettledBlock:", lastSettled.toString(), "lastDistributionTime:", lastDistTime.toString(), "MIN_DISTRIBUTION_INTERVAL:", minInterval.toString());

  const nowSec = Math.floor(Date.now() / 1000);
  const readyAt = Number(lastDistTime) + Number(minInterval);
  if (nowSec < readyAt) {
    const waitMs = (readyAt - nowSec + 2) * 1000;
    console.log(`Waiting ${waitMs}ms for MIN_DISTRIBUTION_INTERVAL to elapse...`);
    await new Promise((r) => setTimeout(r, waitMs));
  }

  const currentBlock = await provider.getBlockNumber();
  const fromBlock = Number(lastSettled) + 1;
  const toBlock = currentBlock - 1;
  console.log(`Settling range [${fromBlock}, ${toBlock}], current block ${currentBlock}`);

  const { counts, unaccounted } = await countBlocksByMiner(provider, fromBlock, toBlock, founders);
  console.log("Block counts by founder in range:", counts, "unaccounted (other miners):", unaccounted);
  const blocksMined = founders.map((a) => counts[a.toLowerCase()]);
  const totalBlocks = blocksMined.reduce((a, b) => a + b, 0);

  const distBalance = await provider.getBalance(DISTRIBUTOR);
  console.log("Distributor balance now:", ethers.formatEther(distBalance), "ether");
  const totalRewards = distBalance;
  const totalFees = 0n;

  // ===== PHASE D: attempt with the fake (never-activated) address included =====
  console.log("\n=== PHASE D: attempting distributeRewards() with a never-activated address ===");
  const fakeValidators = [...founders, accounts.fakeAddress.address];
  const fakeBlocksMined = [...blocksMined, 1]; // nonzero blocksMined for the fake address, as instructed
  let phaseDResult = {};
  const phaseDSubmittedAt = new Date().toISOString();
  try {
    const tx = await distributor.distributeRewards(
      { fromBlock, toBlock },
      fakeValidators,
      fakeBlocksMined,
      totalRewards,
      totalFees,
      { gasLimit: 3_000_000 }
    );
    const receipt = await tx.wait();
    console.log("UNEXPECTED: Phase D call did NOT revert. status:", receipt.status, "tx:", receipt.hash);
    phaseDResult = { submittedAt: phaseDSubmittedAt, unexpectedSuccess: true, txHash: receipt.hash, status: receipt.status };
  } catch (err) {
    const msg = err.shortMessage || err.reason || err.message;
    console.log("Reverted as expected. Revert message:", msg);
    const containsExpected = msg.includes("address was never a legitimate validator");
    console.log("Contains expected substring 'address was never a legitimate validator':", containsExpected);
    phaseDResult = { submittedAt: phaseDSubmittedAt, reverted: true, revertMessage: msg, containsExpectedSubstring: containsExpected };
  }
  fs.writeFileSync(path.join(ROOT, "logs", "phaseD-result.json"), JSON.stringify(phaseDResult, null, 2));

  // Confirm state is unchanged after the revert (lastSettledBlock/epochCount untouched).
  const lastSettledAfterD = await distributor.lastSettledBlock();
  console.log("lastSettledBlock after Phase D attempt (should be unchanged):", lastSettledAfterD.toString(), "was:", lastSettled.toString());

  // ===== PHASE C: the REAL call, founder3 still included despite having exited mid-range =====
  console.log("\n=== PHASE C: real distributeRewards() call, founder3 still included after mid-range exit ===");
  const balancesBefore = {};
  for (const addr of [...founders, FOUNDATION, TREASURY]) {
    balancesBefore[addr] = await provider.getBalance(addr);
  }

  const phaseCSubmittedAt = new Date().toISOString();
  const tx2 = await distributor.distributeRewards(
    { fromBlock, toBlock },
    founders,
    blocksMined,
    totalRewards,
    totalFees,
    { gasLimit: 3_000_000 }
  );
  console.log("tx hash:", tx2.hash);
  const receipt2 = await tx2.wait();
  console.log("status:", receipt2.status, "gasUsed:", receipt2.gasUsed.toString());

  const balancesAfter = {};
  for (const addr of [...founders, FOUNDATION, TREASURY]) {
    balancesAfter[addr] = await provider.getBalance(addr);
  }

  const foundationShareBps = await distributor.FOUNDATION_SHARE_BPS();
  const validatorDirectShareBps = await distributor.validatorDirectShareBps();
  const expectedValidatorDirectTotal = (totalRewards * validatorDirectShareBps) / 10000n;

  console.log("\n=== Balance deltas (Phase C) ===");
  const deltas = {};
  for (const addr of [...founders, FOUNDATION, TREASURY]) {
    const delta = balancesAfter[addr] - balancesBefore[addr];
    deltas[addr] = delta.toString();
    console.log(`${addr}: delta=${ethers.formatEther(delta)}`);
  }
  for (let i = 0; i < founders.length; i++) {
    const expectedShare = totalBlocks > 0 ? (expectedValidatorDirectTotal * BigInt(blocksMined[i])) / BigInt(totalBlocks) : 0n;
    console.log(`founder${i + 1} (blocksMined=${blocksMined[i]}) expected=${ethers.formatEther(expectedShare)} actual=${ethers.formatEther(deltas[founders[i]])}`);
  }
  console.log(`\nfounder3 received nonzero payment despite isValidator()==false: ${BigInt(deltas[founders[2]]) > 0n}`);
  console.log(`founder1/founder2 did NOT receive a windfall of founder3's share (each matches only its own block count): see per-founder comparison above.`);

  fs.writeFileSync(
    path.join(ROOT, "logs", "phaseC-distribute-result.json"),
    JSON.stringify(
      {
        submittedAt: phaseCSubmittedAt,
        txHash: receipt2.hash,
        status: receipt2.status,
        gasUsed: receipt2.gasUsed.toString(),
        fromBlock,
        toBlock,
        blocksMined,
        totalRewards: totalRewards.toString(),
        totalFees: totalFees.toString(),
        balancesBefore: Object.fromEntries(Object.entries(balancesBefore).map(([k, v]) => [k, v.toString()])),
        balancesAfter: Object.fromEntries(Object.entries(balancesAfter).map(([k, v]) => [k, v.toString()])),
        deltas,
      },
      null,
      2
    )
  );
  console.log("\nWrote logs/phaseC-distribute-result.json and logs/phaseD-result.json");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
