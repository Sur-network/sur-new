// FINAL, corrected, single-file reproduction of the L1-L3 rate-change governance path that
// actually succeeded on Net-Fork (proposal id=2: startBlock=590, rate=3.3 ether, executed at
// block ~499). Consolidates two fixes found and applied during this round (see FINDINGS.md item
// 5 and the DEVIATIONS.md / review-response history):
//
//   1. RateProposal struct field order: the correct order, read directly from
//      BlockRewardDistributor.sol's own struct declaration, is
//      (startBlock, ratePerBlock, createdAt, votingExpiresAt, requiredValidatorApprovals,
//       boardApprovals, validatorApprovals, approvedAt, executed, boardVersionAtCreation,
//       validatorNonceAtCreation). Earlier attempts in this round used a wrong order (swapped
//      approvedAt/requiredValidatorApprovals), which silently under-counted the required
//      validator votes by one.
//   2. startBlock margin: must cover MIN_RATE_CHANGE_LEAD_BLOCKS (blocks) PLUS the number of
//      blocks the chain will produce during the real RATE_CHANGE_DELAY wait (~delay/3s blocks),
//      plus a safety buffer -- not just the lead-blocks minimum measured at proposal time.
//
// This script performs the full sequence end-to-end: propose -> 3 board votes -> N validator
// votes (N = the correct, freshly-read requiredValidatorApprovals) -> wait the real compressed
// RATE_CHANGE_DELAY -> executeRateChange. It is idempotent to run against a fresh network (it
// creates a NEW proposal each time; it does not assume proposal id=2 already exists).
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const RPC = "http://127.0.0.1:8791";
const DISTRIBUTOR = "0x2222222222222222222222222222222222222222";

