// C-L01 full sequence on Net-L01: proposals A(5500)/B(5200)/C(5800) built BEFORE any execution;
// A executes (2 board votes insufficient, 3rd executes); B's completing VALIDATOR vote must
// revert (board already passed); C's completing BOARD vote must revert (validators already
// passed); then C-L01-3: a fresh proposal is rejected at creation time.
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const RPC = "http://127.0.0.1:8711";
const DISTRIBUTOR = "0x2222222222222222222222222222222222222222";
const REGISTRY = "0x3333333333333333333333333333333333333333";

const DIST_ABI = [
  "function proposeShareChange(uint256) external returns (uint256)",
  "function boardVoteShareChange(uint256) external",
  "function validatorVoteShareChange(uint256) external",
  "function shareProposals(uint256) view returns (uint256 newValidatorShareBps,uint256 createdAt,uint256 expiresAt,uint256 requiredValidatorApprovals,uint256 boardApprovals,uint256 validatorApprovals,bool boardPassed,bool validatorPassed,bool executed,uint256 boardVersionAtCreation,uint256 validatorNonceAtCreation)",
  "function lastShareChangeTime() view returns (uint256)",
  "function validatorDirectShareBps() view returns (uint256)",
  "function shareProposalCount() view returns (uint256)",
];
const REG_ABI = ["function getActiveValidatorCount() view returns (uint256)"];

