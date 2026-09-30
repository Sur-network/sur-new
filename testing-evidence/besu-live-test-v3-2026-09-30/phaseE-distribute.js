// Phase E step 5: a distribution covering blocks mined by newValidator1 BEFORE its exit, called
// AFTER its full withdrawStake() (ValidatorInfo fully deleted) — must still succeed, proving
// everActivated (not isValidator, not even a live ValidatorInfo entry) is what gates payment.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "..");
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "accounts.json"), "utf8"));
const RPC = "http://127.0.0.1:8651";
const DISTRIBUTOR = "0x2222222222222222222222222222222222222222";
const FOUNDATION = "0x1111111111111111111111111111111111111111";
const TREASURY = "0x5555555555555555555555555555555555555555";
const REGISTRY = "0x3333333333333333333333333333333333333333";

const DIST_ABI = [
  "function distributeRewards((uint256 fromBlock,uint256 toBlock) range, address[] validators, uint256[] blocksMined, uint256 totalRewards, uint256 totalFees) external",
  "function lastSettledBlock() view returns (uint256)",
  "function lastDistributionTime() view returns (uint256)",
  "function MIN_DISTRIBUTION_INTERVAL() view returns (uint256)",
];
const REG_ABI = ["function getValidatorInfo(address) view returns (uint8,uint256,uint256,uint256,uint256,bool)", "function everActivated(address) view returns (bool)"];

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
  const registry = new ethers.Contract(REGISTRY, REG_ABI, provider);

  const lastSettled = await distributor.lastSettledBlock();
  const lastDistTime = await distributor.lastDistributionTime();
  const minInterval = await distributor.MIN_DISTRIBUTION_INTERVAL();
  const nowSec = Math.floor(Date.now() / 1000);
  const readyAt = Number(lastDistTime) + Number(minInterval);
  console.log("lastSettledBlock:", lastSettled.toString(), "readyAt:", readyAt, "now:", nowSec);
  if (nowSec < readyAt) {
    const waitMs = (readyAt - nowSec + 3) * 1000;
    console.log(`Waiting ${waitMs}ms for MIN_DISTRIBUTION_INTERVAL...`);
    await new Promise((r) => setTimeout(r, waitMs));
  }

  const currentBlock = await provider.getBlockNumber();
  const fromBlock = Number(lastSettled) + 1;
  // ✅ FIX: real blocks here are being produced slightly faster than the nominal 3s
  // blockperiodseconds (observed ~2.95s/block average), so simply taking toBlock=currentBlock-1
  // eventually reports more blocks than _checkPhysicalMaximum's elapsed/MIN_BLOCK_PERIOD_SECONDS
  // allows (a real, legitimate safety check — not a bug). Cap the declared range so totalBlocks
  // stays safely under that limit; this is well past newValidator1's actual activity window
  // (it exited at block 175), so its blocks are still fully included.
  const latestBlockObj = await provider.getBlock(currentBlock);
  const elapsedNow = latestBlockObj.timestamp - Number(lastDistTime);
  const MIN_BLOCK_PERIOD_SECONDS = 3;
  const maxSafeRangeSize = Math.floor(elapsedNow / MIN_BLOCK_PERIOD_SECONDS) - 10; // 10-block safety buffer
  const cappedToBlock = Math.min(currentBlock - 1, fromBlock + maxSafeRangeSize - 1);
  const toBlock = cappedToBlock;
  console.log(`Range [${fromBlock}, ${toBlock}] (capped from currentBlock-1=${currentBlock - 1} to stay under the physical-maximum gate), current block ${currentBlock}`);

  const participants = [accounts.founder1.address, accounts.founder2.address, accounts.newValidator1.address];
  const counts = await countBlocksByMiner(provider, fromBlock, toBlock, participants);
  console.log("Block counts:", counts);
  const blocksMined = participants.map((a) => counts[a.toLowerCase()]);
  const totalBlocks = blocksMined.reduce((a, b) => a + b, 0);

  // sanity: confirm newValidator1's ValidatorInfo really is cleared and everActivated is still true
  const infoNow = await registry.getValidatorInfo(accounts.newValidator1.address);
  const everActNow = await registry.everActivated(accounts.newValidator1.address);
  console.log("newValidator1 getValidatorInfo right before distribution:", infoNow);
  console.log("newValidator1 everActivated right before distribution:", everActNow);

  const distBalance = await provider.getBalance(DISTRIBUTOR);
  console.log("Distributor balance:", ethers.formatEther(distBalance));
  // ✅ FIX (root cause of the first attempt's revert): the distributor's raw balance also
  // includes newValidator1's one-time membership fee (forwarded via receiveMembershipFee() in
  // Phase E's join), which the contract tracks SEPARATELY as pendingMembershipFees and folds into
  // effectiveTotalFees inside _prepareEpoch — it is NOT part of totalRewards. Passing the full
  // raw balance as totalRewards double-counted that fee against the "totalRewards + fees <=
  // balance" check. totalRewards must be only the pure block-reward accrual for this range
  // (blockreward=2 ether/block per genesis config), matching what the real off-chain oracle would
  // compute from trace_block "reward" entries.
  const BLOCK_REWARD_WEI = ethers.parseEther("2");
  const totalRewards = BLOCK_REWARD_WEI * BigInt(toBlock - fromBlock + 1);
  console.log("Corrected totalRewards (pure block-reward accrual, excludes membership fee):", ethers.formatEther(totalRewards));

  const balancesBefore = {};
  for (const addr of [...participants, FOUNDATION, TREASURY]) balancesBefore[addr] = await provider.getBalance(addr);

  const submittedAt = new Date().toISOString();
  let receipt;
  try {
    const tx = await distributor.distributeRewards({ fromBlock, toBlock }, participants, blocksMined, totalRewards, 0n, { gasLimit: 3_000_000 });
    console.log("tx hash:", tx.hash);
    receipt = await tx.wait();
    console.log("status:", receipt.status, "gasUsed:", receipt.gasUsed.toString());
  } catch (err) {
    console.error("REVERTED:", err.reason || err.message);
    fs.writeFileSync(path.join(ROOT, "logs", "phaseE-distribute-result.json"), JSON.stringify({ error: err.reason || err.message, submittedAt }, null, 2));
    process.exitCode = 1;
    return;
  }

  const balancesAfter = {};
  for (const addr of [...participants, FOUNDATION, TREASURY]) balancesAfter[addr] = await provider.getBalance(addr);

  const deltas = {};
  console.log("\n=== Deltas ===");
  for (const addr of [...participants, FOUNDATION, TREASURY]) {
    const delta = balancesAfter[addr] - balancesBefore[addr];
    deltas[addr] = delta.toString();
    console.log(`${addr}: delta=${ethers.formatEther(delta)}`);
  }
  console.log(`\nnewValidator1 (fully withdrawn, ValidatorInfo deleted) received: ${ethers.formatEther(deltas[accounts.newValidator1.address])} (blocksMined=${blocksMined[2]}/${totalBlocks})`);

  fs.writeFileSync(
    path.join(ROOT, "logs", "phaseE-distribute-result.json"),
    JSON.stringify(
      {
        submittedAt,
        txHash: receipt.hash,
        status: receipt.status,
        gasUsed: receipt.gasUsed.toString(),
        fromBlock,
        toBlock,
        participants,
        blocksMined,
        totalRewards: totalRewards.toString(),
        distributorRawBalanceAtCallTime: distBalance.toString(),
        balancesBefore: Object.fromEntries(Object.entries(balancesBefore).map(([k, v]) => [k, v.toString()])),
        balancesAfter: Object.fromEntries(Object.entries(balancesAfter).map(([k, v]) => [k, v.toString()])),
        deltas,
        newValidator1InfoBeforeDistribution: infoNow.map((v) => v.toString()),
        newValidator1EverActivatedBeforeDistribution: everActNow,
      },
      null,
      2
    )
  );
  console.log("\nWrote logs/phaseE-distribute-result.json");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
