// TESTONLY TOOL — Group A (genesis, storage, founder checkpoint) checks, read-only.
// env: GROUPA_NET, GROUPA_RPC, GROUPA_FOUNDERS (G5|G6), GROUPA_PROJECT_ROOT, GROUPA_FULL (1 for A06-A10/A15)
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

const ROOT = process.env.GROUPA_PROJECT_ROOT;
const NET = process.env.GROUPA_NET;
const RPC = `http://127.0.0.1:${process.env.GROUPA_RPC}`;
const FOUNDERS = process.env.GROUPA_FOUNDERS;
const FULL = process.env.GROUPA_FULL === "1";

const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const founderRoleList = FOUNDERS === "G5" ? ["g5_v1", "g5_v2", "g5_v3", "g5_v4", "g5_v5"] : ["g6_v1", "g6_v2", "g6_v3", "g6_v4", "g6_v5", "g6_v6"];
const founders = founderRoleList.map((r) => accounts[r].address);

const FIXED = {
  FoundationDAO: "0x1111111111111111111111111111111111111111",
  BlockRewardDistributor: "0x2222222222222222222222222222222222222222",
  ValidatorsRegistry: "0x3333333333333333333333333333333333333333",
  ValidatorsBoard: "0x4444444444444444444444444444444444444444",
  ValidatorsTreasury: "0x5555555555555555555555555555555555555555",
  IdentityRegistry: "0x6666666666666666666666666666666666666666",
};

