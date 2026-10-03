// D01 (negative cases, via staticCall - non-mutating) + D02 (real first distribution) on Net-D.
// Also covers C-L07-1/2 (ascending order) and C-REG-1 (P05 range regressions) and C-REG-2
// (everActivated regression groundwork — full regression completed after B-style suspend/exit,
// here we at least confirm the fake-address rejection and the real distribution succeeding).
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const RPC = "http://127.0.0.1:8751";
const DISTRIBUTOR = "0x2222222222222222222222222222222222222222";
const FOUNDATION = "0x1111111111111111111111111111111111111111";
const TREASURY = "0x5555555555555555555555555555555555555555";

const DIST_ABI = [
  "function distributeRewards((uint256 fromBlock,uint256 toBlock) range, address[] validators, uint256[] blocksMined, uint256 totalRewards, uint256 totalFees) external",
  "function lastSettledBlock() view returns (uint256)",
  "function epochCount() view returns (uint256)",
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

async function tryCall(label, distributor, args, oracleAddr) {
  try {
    await distributor.distributeRewards.staticCall(...args, { from: oracleAddr });
    return { label, result: "UNEXPECTED_SUCCESS" };
  } catch (err) {
    return { label, revertReason: err.reason || err.shortMessage || err.message };
  }
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const oracleWallet = new ethers.Wallet(accounts.distributionOracle.privateKey, provider);
  const distributor = new ethers.Contract(DISTRIBUTOR, DIST_ABI, oracleWallet);

  const founders = [1, 2, 3, 4, 5, 6].map((i) => accounts[`g6_v${i}`].address);
  const sortedFounders = [...founders].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : BigInt(a) > BigInt(b) ? 1 : 0));
  console.log("sorted founders:", sortedFounders);

  const currentBlock = await provider.getBlockNumber();
  const fromBlock = 1;
  const toBlock = currentBlock - 1;
  const counts = await countBlocksByMiner(provider, fromBlock, toBlock, sortedFounders);
  const blocksMined = sortedFounders.map((a) => counts[a.toLowerCase()]);
  const totalBlocks = blocksMined.reduce((a, b) => a + b, 0);
  console.log("range", fromBlock, toBlock, "blocksMined", blocksMined, "totalBlocks", totalBlocks, "rangeSize", toBlock - fromBlock + 1);

  const maxRewards = await distributor.maxRewardsForRange(fromBlock, toBlock);
  console.log("maxRewardsForRange:", maxRewards.toString());
  const validTotalRewards = maxRewards; // use the exact cap, per D02 spec ("totalRewards = سقف دقیق")

  const d01 = {};
  const oracleAddr = accounts.distributionOracle.address;

  d01.empty_list = await tryCall("empty_list", distributor, [{ fromBlock, toBlock }, [], [], validTotalRewards, 0n], oracleAddr);
  d01.length_mismatch = await tryCall("length_mismatch", distributor, [{ fromBlock, toBlock }, sortedFounders, [1], validTotalRewards, 0n], oracleAddr);
  d01.nothing_to_distribute = await tryCall("nothing_to_distribute", distributor, [{ fromBlock, toBlock }, sortedFounders, blocksMined, 0n, 0n], oracleAddr);
  d01.insufficient_balance = await tryCall("insufficient_balance", distributor, [{ fromBlock, toBlock }, sortedFounders, blocksMined, ethers.parseEther("999999999"), 0n], oracleAddr);
  d01.range_not_from_s_plus_1 = await tryCall("range_not_from_s_plus_1", distributor, [{ fromBlock: 2, toBlock }, sortedFounders, blocksMined, validTotalRewards, 0n], oracleAddr);
  d01.range_inverted = await tryCall("range_inverted", distributor, [{ fromBlock: 10, toBlock: 5 }, sortedFounders, blocksMined, validTotalRewards, 0n], oracleAddr);
  d01.range_not_yet_produced = await tryCall("range_not_yet_produced", distributor, [{ fromBlock, toBlock: currentBlock + 1000 }, sortedFounders, blocksMined, validTotalRewards, 0n], oracleAddr);
  d01.blocks_exceed_range = await tryCall("blocks_exceed_range", distributor, [{ fromBlock, toBlock }, sortedFounders, blocksMined.map((b) => b + 1000), validTotalRewards, 0n], oracleAddr);
  d01.cap_plus_1wei = await tryCall("cap_plus_1wei (L05)", distributor, [{ fromBlock, toBlock }, sortedFounders, blocksMined, maxRewards + 1n, 0n], oracleAddr);
  const dup = [sortedFounders[0], sortedFounders[0], ...sortedFounders.slice(1)];
  d01.duplicate_address = await tryCall("duplicate_address (L07)", distributor, [{ fromBlock, toBlock }, dup, [blocksMined[0], blocksMined[0], ...blocksMined.slice(1)], validTotalRewards, 0n], oracleAddr);
  const descending = [...sortedFounders].reverse();
  d01.descending_order = await tryCall("descending_order (L07)", distributor, [{ fromBlock, toBlock }, descending, [...blocksMined].reverse(), validTotalRewards, 0n], oracleAddr);
  const withZero = [ethers.ZeroAddress, ...sortedFounders].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
  d01.zero_address = await tryCall("zero_address", distributor, [{ fromBlock, toBlock }, withZero, [1, ...blocksMined], validTotalRewards, 0n], oracleAddr);
  const withFake = [...sortedFounders, accounts.fakeAddress.address].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
  const fakeIdx = withFake.indexOf(accounts.fakeAddress.address);
  const blocksWithFake = withFake.map((a) => (a === accounts.fakeAddress.address ? 1 : blocksMined[sortedFounders.indexOf(a)]));
  d01.never_activated_address = await tryCall("never_activated_address (C-REG-2)", distributor, [{ fromBlock, toBlock }, withFake, blocksWithFake, validTotalRewards, 0n], oracleAddr);
  // non-oracle sender
  try {
    const distAsFounder = distributor.connect(new ethers.Wallet(accounts.g6_v1.privateKey, provider));
    await distAsFounder.distributeRewards.staticCall({ fromBlock, toBlock }, sortedFounders, blocksMined, validTotalRewards, 0n);
    d01.non_oracle_sender = { result: "UNEXPECTED_SUCCESS" };
  } catch (err) {
    d01.non_oracle_sender = { revertReason: err.reason || err.shortMessage || err.message };
  }

  console.log("\n=== D01 results ===");
  console.log(JSON.stringify(d01, null, 2));

  const lastSettledBefore = await distributor.lastSettledBlock();
  const epochCountBefore = await distributor.epochCount();
  console.log("\nlastSettledBlock before:", lastSettledBefore.toString(), "epochCount before:", epochCountBefore.toString());

  // === D02: the REAL first distribution ===
  const balancesBefore = {};
  for (const addr of [...sortedFounders, FOUNDATION, TREASURY]) balancesBefore[addr] = await provider.getBalance(addr);

  const submittedAt = new Date().toISOString();
  const tx = await distributor.distributeRewards({ fromBlock, toBlock }, sortedFounders, blocksMined, validTotalRewards, 0n, { gasLimit: 5_000_000 });
  const receipt = await tx.wait();
  console.log("\nD02 tx:", receipt.hash, "status:", receipt.status, "gasUsed:", receipt.gasUsed.toString());

  const balancesAfter = {};
  for (const addr of [...sortedFounders, FOUNDATION, TREASURY]) balancesAfter[addr] = await provider.getBalance(addr);
  const deltas = {};
  for (const addr of [...sortedFounders, FOUNDATION, TREASURY]) deltas[addr] = (balancesAfter[addr] - balancesBefore[addr]).toString();

  const foundationShareBps = await distributor.FOUNDATION_SHARE_BPS();
  const validatorDirectShareBps = await distributor.validatorDirectShareBps();
  const expectedFoundation = (validTotalRewards * foundationShareBps) / 10000n;
  const expectedValidatorDirectTotal = (validTotalRewards * validatorDirectShareBps) / 10000n;
  const expectedTreasury = validTotalRewards - expectedFoundation - expectedValidatorDirectTotal;

  const d02 = {
    submittedAt, txHash: receipt.hash, status: receipt.status, gasUsed: receipt.gasUsed.toString(),
    fromBlock, toBlock, blocksMined, totalRewards: validTotalRewards.toString(),
    lastSettledBlockAfter: (await distributor.lastSettledBlock()).toString(),
    epochCountAfter: (await distributor.epochCount()).toString(),
    deltas, expectedFoundation: expectedFoundation.toString(), expectedValidatorDirectTotal: expectedValidatorDirectTotal.toString(), expectedTreasury: expectedTreasury.toString(),
  };
  console.log("\n=== D02 result ===");
  console.log(JSON.stringify(d02, null, 2));

  // D03: immediate second attempt, expects "too soon"
  let d03;
  try {
    await distributor.distributeRewards.staticCall({ fromBlock: toBlock + 1, toBlock: toBlock + 1 }, [sortedFounders[0]], [1], 1n, 0n);
    d03 = { result: "UNEXPECTED_SUCCESS" };
  } catch (err) {
    d03 = { revertReason: err.reason || err.shortMessage || err.message };
  }
  console.log("\n=== D03 result ===", JSON.stringify(d03));

  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-D-D01-D02-D03.json"), JSON.stringify({ d01, d02, d03 }, null, 2));
  console.log("\nWrote evidence file.");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