const DIST_ABI = [
  "function proposeRateChange(uint256,uint256) external returns (uint256)",
  "function boardVoteRateChange(uint256) external",
  "function validatorVoteRateChange(uint256) external",
  "function executeRateChange(uint256) external",
  "function rateChangeStatus(uint256) view returns (uint8,uint8)",
  // CORRECT field order -- see header comment, fix #1.
  "function rateProposals(uint256) view returns (uint128 startBlock,uint128 ratePerBlock,uint256 createdAt,uint256 votingExpiresAt,uint256 requiredValidatorApprovals,uint256 boardApprovals,uint256 validatorApprovals,uint256 approvedAt,bool executed,uint256 boardVersionAtCreation,uint256 validatorNonceAtCreation)",
  "function rewardRateChangeCount() view returns (uint256)",
  // The underlying array (`rewardRateChanges`) is private; this is the contract's own public
  // single-entry getter (BlockRewardDistributor.sol:843), which returns uint256 (Solidity
  // upcasts the struct's internal uint128 fields on return) -- NOT a `rewardRateChanges(uint256)`
  // auto-getter, which does not exist for a private array.
  "function rewardRateChange(uint256) view returns (uint256 startBlock, uint256 ratePerBlock)",
  "function RATE_CHANGE_DELAY() view returns (uint256)",
  "function MIN_RATE_CHANGE_LEAD_BLOCKS() view returns (uint256)",
  "function rateProposalCount() view returns (uint256)",
];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const founders = [1, 2, 3, 4, 5].map((i) => new ethers.Wallet(accounts[`g5_v${i}`].privateKey, provider));
  const distV1 = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[0]);
  const distP = new ethers.Contract(DISTRIBUTOR, DIST_ABI, provider);
  const out = {};

  // --- margin fix #2: cover the delay wait's blocks too, not just the lead-blocks minimum ---
  const leadBlocks = Number(await distP.MIN_RATE_CHANGE_LEAD_BLOCKS());
  const rateChangeDelay = Number(await distP.RATE_CHANGE_DELAY());
  const currentBlock = await provider.getBlockNumber();
  const blocksDuringDelay = Math.ceil(rateChangeDelay / 3); // nominal 3s/block
  const startBlock = currentBlock + blocksDuringDelay + leadBlocks + 30; // +30 safety buffer
  console.log("currentBlock:", currentBlock, "leadBlocks:", leadBlocks, "delay:", rateChangeDelay, "blocksDuringDelay:", blocksDuringDelay, "startBlock:", startBlock);

  const proposeTx = await distV1.proposeRateChange(startBlock, ethers.parseEther("3.3"), { gasLimit: 400000 });
  const proposeRcpt = await proposeTx.wait();
  const id = Number(await distP.rateProposalCount());
  out.propose = { txHash: proposeRcpt.hash, status: proposeRcpt.status, id, startBlock, ratePerBlock: ethers.parseEther("3.3").toString() };
  console.log("Proposed id:", id, "tx:", proposeRcpt.hash, "status:", proposeRcpt.status);

  // 3 board votes (RATE_CHANGE_BOARD_APPROVALS is a fixed constant = 3, never snapshotted)
  for (let i = 0; i < 3; i++) {
    const d = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await d.boardVoteRateChange(id, { gasLimit: 300000 })).wait();
  }

  // --- fix #1 in action: read requiredValidatorApprovals from the CORRECT struct index (4) ---
  const required = Number((await distP.rateProposals(id))[4]);
  console.log("requiredValidatorApprovals (correctly read):", required);
  for (let i = 0; i < required; i++) {
    const d = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await d.validatorVoteRateChange(id, { gasLimit: 300000 })).wait();
  }

  const afterVotes = await distP.rateProposals(id);
  const statusAfterVotes = await distP.rateChangeStatus(id);
  out.L1 = {
    requiredValidatorApprovals: required,
    boardApprovals: afterVotes[5].toString(),
    validatorApprovals: afterVotes[6].toString(),
    approvedAt: afterVotes[7].toString(),
    statusAfterVotes: { status: Number(statusAfterVotes[0]), problem: Number(statusAfterVotes[1]) },
  };
  console.log("=== L1 (both chambers approved) ===", JSON.stringify(out.L1, null, 2));
  if (afterVotes[7].toString() === "0") throw new Error("L1 FAILED: proposal did not reach approvedAt != 0 -- check vote counts");

  // premature execute attempt -- expected to revert with "execution delay has not elapsed".
  // An unexpected SUCCESS here means the delay gate did not hold, which invalidates the whole
  // L1-L3 sequence as proof of anything -- treat it as a hard failure, not a logged curiosity.
  try {
    await distV1.executeRateChange.staticCall(id);
    out.L1.prematureExecute = "UNEXPECTED_SUCCESS";
    fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
    fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-Fork-L1-L3-ratepath-FINAL-script-output.json"), JSON.stringify(out, null, 2));
    throw new Error("L1 FAILED: executeRateChange.staticCall succeeded before RATE_CHANGE_DELAY elapsed -- the delay gate did not hold");
  } catch (err) {
    if (err.message && err.message.startsWith("L1 FAILED")) throw err;
    out.L1.prematureExecute = err.reason || err.message;
  }

  // --- L2: wait the REAL (compressed) RATE_CHANGE_DELAY ---
  console.log(`\nWaiting ${rateChangeDelay}s for RATE_CHANGE_DELAY...`);
  await new Promise((r) => setTimeout(r, (rateChangeDelay + 5) * 1000));

  const statusAfterDelay = await distP.rateChangeStatus(id);
  const blockNow = await provider.getBlockNumber();
  out.L2 = { statusAfterDelay: { status: Number(statusAfterDelay[0]), problem: Number(statusAfterDelay[1]) }, blockNow, startBlock, marginRemaining: startBlock - blockNow };
  console.log("=== L2 (delay elapsed) ===", JSON.stringify(out.L2, null, 2));

  // --- L3: execute ---
  const execTx = await distV1.executeRateChange(id, { gasLimit: 400000 });
  const execRcpt = await execTx.wait();
  const historyCount = await distP.rewardRateChangeCount();
  const lastEntry = await distP.rewardRateChange(Number(historyCount) - 1);
  out.L3_execute = { txHash: execRcpt.hash, status: execRcpt.status, historyCountAfter: historyCount.toString(), lastEntry: { startBlock: lastEntry[0].toString(), ratePerBlock: lastEntry[1].toString() } };
  console.log("\n=== L3 (executed, history updated) ===", JSON.stringify(out.L3_execute, null, 2));

  out.scopeNote = "This proves L1 (propose+approve) through L3 (execute, history updated) end-to-end on real Besu. It does NOT cross startBlock and does NOT make any distribution at the new rate -- that step (L4) is separately marked NOT-RUN in REPORT.md and requires Besu-side blockreward-transition coordination (Group F, also NOT-RUN this round).";

  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-Fork-L1-L3-ratepath-FINAL-script-output.json"), JSON.stringify(out, null, 2));
  console.log("\nWrote evidence file.");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
