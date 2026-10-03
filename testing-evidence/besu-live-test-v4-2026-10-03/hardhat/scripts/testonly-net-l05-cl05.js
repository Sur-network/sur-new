// C-L05-2 (board intact) + C-L05-3a/3b (board composition changes mid-vote) on Net-L05 (baseline
// code, real MIN_RATE_CHANGE_LEAD_BLOCKS=201600 and RATE_CHANGE_DELAY=7 days — these specific
// sub-scenarios only test PRE-delay/PRE-height rejections and board-version invalidation, never
// actual elapsed-time effectiveness, so the real (uncompressed) constants are fine here).
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const RPC = "http://127.0.0.1:8741";
const DISTRIBUTOR = "0x2222222222222222222222222222222222222222";
const REGISTRY = "0x3333333333333333333333333333333333333333";
const BOARD = "0x4444444444444444444444444444444444444444";

const DIST_ABI = [
  "function proposeRateChange(uint256,uint256) external returns (uint256)",
  "function boardVoteRateChange(uint256) external",
  "function validatorVoteRateChange(uint256) external",
  "function executeRateChange(uint256) external",
  "function rateChangeStatus(uint256) view returns (uint8,uint8)",
  "function rateProposals(uint256) view returns (uint128,uint128,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint256,uint256)",
  "function rateProposalCount() view returns (uint256)",
];
const REG_ABI = ["function requestExit() external", "function getActiveValidatorCount() view returns (uint256)"];
const BOARD_ABI = ["function syncBoard() external", "function boardVersion() view returns (uint256)"];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const founders = [1, 2, 3, 4, 5].map((i) => new ethers.Wallet(accounts[`g5_v${i}`].privateKey, provider));
  const [V1, V2, V3, V4, V5] = founders;
  const distV1 = new ethers.Contract(DISTRIBUTOR, DIST_ABI, V1);
  const distP = new ethers.Contract(DISTRIBUTOR, DIST_ABI, provider);
  const out = {};

  // === C-L05-2 ===
  const currentBlock = await provider.getBlockNumber();
  const leadBlocks = 201600;
  const startBlockGood = currentBlock + leadBlocks + 1000;
  out.cl05_2 = {};

  // negative: start block not in future
  try { await distV1.proposeRateChange.staticCall(currentBlock, ethers.parseEther("2.5")); out.cl05_2.notInFuture = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl05_2.notInFuture = e.reason || e.message; }
  // negative: closer than lead blocks
  try { await distV1.proposeRateChange.staticCall(currentBlock + 100, ethers.parseEther("2.5")); out.cl05_2.tooClose = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl05_2.tooClose = e.reason || e.message; }

  const proposeTx = await distV1.proposeRateChange(startBlockGood, ethers.parseEther("2.5"), { gasLimit: 400000 });
  await proposeTx.wait();
  const idR = Number(await distP.rateProposalCount());
  out.cl05_2.idR = idR;

  for (let i = 0; i < 3; i++) {
    const d = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await d.boardVoteRateChange(idR, { gasLimit: 300000 })).wait();
  }
  const requiredR = Number((await distP.rateProposals(idR))[5]);
  for (let i = 0; i < requiredR; i++) {
    const d = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await d.validatorVoteRateChange(idR, { gasLimit: 300000 })).wait();
  }
  const statusR = await distP.rateChangeStatus(idR);
  out.cl05_2.statusAfterBothChambers = { status: Number(statusR[0]), problem: Number(statusR[1]) };
  try { await distV1.executeRateChange.staticCall(idR); out.cl05_2.prematureExecute = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl05_2.prematureExecute = e.reason || e.message; }
  console.log("=== C-L05-2 ===", JSON.stringify(out.cl05_2, null, 2));

  // === C-L05-3a ===
  const startBlockR1 = currentBlock + leadBlocks + 2000;
  const r1Tx = await distV1.proposeRateChange(startBlockR1, ethers.parseEther("2.6"), { gasLimit: 400000 });
  await r1Tx.wait();
  const idR1 = Number(await distP.rateProposalCount());
  for (let i = 0; i < 3; i++) {
    const d = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await d.boardVoteRateChange(idR1, { gasLimit: 300000 })).wait();
  }
  const requiredR1 = Number((await distP.rateProposals(idR1))[5]);
  for (let i = 0; i < requiredR1 - 1; i++) {
    const d = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await d.validatorVoteRateChange(idR1, { gasLimit: 300000 })).wait();
  }
  // board composition changes: M(V5) exits + syncBoard
  const regV5 = new ethers.Contract(REGISTRY, REG_ABI, V5);
  await (await regV5.requestExit({ gasLimit: 600000 })).wait();
  const boardV1 = new ethers.Contract(BOARD, BOARD_ABI, V1);
  await (await boardV1.syncBoard({ gasLimit: 600000 })).wait();
  const activeAfterV5Exit = await new ethers.Contract(REGISTRY, REG_ABI, provider).getActiveValidatorCount();

  const distCompleting = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[requiredR1 - 1]);
  try { await distCompleting.validatorVoteRateChange.staticCall(idR1); out.cl05_3a_completingVote = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl05_3a_completingVote = e.reason || e.message; }
  const statusR1 = await distP.rateChangeStatus(idR1);
  out.cl05_3a = { activeAfterV5Exit: activeAfterV5Exit.toString(), completingVoteAttempt: out.cl05_3a_completingVote, statusR1: { status: Number(statusR1[0]), problem: Number(statusR1[1]) }, approvedAt: (await distP.rateProposals(idR1))[4].toString() };
  console.log("\n=== C-L05-3a ===", JSON.stringify(out.cl05_3a, null, 2));

  // === C-L05-3b ===
  const startBlockR2 = currentBlock + leadBlocks + 3000;
  const r2Tx = await distV1.proposeRateChange(startBlockR2, ethers.parseEther("2.7"), { gasLimit: 400000 });
  await r2Tx.wait();
  const idR2 = Number(await distP.rateProposalCount());
  const remainingFounders = [V1, V2, V3, V4]; // V5 exited
  const requiredR2 = Number((await distP.rateProposals(idR2))[5]);
  for (let i = 0; i < requiredR2; i++) {
    const d = new ethers.Contract(DISTRIBUTOR, DIST_ABI, remainingFounders[i]);
    await (await d.validatorVoteRateChange(idR2, { gasLimit: 300000 })).wait();
  }
  // board changes AGAIN: V4 exits + syncBoard (active must stay >= ? doc allows down to whatever; we accept the dip)
  const regV4b = new ethers.Contract(REGISTRY, REG_ABI, V4);
  await (await regV4b.requestExit({ gasLimit: 600000 })).wait();
  await (await boardV1.syncBoard({ gasLimit: 600000 })).wait();
  const activeAfterV4Exit = await new ethers.Contract(REGISTRY, REG_ABI, provider).getActiveValidatorCount();

  const boardVoterV1 = new ethers.Contract(DISTRIBUTOR, DIST_ABI, V1);
  try { await boardVoterV1.boardVoteRateChange.staticCall(idR2); out.cl05_3b_boardVote = "UNEXPECTED_SUCCESS"; } catch (e) { out.cl05_3b_boardVote = e.reason || e.message; }
  out.cl05_3b = { idR2, activeAfterV4Exit: activeAfterV4Exit.toString(), boardVoteAttempt: out.cl05_3b_boardVote };
  console.log("\n=== C-L05-3b ===", JSON.stringify(out.cl05_3b, null, 2));

  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-L05-CL05.json"), JSON.stringify(out, null, 2));
  console.log("\nWrote evidence file.");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
