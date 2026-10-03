// C-L02 on Net-L02: board member M requestExit()s (loses live authority immediately, P02), but
// syncBoard() not yet called (isBoardMember(M) still true). M's vote rejected; 2 others succeed.
// Then syncBoard() -> boardVersion bumps -> a remaining member's vote on the OLD proposal rejected
// with the board-changed message; a fresh proposal P2 (post-sync) is votable (positive control).
const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const RPC = "http://127.0.0.1:8721";
const DISTRIBUTOR = "0x2222222222222222222222222222222222222222";
const REGISTRY = "0x3333333333333333333333333333333333333333";
const BOARD = "0x4444444444444444444444444444444444444444";

const DIST_ABI = ["function proposeShareChange(uint256) external returns (uint256)", "function boardVoteShareChange(uint256) external", "function shareProposals(uint256) view returns (uint256,uint256,uint256,uint256,uint256,uint256,bool,bool,bool,uint256,uint256)"];
const REG_ABI = ["function requestExit() external", "function getActiveValidatorCount() view returns (uint256)"];
const BOARD_ABI = ["function hasBoardAuthority(address) view returns (bool)", "function isBoardMember(address) view returns (bool)", "function syncBoard() external", "function boardVersion() view returns (uint256)", "function getBoardMembers() view returns (address[])"];

async function main() {
  const provider = new ethers.JsonRpcProvider(RPC);
  const founders = [1, 2, 3, 4, 5].map((i) => new ethers.Wallet(accounts[`g5_v${i}`].privateKey, provider));
  const M = founders[4]; // V5
  const board = new ethers.Contract(BOARD, BOARD_ABI, provider);
  const out = {};

  out.pre = { boardVersion: (await board.boardVersion()).toString(), activeCount: (await new ethers.Contract(REGISTRY, REG_ABI, provider).getActiveValidatorCount()).toString() };

  // Build proposal P (on validatorDirectShareBps, reusing the share-change mechanism) BEFORE M exits.
  const distV1 = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[0]);
  const txP = await distV1.proposeShareChange(6000, { gasLimit: 400000 });
  await txP.wait();
  const distP = new ethers.Contract(DISTRIBUTOR, DIST_ABI, provider);
  const countP = await distP.shareProposals ? null : null;
  // shareProposalCount isn't in ABI here; read via a side call
  const distFull = new ethers.Contract(DISTRIBUTOR, [...DIST_ABI, "function shareProposalCount() view returns (uint256)"], provider);
  const idP = Number(await distFull.shareProposalCount());
  out.proposalP_id = idP;

  // M requestExit()
  const registryM = new ethers.Contract(REGISTRY, REG_ABI, M);
  const exitTx = await registryM.requestExit({ gasLimit: 600000 });
  const exitRcpt = await exitTx.wait();
  out.cl02_1 = { exitTxHash: exitRcpt.hash, exitStatus: exitRcpt.status };
  out.cl02_1.hasBoardAuthority_M_afterExit = await board.hasBoardAuthority(M.address);
  out.cl02_1.isBoardMember_M_afterExit = await board.isBoardMember(M.address);

  // M's vote should be rejected
  const distM = new ethers.Contract(DISTRIBUTOR, DIST_ABI, M);
  try {
    await distM.boardVoteShareChange.staticCall(idP);
    out.cl02_1.M_vote_result = "UNEXPECTED_SUCCESS";
  } catch (err) {
    out.cl02_1.M_vote_result = err.reason || err.message;
  }

  // 2 other members vote successfully
  out.cl02_1.otherVotes = [];
  for (let i = 0; i < 2; i++) {
    const distV = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[i]);
    const tx = await distV.boardVoteShareChange(idP, { gasLimit: 300000 });
    const rcpt = await tx.wait();
    out.cl02_1.otherVotes.push({ voter: founders[i].address, status: rcpt.status });
  }
  console.log("=== C-L02-1 ===", JSON.stringify(out.cl02_1, null, 2));

  // === C-L02-2: syncBoard(), boardVersion bumps, remaining member's vote on OLD P rejected ===
  const syncTx = await new ethers.Contract(BOARD, BOARD_ABI, founders[0]).syncBoard({ gasLimit: 600000 });
  const syncRcpt = await syncTx.wait();
  const boardVersionAfterSync = await board.boardVersion();
  out.cl02_2 = { syncTxHash: syncRcpt.hash, syncStatus: syncRcpt.status, boardVersionBefore: out.pre.boardVersion, boardVersionAfterSync: boardVersionAfterSync.toString(), bumped: boardVersionAfterSync.toString() !== out.pre.boardVersion };

  const distV3 = new ethers.Contract(DISTRIBUTOR, DIST_ABI, founders[2]);
  try {
    await distV3.boardVoteShareChange.staticCall(idP);
    out.cl02_2.remainingMemberVoteOnOldP = "UNEXPECTED_SUCCESS";
  } catch (err) {
    out.cl02_2.remainingMemberVoteOnOldP = err.reason || err.message;
  }

  // positive control: fresh proposal P2 post-sync IS votable
  const txP2 = await distV1.proposeShareChange(6100, { gasLimit: 400000 });
  await txP2.wait();
  const idP2 = Number(await distFull.shareProposalCount());
  try {
    const tx = await distV3.boardVoteShareChange(idP2, { gasLimit: 300000 });
    const rcpt = await tx.wait();
    out.cl02_2.P2_vote_positive_control = { status: rcpt.status };
  } catch (err) {
    out.cl02_2.P2_vote_positive_control = { error: err.reason || err.message };
  }
  console.log("\n=== C-L02-2 ===", JSON.stringify(out.cl02_2, null, 2));

  fs.mkdirSync(path.join(ROOT, "evidence", "04-results"), { recursive: true });
  fs.writeFileSync(path.join(ROOT, "evidence", "04-results", "Net-L02-CL02.json"), JSON.stringify(out, null, 2));
  console.log("\nWrote evidence file.");
}

main().catch((err) => { console.error(err); process.exitCode = 1; });