function snap(p) {
  return { newValidatorShareBps: p[0].toString(), createdAt: p[1].toString(), expiresAt: p[2].toString(), requiredValidatorApprovals: p[3].toString(), boardApprovals: p[4].toString(), validatorApprovals: p[5].toString(), boardPassed: p[6], validatorPassed: p[7], executed: p[8], boardVersionAtCreation: p[9].toString(), validatorNonceAtCreation: p[10].toString() };
}

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const founders = [1, 2, 3, 4, 5].map((i) => new ethers.Wallet(accounts[`g5_v${i}`].privateKey, provider));
  const registry = new ethers.Contract(REGISTRY, REG_ABI, provider);
  const n = await registry.getActiveValidatorCount();
  console.log("active validator count (n):", n.toString(), "expected requiredValidatorApprovals = (n*2+2)/3 =", (Number(n) * 2 + 2) / 3 | 0);

  const distAsV1 = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[0]);
  const out = {};

  // --- Build A, B, C before any execution ---
  out.proposals = {};
  for (const [label, bps] of [["A", 5500], ["B", 5200], ["C", 5800]]) {
    const tx = await distAsV1.proposeShareChange(bps, { gasLimit: 400000 });
    const rcpt = await tx.wait();
    const id = await distAsV1.shareProposalCount();
    out.proposals[label] = { id: id.toString(), bps, txHash: rcpt.hash, status: rcpt.status };
    console.log(`Proposal ${label} (${bps}bps) created, id=${id}`);
  }
  const idA = Number(out.proposals.A.id), idB = Number(out.proposals.B.id), idC = Number(out.proposals.C.id);

  const distP = new ethers.Contract(DISTRIBUTOR, DIST_ABI, provider);
  for (const [label, id] of [["A", idA], ["B", idB], ["C", idC]]) {
    const p = await distP.shareProposals(id);
    out.proposals[label].requiredValidatorApprovals = p[3].toString();
    if (p[3].toString() !== String((Number(n) * 2 + 2) / 3 | 0)) console.log(`WARNING: ${label} requiredValidatorApprovals mismatch!`);
  }

  // === C-L01-1: execute A ===
  // validator chamber complete (all 5, well over required 4), THEN board votes 1,2 (no exec), 3rd executes.
  out.cl01_1 = { validatorVotes: [], boardVotes: [] };
  for (let i = 0; i < founders.length; i++) {
    const distV = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    const tx = await distV.validatorVoteShareChange(idA, { gasLimit: 300000 });
    const rcpt = await tx.wait();
    out.cl01_1.validatorVotes.push({ voter: founders[i].address, status: rcpt.status });
  }
  for (let i = 0; i < 3; i++) {
    const distV = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    const tx = await distV.boardVoteShareChange(idA, { gasLimit: 300000 });
    const rcpt = await tx.wait();
    const pAfter = await distP.shareProposals(idA);
    out.cl01_1.boardVotes.push({ voter: founders[i].address, status: rcpt.status, executedAfter: pAfter[8] });
  }
  out.cl01_1.proposalA_final = snap(await distP.shareProposals(idA));
  out.cl01_1.validatorDirectShareBps_after = (await distP.validatorDirectShareBps()).toString();
  out.cl01_1.lastShareChangeTime_after = (await distP.lastShareChangeTime()).toString();
  console.log("\n=== C-L01-1 ===", JSON.stringify(out.cl01_1, null, 2));

  // === C-L01-2a: B gets board pass (3 votes) + required-1 validator votes, then completing vote reverts ===
  for (let i = 0; i < 3; i++) {
    const distV = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await distV.boardVoteShareChange(idB, { gasLimit: 300000 })).wait();
  }
  const requiredB = Number((await distP.shareProposals(idB))[3]);
  for (let i = 0; i < requiredB - 1; i++) {
    const distV = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await distV.validatorVoteShareChange(idB, { gasLimit: 300000 })).wait();
  }
  const snapBeforeCompletingVote = snap(await distP.shareProposals(idB));
  let cl01_2a_revert;
  try {
    const distV = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[requiredB - 1]);
    const tx = await distV.validatorVoteShareChange(idB, { gasLimit: 500000 });
    const rcpt = await tx.wait();
    cl01_2a_revert = { unexpectedSuccess: true, status: rcpt.status };
  } catch (err) {
    cl01_2a_revert = { revertReason: err.reason || err.shortMessage || err.message };
  }
  const snapAfterCompletingVote = snap(await distP.shareProposals(idB));
  out.cl01_2a = { requiredB, snapBeforeCompletingVote, completingVoteAttempt: cl01_2a_revert, snapAfterCompletingVote, stateUnchanged: JSON.stringify(snapBeforeCompletingVote) === JSON.stringify(snapAfterCompletingVote) };
  console.log("\n=== C-L01-2a ===", JSON.stringify(out.cl01_2a, null, 2));

  // === C-L01-2b: C gets validator chamber complete first, then 2 board votes, 3rd (completing) reverts ===
  for (let i = 0; i < founders.length; i++) {
    const distV = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await distV.validatorVoteShareChange(idC, { gasLimit: 300000 })).wait();
  }
  for (let i = 0; i < 2; i++) {
    const distV = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    await (await distV.boardVoteShareChange(idC, { gasLimit: 300000 })).wait();
  }
  const snapBeforeC = snap(await distP.shareProposals(idC));
  let cl01_2b_revert;
  try {
    const distV = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[2]);
    const tx = await distV.boardVoteShareChange(idC, { gasLimit: 500000 });
    const rcpt = await tx.wait();
    cl01_2b_revert = { unexpectedSuccess: true, status: rcpt.status };
  } catch (err) {
    cl01_2b_revert = { revertReason: err.reason || err.shortMessage || err.message };
  }
  const snapAfterC = snap(await distP.shareProposals(idC));
  out.cl01_2b = { snapBeforeC, completingVoteAttempt: cl01_2b_revert, snapAfterC, stateUnchanged: JSON.stringify(snapBeforeC) === JSON.stringify(snapAfterC) };
  console.log("\n=== C-L01-2b ===", JSON.stringify(out.cl01_2b, null, 2));

  // === C-L01-3: fresh proposal rejected at creation ===
  const countBefore = await distP.shareProposalCount();
  let cl01_3;
  try {
    const tx = await distAsV1.proposeShareChange(5300, { gasLimit: 400000 });
    const rcpt = await tx.wait();
    cl01_3 = { unexpectedSuccess: true, status: rcpt.status };
  } catch (err) {
    cl01_3 = { revertReason: err.reason || err.shortMessage || err.message };
  }
  const countAfter = await distP.shareProposalCount();
  out.cl01_3 = { countBefore: countBefore.toString(), attempt: cl01_3, countAfter: countAfter.toString(), countUnchanged: countBefore.toString() === countAfter.toString() };
  console.log("\n=== C-L01-3 ===", JSON.stringify(out.cl01_3, null, 2));

  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-L01-CL01.json"), JSON.stringify(out, null, 2));
  console.log("\nWrote evidence file.");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