const REG_ABI = [
  "function getValidators() view returns (address[])",
  "function isValidator(address) view returns (bool)",
  "function everActivated(address) view returns (bool)",
  "function statusNonce() view returns (uint256)",
  "function wasActiveAt(address,uint256) view returns (bool)",
  "function verifier() view returns (address)",
  "function probationPeriod() view returns (uint256)",
  "function recoveryPeriod() view returns (uint256)",
  "function exitCooldown() view returns (uint256)",
  "function maxEntriesPerWindow() view returns (uint256)",
  "function windowStart() view returns (uint256)",
];
const BOARD_ABI = ["function getBoardMembers() view returns (address[])", "function boardVersion() view returns (uint256)", "function lastBoardRefreshAt() view returns (uint256)"];
const FD_ABI = ["function memberList(uint256) view returns (string,address)", "function membershipNonce() view returns (uint256)", "function memberSinceNonce(address) view returns (uint256)"];
const DIST_ABI = [
  "function INITIAL_REWARD_PER_BLOCK() view returns (uint256)",
  "function rewardRateChangeCount() view returns (uint256)",
  "function rateProposalCount() view returns (uint256)",
  "function lastSettledBlock() view returns (uint256)",
  "function epochCount() view returns (uint256)",
  "function distributionOracle() view returns (address)",
  "function validatorDirectShareBps() view returns (uint256)",
  "function maxRewardsForRange(uint256,uint256) view returns (uint256)",
  "function RATE_VOTING_EXPIRY() view returns (uint256)",
  "function RATE_CHANGE_DELAY() view returns (uint256)",
  "function MIN_RATE_CHANGE_LEAD_BLOCKS() view returns (uint256)",
];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const registry = new ethers.Contract(FIXED.ValidatorsRegistry, REG_ABI, provider);
  const board = new ethers.Contract(FIXED.ValidatorsBoard, BOARD_ABI, provider);
  const foundation = new ethers.Contract(FIXED.FoundationDAO, FD_ABI, provider);
  const distributor = new ethers.Contract(FIXED.BlockRewardDistributor, DIST_ABI, provider);

  const result = { net: NET, timestamp: new Date().toISOString() };

  // A01 (hash) covered separately in Phase 0 report. A02/A03: read raw genesis.json (file-level, done by builder evidence).
  // A04/A05: code hash comparison vs this build's bytecode (done in Phase 0 report + per-net genesis evidence).
  const block1 = await provider.getBlock(1).catch(() => null);
  result.A01_note = "covered in Phase 0 baseline hash report + per-network genesis.json evidence";

  // A06/A07/A08 (full group only on Net-B/Net-D)
  const getValidatorsResult = await registry.getValidators();
  result.A06_getValidators = getValidatorsResult;
  result.A06_matchesFounders = getValidatorsResult.length === founders.length && getValidatorsResult.every((a, i) => a.toLowerCase() === founders[i].toLowerCase());

  result.A07 = {};
  for (const addr of founders) {
    result.A07[addr] = { isValidator: await registry.isValidator(addr), everActivated: await registry.everActivated(addr) };
  }

  const statusNonce = await registry.statusNonce();
  result.A08 = { statusNonce: statusNonce.toString() };
  result.A08.wasActiveAt_founders = {};
  for (const addr of founders) {
    result.A08.wasActiveAt_founders[addr] = await registry.wasActiveAt(addr, 0);
  }
  result.A08.wasActiveAt_nonFounder = await registry.wasActiveAt(accounts.fakeAddress.address, 0);

  // A09
  const boardMembers = await board.getBoardMembers();
  result.A09 = { boardMembers, boardVersion: (await board.boardVersion()).toString(), lastBoardRefreshAt: (await board.lastBoardRefreshAt()).toString() };

  // A10
  try {
    const membershipNonce = await foundation.membershipNonce();
    result.A10 = { membershipNonce: membershipNonce.toString(), members: [] };
    for (let i = 0; i < 15; i++) {
      try {
        const [name, acct] = await foundation.memberList(i);
        const sinceNonce = await foundation.memberSinceNonce(acct);
        result.A10.members.push({ name, acct, sinceNonce: sinceNonce.toString() });
      } catch (e) { break; }
    }
  } catch (e) {
    result.A10 = { error: e.message };
  }

  // A11
  result.A11 = {
    INITIAL_REWARD_PER_BLOCK: (await distributor.INITIAL_REWARD_PER_BLOCK()).toString(),
    rewardRateChangeCount: (await distributor.rewardRateChangeCount()).toString(),
    rateProposalCount: (await distributor.rateProposalCount()).toString(),
    lastSettledBlock: (await distributor.lastSettledBlock()).toString(),
    epochCount: (await distributor.epochCount()).toString(),
    distributionOracle: await distributor.distributionOracle(),
    validatorDirectShareBps: (await distributor.validatorDirectShareBps()).toString(),
    maxRewardsForRange_1_1000: (await distributor.maxRewardsForRange(1, 1000)).toString(),
    RATE_VOTING_EXPIRY: (await distributor.RATE_VOTING_EXPIRY()).toString(),
    RATE_CHANGE_DELAY: (await distributor.RATE_CHANGE_DELAY()).toString(),
    MIN_RATE_CHANGE_LEAD_BLOCKS: (await distributor.MIN_RATE_CHANGE_LEAD_BLOCKS()).toString(),
  };

  // A13 overlays
  result.A13 = {
    verifier: await registry.verifier(),
    probationPeriod: (await registry.probationPeriod()).toString(),
    recoveryPeriod: (await registry.recoveryPeriod()).toString(),
    exitCooldown: (await registry.exitCooldown()).toString(),
    maxEntriesPerWindow: (await registry.maxEntriesPerWindow()).toString(),
    windowStart: (await registry.windowStart()).toString(),
  };

  // A15 (only meaningful once >=100 blocks exist — recorded regardless, flagged if too early)
  const currentBlock = await provider.getBlockNumber();
  if (currentBlock >= 100) {
    const periods = [];
    for (let i = 1; i <= 100; i++) {
      const b = await provider.getBlock(i);
      const prev = await provider.getBlock(i - 1);
      periods.push(b.timestamp - prev.timestamp);
    }
    periods.sort((a, b) => a - b);
    const avg = periods.reduce((a, b) => a + b, 0) / periods.length;
    const p95 = periods[Math.floor(periods.length * 0.95)];
    result.A15 = { blocksChecked: 100, avgPeriod: avg, min: periods[0], max: periods[periods.length - 1], p95 };
  } else {
    result.A15 = { note: `only ${currentBlock} blocks so far, need >=100 for A15 — will retry later` };
  }

  console.log(JSON.stringify(result, null, 2));

  const outDir = path.join(ROOT, "evidence", "04-results");
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, `${NET}-groupA.json`), JSON.stringify(result, null, 2));
  console.log(`\nWrote ${path.join(outDir, `${NET}-groupA.json`)}`);
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
