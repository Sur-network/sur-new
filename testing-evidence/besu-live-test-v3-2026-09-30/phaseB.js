// Phase B: first real distributeRewards() call on the fresh network, paying the 3 founders.
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
  "function FOUNDATION_SHARE_BPS() view returns (uint256)",
  "function validatorDirectShareBps() view returns (uint256)",
];

async function countBlocksByMiner(provider, fromBlock, toBlock, addresses) {
  const counts = Object.fromEntries(addresses.map((a) => [a.toLowerCase(), 0]));
  for (let i = fromBlock; i <= toBlock; i++) {
    const blk = await provider.getBlock(i);
    const miner = blk.miner.toLowerCase();
    if (miner in counts) counts[miner]++;
  }
  return counts;
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const oracleWallet = new ethers.Wallet(accounts.distributionOracle.privateKey, provider);
  const distributor = new ethers.Contract(DISTRIBUTOR, DIST_ABI, oracleWallet);

  const founders = [accounts.founder1.address, accounts.founder2.address, accounts.founder3.address];

  const currentBlock = await provider.getBlockNumber();
  const fromBlock = 1;
  const toBlock = currentBlock - 1; // must be < current block per _settleRange
  console.log(`Current block: ${currentBlock}. Settling range [${fromBlock}, ${toBlock}]`);

  const counts = await countBlocksByMiner(provider, fromBlock, toBlock, founders);
  console.log("Block counts by founder:", counts);
  const blocksMined = founders.map((a) => counts[a.toLowerCase()]);
  const totalBlocks = blocksMined.reduce((a, b) => a + b, 0);
  console.log("Total blocks in range:", toBlock - fromBlock + 1, "accounted for:", totalBlocks);

  const distBalanceBefore = await provider.getBalance(DISTRIBUTOR);
  console.log("BlockRewardDistributor balance before:", ethers.formatEther(distBalanceBefore), "ether");

  const totalRewards = distBalanceBefore; // all accumulated blockreward, no tx fees on empty blocks
  const totalFees = 0n;

  const balancesBefore = {};
  for (const addr of [...founders, FOUNDATION, TREASURY]) {
    balancesBefore[addr] = await provider.getBalance(addr);
  }

  console.log("\nSubmitting distributeRewards()...");
  const submittedAt = new Date().toISOString();
  let receipt;
  try {
    const tx = await distributor.distributeRewards(
      { fromBlock, toBlock },
      founders,
      blocksMined,
      totalRewards,
      totalFees,
      { gasLimit: 3_000_000 }
    );
    console.log("tx hash:", tx.hash);
    receipt = await tx.wait();
  } catch (err) {
    console.error("distributeRewards() REVERTED or failed:", err.message);
    fs.writeFileSync(path.join(ROOT, "logs", "phaseB-result.json"), JSON.stringify({ error: err.message, submittedAt }, null, 2));
    process.exitCode = 1;
    return;
  }

  console.log("status:", receipt.status, "gasUsed:", receipt.gasUsed.toString());

  const balancesAfter = {};
  for (const addr of [...founders, FOUNDATION, TREASURY]) {
    balancesAfter[addr] = await provider.getBalance(addr);
  }

  const foundationShareBps = await distributor.FOUNDATION_SHARE_BPS();
  const validatorDirectShareBps = await distributor.validatorDirectShareBps();
  const expectedFoundation = (totalRewards * foundationShareBps) / 10000n;
  const expectedValidatorDirectTotal = (totalRewards * validatorDirectShareBps) / 10000n;
  const expectedTreasury = totalRewards - expectedFoundation - expectedValidatorDirectTotal;

  console.log("\n=== Balance deltas ===");
  const deltas = {};
  for (const addr of [...founders, FOUNDATION, TREASURY]) {
    const delta = balancesAfter[addr] - balancesBefore[addr];
    deltas[addr] = delta.toString();
    console.log(`${addr}: before=${ethers.formatEther(balancesBefore[addr])} after=${ethers.formatEther(balancesAfter[addr])} delta=${ethers.formatEther(delta)}`);
  }

  console.log("\nExpected foundation share (15%):", ethers.formatEther(expectedFoundation));
  console.log("Expected validator-direct total (", validatorDirectShareBps.toString(), "bps):", ethers.formatEther(expectedValidatorDirectTotal));
  console.log("Expected treasury remainder:", ethers.formatEther(expectedTreasury));

  for (let i = 0; i < founders.length; i++) {
    const expectedShare = totalBlocks > 0 ? (expectedValidatorDirectTotal * BigInt(blocksMined[i])) / BigInt(totalBlocks) : 0n;
    console.log(`founder${i + 1} expected share (proportional to ${blocksMined[i]}/${totalBlocks} blocks): ${ethers.formatEther(expectedShare)} vs actual delta ${ethers.formatEther(deltas[founders[i]])}`);
  }

  fs.writeFileSync(
    path.join(ROOT, "logs", "phaseB-result.json"),
    JSON.stringify(
      {
        submittedAt,
        txHash: receipt.hash,
        status: receipt.status,
        gasUsed: receipt.gasUsed.toString(),
        fromBlock,
        toBlock,
        blocksMined,
        totalRewards: totalRewards.toString(),
        totalFees: totalFees.toString(),
        balancesBefore: Object.fromEntries(Object.entries(balancesBefore).map(([k, v]) => [k, v.toString()])),
        balancesAfter: Object.fromEntries(Object.entries(balancesAfter).map(([k, v]) => [k, v.toString()])),
        deltas,
        expectedFoundation: expectedFoundation.toString(),
        expectedValidatorDirectTotal: expectedValidatorDirectTotal.toString(),
        expectedTreasury: expectedTreasury.toString(),
      },
      null,
      2
    )
  );
  console.log("\nWrote logs/phaseB-result.json");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
