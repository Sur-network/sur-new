// Shared helpers for the v5 follow-up scripts (Groups F/E, D02 accounting, L05 re-runs). Test tooling only.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const ADDR = {
  FOUNDATION: "0x1111111111111111111111111111111111111111",
  DISTRIBUTOR: "0x2222222222222222222222222222222222222222",
  REGISTRY: "0x3333333333333333333333333333333333333333",
  BOARD: "0x4444444444444444444444444444444444444444",
  TREASURY: "0x5555555555555555555555555555555555555555",
  IDENTITY: "0x6666666666666666666666666666666666666666",
  BURN: "0x0000000000000000000000000000000000000000",
};

// Full distributor ABI subset used by the follow-up scripts (verified against baseline/contracts/BlockRewardDistributor.sol).
const DIST_ABI = [
  "function distributeRewards((uint256 fromBlock,uint256 toBlock) range, address[] validators, uint256[] blocksMined, uint256 totalRewards, uint256 totalFees) external",
  "function lastSettledBlock() view returns (uint256)",
  "function epochCount() view returns (uint256)",
  "function lastDistributionTime() view returns (uint256)",
  "function maxRewardsForRange(uint256,uint256) view returns (uint256)",
  "function rewardRateAt(uint256) view returns (uint256)",
  "function rewardRateChangeCount() view returns (uint256)",
  "function rewardRateChange(uint256) view returns (uint256 startBlock, uint256 ratePerBlock)",
  "function FOUNDATION_SHARE_BPS() view returns (uint256)",
  "function FEE_BURN_BPS() view returns (uint256)",
  "function validatorDirectShareBps() view returns (uint256)",
  "function pendingMembershipFees() view returns (uint256)",
  "function totalFeesBurned() view returns (uint256)",
  "function epochBlockRanges(uint256) view returns (uint256 fromBlock, uint256 toBlock)",
  "function getEpoch(uint256) view returns (uint256 timestamp,uint256 totalRewards,uint256 totalFees,uint256 treasuryAmount,uint256 totalBlocksMined,uint256 validatorCount)",
  "function epochValidatorRewardShare(uint256,address) view returns (uint256)",
  "function epochValidatorFeeShare(uint256,address) view returns (uint256)",
  "function epochValidatorBlocks(uint256,address) view returns (uint256)",
  "event MembershipFeeReceived(uint256 amount, uint256 newPendingTotal)",
  "event RewardsDistributed(uint256 indexed epochId, uint256 totalRewards, uint256 totalFees, uint256 treasuryAmount, uint256 totalBlocks, uint256 validatorCount)",
  "event FeesBurned(uint256 indexed epochId, uint256 amount, uint256 totalBurned)",
  "event ValidatorRewarded(uint256 indexed epochId, address indexed validator, uint256 blocksMined, uint256 rewardShare, uint256 feeShare, uint256 totalPayout)",
];

const sortAsc = (arr) => [...arr].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : BigInt(a) > BigInt(b) ? 1 : 0));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const hex = (n) => "0x" + BigInt(n).toString(16);
const SUR = (wei) => ethers.formatEther(BigInt(wei));

function rpc(url) {
  return async (method, params = []) => {
    const res = await fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) });
    const j = await res.json();
    if (j.error) { const e = new Error(`${method}: ${j.error.message}`); e.rpcError = j.error; throw e; }
    return j.result;
  };
}

async function waitForBlock(provider, target, label = "") {
  for (;;) {
    const h = await provider.getBlockNumber();
    if (h >= target) return h;
    await sleep(3000);
  }
}

async function balanceAt(provider, addr, blockNumber) {
  return BigInt(await provider.send("eth_getBalance", [addr, hex(blockNumber)]));
}

// Per-block reward observation, two independent ways: (1) empty-block balance delta of the distributor, (2) trace_block "reward" entries.
async function observeBlock(provider, call, n) {
  const blk = await provider.send("eth_getBlockByNumber", [hex(n), false]);
  const txCount = blk.transactions.length;
  const bal = await balanceAt(provider, ADDR.DISTRIBUTOR, n);
  const balPrev = n > 0 ? await balanceAt(provider, ADDR.DISTRIBUTOR, n - 1) : 0n;
  let traceRewards = null, traceError = null;
  try {
    const traces = await call("trace_block", [hex(n)]);
    traceRewards = traces.filter((t) => t.type === "reward").map((t) => ({ author: t.action.author, rewardType: t.action.rewardType, value: BigInt(t.action.value).toString() }));
  } catch (e) { traceError = e.message; }
  return { n, miner: blk.miner, txCount, balanceDelta: (bal - balPrev).toString(), emptyBlockMethod: txCount === 0 ? (bal - balPrev).toString() : null, traceRewards, traceError };
}

function saveEvidence(name, obj) {
  const dir = path.join(ROOT, "evidence", "04-results");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, name), JSON.stringify(obj, (k, v) => (typeof v === "bigint" ? v.toString() : v), 2));
  console.log("wrote evidence:", name);
}

module.exports = { ethers, fs, path, ROOT, accounts, ADDR, DIST_ABI, sortAsc, sleep, hex, SUR, rpc, waitForBlock, balanceAt, observeBlock, saveEvidence };
