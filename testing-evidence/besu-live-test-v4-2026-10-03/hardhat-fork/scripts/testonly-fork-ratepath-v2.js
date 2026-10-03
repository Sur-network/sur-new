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
  "function rateProposals(uint256) view returns (uint128 startBlock,uint128 ratePerBlock,uint256 createdAt,uint256 votingExpiresAt,uint256 requiredValidatorApprovals,uint256 boardApprovals,uint256 validatorApprovals,uint256 approvedAt,bool executed,uint256 boardVersionAtCreation,uint256 validatorNonceAtCreation)",
  "function rewardRateChangeCount() view returns (uint256)",
  "function rewardRateChanges(uint256) view returns (uint128,uint128)",
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

  const leadBlocks = Number(await distP.MIN_RATE_CHANGE_LEAD_BLOCKS());
  const rateChangeDelay = Number(await distP.RATE_CHANGE_DELAY());
  const currentBlock = await provider.getBlockNumber();
  // margin must cover: blocks produced during the RATE_CHANGE_DELAY wait (~delay/3s) + leadBlocks + buffer
  const blocksduringDelay = Math.ceil(rateChangeDelay / 3);
  const startBlock = currentBlock + blocksduringDelay + leadBlocks + 30;
  console.log("currentBlock:", currentBlock, "leadBlocks:", leadBlocks, "delay:", rateChangeDelay, "blocksDuringDelay:", blocksduringDelay, "startBlock:", startBlock);

  const proposeTx = await distV1.proposeRateChange(startBlock, ethers.parseEther("3.3"), { gasLimit: 400000 });
  const proposeRcpt = await proposeTx.wait();
  const id = Number(await distP.rateProposalCount());
  out.propose = { txHash: proposeRcpt.hash, status: proposeRcpt.status, id, startBlock, ratePerBlock: ethers.parseEther("3.3").toString() };

  for (let i = 0; i < 3; i++) {
    const d = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await d.boardVoteRateChange(id, { gasLimit: 300000 })).wait();
  }
  const required = Number((await distP.rateProposals(id))[4]); // correct index now
  console.log("requiredValidatorApprovals:", required);
  for (let i = 0; i < required; i++) {
    const d = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await d.validatorVoteRateChange(id, { gasLimit: 300000 })).wait();
  }
  const afterVotes = await distP.rateProposals(id);
  const statusAfterVotes = await distP.rateChangeStatus(id);
  out.L1 = { requiredValidatorApprovals: required, boardApprovals: afterVotes[5].toString(), validatorApprovals: afterVotes[6].toString(), approvedAt: afterVotes[7].toString(), statusAfterVotes: { status: Number(statusAfterVotes[0]), problem: Number(statusAfterVotes[1]) } };
  console.log("=== L1 ===", JSON.stringify(out.L1, null, 2));

  try {
    await distV1.executeRateChange.staticCall(id);
    out.L1.prematureExecute = "UNEXPECTED_SUCCESS";
  } catch (err) {
    out.L1.prematureExecute = err.reason || err.message;
  }

  console.log(`\nWaiting ${rateChangeDelay}s for RATE_CHANGE_DELAY...`);
  await new Promise((r) => setTimeout(r, (rateChangeDelay + 5) * 1000));

  const statusAfterDelay = await distP.rateChangeStatus(id);
  const blockNow = await provider.getBlockNumber();
  out.L2 = { statusAfterDelay: { status: Number(statusAfterDelay[0]), problem: Number(statusAfterDelay[1]) }, blockNow, startBlock, margin: startBlock - blockNow };
  console.log("=== L2 ===", JSON.stringify(out.L2, null, 2));

  const execTx = await distV1.executeRateChange(id, { gasLimit: 400000 });
  const execRcpt = await execTx.wait();
  const historyCount = await distP.rewardRateChangeCount();
  const lastEntry = await distP.rewardRateChanges(Number(historyCount) - 1);
  out.L3_execute = { txHash: execRcpt.hash, status: execRcpt.status, historyCount: historyCount.toString(), lastEntry: { startBlock: lastEntry[0].toString(), ratePerBlock: lastEntry[1].toString() } };
  console.log("\n=== L3 (executed) ===", JSON.stringify(out.L3_execute, null, 2));

  out.note = "L4's Besu-side blockreward-transition coordination at startBlock is covered separately by Group F (F01-F04) using seeded history.";
  out.priorAttemptNote = "A prior attempt (proposal id=1) used an insufficient startBlock margin (did not account for blocks produced during the RATE_CHANGE_DELAY wait) and a WRONG RateProposal struct field order in the script's ABI -- both script bugs, not contract bugs. Superseded by this corrected run (proposal id=" + id + ").";

  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-Fork-L1-L3-ratepath-v2.json"), JSON.stringify(out, null, 2));
  console.log("\nWrote evidence file.");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
