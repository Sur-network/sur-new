// Full governance Path L (L1-L3 + execute) on Net-Fork, using the compressed RATE_CHANGE_DELAY
// (180s) and MIN_RATE_CHANGE_LEAD_BLOCKS (80 blocks). This is the first time this governed
// rate-change path has been exercised end-to-end on a real Besu network (v4's own real-constant
// path needs ~14 days and was explicitly left to the owner's discretion). L4's "Besu coordination"
// aspect (does the real blockreward at startBlock match the approved cap) is separately covered
// by Group F (F01-F04) using seeded history; not redundantly re-attempted here.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const RPC = "http://127.0.0.1:8791";
const DISTRIBUTOR = "0x2222222222222222222222222222222222222222";
const BOARD = "0x4444444444444444444444444444444444444444";
const REGISTRY = "0x3333333333333333333333333333333333333333";

const DIST_ABI = [
  "function proposeRateChange(uint256,uint256) external returns (uint256)",
  "function boardVoteRateChange(uint256) external",
  "function validatorVoteRateChange(uint256) external",
  "function executeRateChange(uint256) external",
  "function rateChangeStatus(uint256) view returns (uint8,uint8)",
  "function rateProposals(uint256) view returns (uint128 startBlock,uint128 ratePerBlock,uint256 createdAt,uint256 votingExpiresAt,uint256 approvedAt,uint256 requiredValidatorApprovals,uint256 boardApprovals,uint256 validatorApprovals,bool executed,uint256 boardVersionAtCreation,uint256 validatorNonceAtCreation)",
  "function rewardRateChangeCount() view returns (uint256)",
  "function rewardRateChanges(uint256) view returns (uint128,uint128)",
  "function RATE_CHANGE_DELAY() view returns (uint256)",
  "function MIN_RATE_CHANGE_LEAD_BLOCKS() view returns (uint256)",
];
const REG_ABI = ["function getActiveValidatorCount() view returns (uint256)"];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const founders = [1, 2, 3, 4, 5].map((i) => new ethers.Wallet(accounts[`g5_v${i}`].privateKey, provider));
  const registry = new ethers.Contract(REGISTRY, REG_ABI, provider);
  const n = await registry.getActiveValidatorCount();

  const distV1 = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[0]);
  const distP = new ethers.Contract(DISTRIBUTOR, DIST_ABI, provider);
  const out = {};

  const leadBlocks = await distP.MIN_RATE_CHANGE_LEAD_BLOCKS();
  const rateChangeDelay = await distP.RATE_CHANGE_DELAY();
  const currentBlock = await provider.getBlockNumber();
  const startBlock = currentBlock + Number(leadBlocks) + 10; // margin above the minimum
  console.log("currentBlock:", currentBlock, "leadBlocks:", leadBlocks.toString(), "startBlock:", startBlock);

  // L1: propose + both chambers approve
  const proposeTx = await distV1.proposeRateChange(startBlock, ethers.parseEther("3"), { gasLimit: 400000 });
  const proposeRcpt = await proposeTx.wait();
  const id = Number(await distP.rewardRateChangeCount()) + 1; // rateProposalCount, but no getter alias; read via event or proposals directly
  // safer: read rateProposalCount via a side call
  const distFull = new ethers.Contract(DISTRIBUTOR, [...DIST_ABI, "function rateProposalCount() view returns (uint256)"], provider);
  const realId = Number(await distFull.rateProposalCount());
  out.propose = { txHash: proposeRcpt.hash, status: proposeRcpt.status, id: realId, startBlock, ratePerBlock: ethers.parseEther("3").toString() };

  for (let i = 0; i < 3; i++) {
    const d = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await d.boardVoteRateChange(realId, { gasLimit: 300000 })).wait();
  }
  const required = Number((await distP.rateProposals(realId))[5]);
  for (let i = 0; i < required; i++) {
    const d = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await d.validatorVoteRateChange(realId, { gasLimit: 300000 })).wait();
  }
  const afterVotes = await distP.rateProposals(realId);
  const statusAfterVotes = await distP.rateChangeStatus(realId);
  out.L1 = { requiredValidatorApprovals: required, approvedAt: afterVotes[4].toString(), statusAfterVotes: { status: Number(statusAfterVotes[0]), problem: Number(statusAfterVotes[1]) } };
  console.log("=== L1 (approved by both chambers) ===", JSON.stringify(out.L1, null, 2));

  // premature execute attempt (before delay) - expect "execution delay has not elapsed"
  try {
    await distV1.executeRateChange.staticCall(realId);
    out.L1.prematureExecute = "UNEXPECTED_SUCCESS";
  } catch (err) {
    out.L1.prematureExecute = err.reason || err.message;
  }

  // L2: wait RATE_CHANGE_DELAY
  console.log(`\nWaiting ${rateChangeDelay}s for RATE_CHANGE_DELAY...`);
  await new Promise((r) => setTimeout(r, (Number(rateChangeDelay) + 5) * 1000));

  const statusAfterDelay = await distP.rateChangeStatus(realId);
  out.L2 = { statusAfterDelay: { status: Number(statusAfterDelay[0]), problem: Number(statusAfterDelay[1]) } };
  console.log("=== L2 (delay elapsed) ===", JSON.stringify(out.L2, null, 2));

  // L3: wait until startBlock - MIN_RATE_CHANGE_LEAD_BLOCKS margin consumed (just wait for enough blocks)
  const blockNow = await provider.getBlockNumber();
  const blocksNeeded = startBlock - blockNow; // need block.number to be within lead-blocks distance eventually; actually execute just needs startBlock > block.number + leadBlocks is now FALSE is required to NOT revert... wait _rateStartProblem returns 3 if startBlock < block.number+leadBlocks. We want this to be false (startBlock >= block.number+leadBlocks) - already true since startBlock was set with margin. Execute can happen NOW regardless of current block, as long as startBlock is still far enough ahead. Let's just execute now.
  console.log("blockNow:", blockNow, "startBlock:", startBlock, "margin:", startBlock - blockNow);

  const execTx = await distV1.executeRateChange(realId, { gasLimit: 400000 });
  const execRcpt = await execTx.wait();
  const historyCount = await distP.rewardRateChangeCount();
  const lastEntry = await distP.rewardRateChanges(Number(historyCount) - 1);
  out.L3_execute = { txHash: execRcpt.hash, status: execRcpt.status, historyCount: historyCount.toString(), lastEntry: { startBlock: lastEntry[0].toString(), ratePerBlock: lastEntry[1].toString() } };
  console.log("\n=== L3 (executed, history updated) ===", JSON.stringify(out.L3_execute, null, 2));

  out.note = "L4's Besu-side blockreward-transition coordination at startBlock is covered separately by Group F (F01-F04) using seeded history, not re-attempted here on this already-distributing network.";

  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-Fork-L1-L3-ratepath.json"), JSON.stringify(out, null, 2));
  console.log("\nWrote evidence file.");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
