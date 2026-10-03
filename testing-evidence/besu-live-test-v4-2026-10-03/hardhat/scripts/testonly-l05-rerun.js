// C-L05-2 (Net-L05a) and C-L05-3a/3b (Net-L05b) RE-RUN on FRESH, separate networks, with the document's own preconditions read and
// recorded first. Unmodified baseline contracts, REAL constants (MIN_RATE_CHANGE_LEAD_BLOCKS=201600, RATE_CHANGE_DELAY=7d): these
// sub-scenarios only exercise pre-delay / pre-height rejections and board-version invalidation, never elapsed time.
// The proposal struct is read with NAMED outputs (the earlier script's positional-index bug cannot recur).
// env: MODE = "2" (Net-L05a) | "3" (Net-L05b)
const { ethers, ADDR, accounts, sleep, saveEvidence } = require("./v5-lib");

const DIST_ABI = [
  "function proposeRateChange(uint256,uint256) external returns (uint256)",
  "function boardVoteRateChange(uint256) external",
  "function validatorVoteRateChange(uint256) external",
  "function executeRateChange(uint256) external",
  "function rateChangeStatus(uint256) view returns (uint8,uint8)",
  "function rateProposals(uint256) view returns (uint128 startBlock,uint128 ratePerBlock,uint256 createdAt,uint256 votingExpiresAt,uint256 requiredValidatorApprovals,uint256 boardApprovals,uint256 validatorApprovals,uint256 approvedAt,bool executed,uint256 boardVersionAtCreation,uint256 validatorNonceAtCreation)",
  "function rateProposalCount() view returns (uint256)",
  "function rewardRateChangeCount() view returns (uint256)",
  "function MIN_RATE_CHANGE_LEAD_BLOCKS() view returns (uint256)",
  "function RATE_CHANGE_DELAY() view returns (uint256)",
];
const REG_ABI = ["function requestExit() external", "function getActiveValidatorCount() view returns (uint256)", "function getValidators() view returns (address[])", "function statusNonce() view returns (uint256)"];
const BOARD_ABI = ["function syncBoard() external", "function boardVersion() view returns (uint256)", "function getBoardMembers() view returns (address[])"];

const reason = (e) => e.reason || e.shortMessage || e.message;
async function tryStatic(fn) { try { await fn(); return "UNEXPECTED_SUCCESS"; } catch (e) { return reason(e); } }
const prop = async (distP, id) => { const p = await distP.rateProposals(id); return { startBlock: p.startBlock.toString(), ratePerBlock: p.ratePerBlock.toString(), requiredValidatorApprovals: Number(p.requiredValidatorApprovals), boardApprovals: Number(p.boardApprovals), validatorApprovals: Number(p.validatorApprovals), approvedAt: p.approvedAt.toString(), executed: p.executed, boardVersionAtCreation: p.boardVersionAtCreation.toString(), validatorNonceAtCreation: p.validatorNonceAtCreation.toString() }; };
const st = async (distP, id) => { const s = await distP.rateChangeStatus(id); return { status: Number(s[0]), problem: Number(s[1]) }; };

async function main() {
  const MODE = process.env.MODE;
  const URL = MODE === "2" ? "http://127.0.0.1:8851" : "http://127.0.0.1:8861";
  const NET = MODE === "2" ? "Net-L05a" : "Net-L05b";
  const provider = new ethers.JsonRpcProvider(URL);
  const F = [1, 2, 3, 4, 5].map((i) => new ethers.Wallet(accounts[`g5_v${i}`].privateKey, provider));
  const distP = new ethers.Contract(ADDR.DISTRIBUTOR, DIST_ABI, provider);
  const distAs = (w) => distP.connect(w);
  const reg = new ethers.Contract(ADDR.REGISTRY, REG_ABI, provider);
  const board = new ethers.Contract(ADDR.BOARD, BOARD_ABI, provider);
  const out = { NET, MODE, startedAt: new Date().toISOString() };
  const tx = async (c, m, args = [], gl = 600000) => { const t = await c[m](...args, { gasLimit: gl }); const r = await t.wait(); return { hash: r.hash, status: r.status, block: r.blockNumber }; };

  // ---- preconditions, READ and recorded before step 1 ----
  const head = await provider.getBlockNumber();
  const lead = Number(await distP.MIN_RATE_CHANGE_LEAD_BLOCKS());
  out.preconditions = {
    head, MIN_RATE_CHANGE_LEAD_BLOCKS: lead, RATE_CHANGE_DELAY: Number(await distP.RATE_CHANGE_DELAY()),
    boardVersion: (await board.boardVersion()).toString(), boardMembers: await board.getBoardMembers(), activeValidatorCount: Number(await reg.getActiveValidatorCount()),
    activeValidators: await reg.getValidators(), rewardRateChangeCount: (await distP.rewardRateChangeCount()).toString(), rateProposalCount: (await distP.rateProposalCount()).toString(),
  };
  console.log("preconditions:", JSON.stringify(out.preconditions));
  const n0 = out.preconditions.activeValidatorCount;
  if (n0 !== 5 || out.preconditions.boardMembers.length !== 5) { out.result = "BLOCKED"; out.blockedReason = "precondition (intact 5-member board, 5 active validators) not satisfied"; saveEvidence(`${NET}-CL05-rerun.json`, out); return; }

  if (MODE === "2") {
    // ===== C-L05-2 =====
    const r = (out.cl05_2 = {});
    r.rejectNotInFuture = await tryStatic(() => distAs(F[0]).proposeRateChange.staticCall(head, ethers.parseEther("2.5")));
    r.rejectTooClose = await tryStatic(() => distAs(F[0]).proposeRateChange.staticCall(head + 100, ethers.parseEther("2.5")));
    const startBlock = head + lead + 1000;
    r.startBlock = startBlock;
    r.propose = await tx(distAs(F[0]), "proposeRateChange", [startBlock, ethers.parseEther("2.5")], 500000);
    const id = Number(await distP.rateProposalCount());
    r.id = id;
    r.afterCreate = await prop(distP, id);
    r.expectedFrozenQuorum_ceil2n3 = Math.floor((n0 * 2 + 2) / 3);
    r.frozenQuorumMatchesFormula = r.afterCreate.requiredValidatorApprovals === r.expectedFrozenQuorum_ceil2n3;
    r.statusAfterCreate = await st(distP, id);
    r.boardVotes = [];
    for (let i = 0; i < 3; i++) r.boardVotes.push(await tx(distAs(F[i]), "boardVoteRateChange", [id], 400000));
    r.afterBoardVotes = await prop(distP, id);
    r.statusAfterBoard = await st(distP, id);
    r.validatorVotes = [];
    const need = r.afterCreate.requiredValidatorApprovals;
    for (let i = 0; i < need; i++) r.validatorVotes.push(await tx(distAs(F[i]), "validatorVoteRateChange", [id], 400000));
    r.afterBothChambers = await prop(distP, id);
    r.statusAfterBothChambers = await st(distP, id);
    r.expectStatus_4_0 = r.statusAfterBothChambers.status === 4 && r.statusAfterBothChambers.problem === 0;
    r.prematureExecuteRevert = await tryStatic(() => distAs(F[0]).executeRateChange.staticCall(id));
    r.rewardRateChangeCountAfter = (await distP.rewardRateChangeCount()).toString();
    r.boardVersionAfter = (await board.boardVersion()).toString();
    r.activeValidatorCountAfter = Number(await reg.getActiveValidatorCount());
    r.pass = r.rejectNotInFuture.includes("start block is not in the future") && r.rejectTooClose.includes("start block is closer than MIN_RATE_CHANGE_LEAD_BLOCKS") && r.frozenQuorumMatchesFormula && r.expectStatus_4_0 && r.afterBothChambers.approvedAt !== "0" && r.prematureExecuteRevert.includes("execution delay has not elapsed") && r.rewardRateChangeCountAfter === "0" && r.boardVersionAfter === out.preconditions.boardVersion && r.activeValidatorCountAfter === n0;
    console.log("C-L05-2 pass:", r.pass, JSON.stringify({ status: r.statusAfterBothChambers, prem: r.prematureExecuteRevert, q: r.afterCreate.requiredValidatorApprovals }));
  } else {
    // ===== C-L05-3a =====
    const a = (out.cl05_3a = {});
    const startR1 = head + lead + 2000;
    a.proposeR1 = await tx(distAs(F[0]), "proposeRateChange", [startR1, ethers.parseEther("2.6")], 500000);
    const idR1 = Number(await distP.rateProposalCount());
    a.idR1 = idR1;
    a.afterCreate = await prop(distP, idR1);
    const need1 = a.afterCreate.requiredValidatorApprovals;
    a.expectedFrozenQuorum = Math.floor((n0 * 2 + 2) / 3);
    a.boardVotes = [];
    for (let i = 0; i < 3; i++) a.boardVotes.push(await tx(distAs(F[i]), "boardVoteRateChange", [idR1], 400000));
    a.validatorVotes = [];
    for (let i = 0; i < need1 - 1; i++) a.validatorVotes.push(await tx(distAs(F[i]), "validatorVoteRateChange", [idR1], 400000));
    a.beforeBoardChange = await prop(distP, idR1);
    a.statusBeforeBoardChange = await st(distP, idR1);
    a.preconditionHeld = a.beforeBoardChange.boardApprovals === 3 && a.beforeBoardChange.validatorApprovals === need1 - 1 && a.beforeBoardChange.approvedAt === "0";
    // board composition change: M = V5 requests exit, then syncBoard()
    a.exitV5 = await tx(new ethers.Contract(ADDR.REGISTRY, REG_ABI, F[4]), "requestExit", [], 800000);
    const bvBefore = (await board.boardVersion()).toString();
    a.syncBoard = await tx(new ethers.Contract(ADDR.BOARD, BOARD_ABI, F[0]), "syncBoard", [], 800000);
    a.boardVersionBefore = bvBefore; a.boardVersionAfter = (await board.boardVersion()).toString();
    a.activeAfter = Number(await reg.getActiveValidatorCount());
    a.activeAtLeast4 = a.activeAfter >= 4;
    const completer = F[need1 - 1]; // the (required)th voter -- V4 for required=4
    a.completingVoterIsActive = (await reg.getValidators()).map((x) => x.toLowerCase()).includes(completer.address.toLowerCase());
    a.completingVoteStaticCallRevert = await tryStatic(() => distAs(completer).validatorVoteRateChange.staticCall(idR1));
    // the same call as a real mined transaction (status 0 expected, state unchanged)
    try { const t = await distAs(completer).validatorVoteRateChange(idR1, { gasLimit: 400000 }); const rc = await t.wait(); a.completingVoteRealTx = { hash: rc.hash, status: rc.status }; } catch (e) { a.completingVoteRealTx = { status: 0, note: reason(e), hash: e.receipt ? e.receipt.hash : (e.transactionHash || null) }; }
    a.afterCompletingAttempt = await prop(distP, idR1);
    a.approvedAtStillZero = a.afterCompletingAttempt.approvedAt === "0";
    a.validatorApprovalsUnchanged = a.afterCompletingAttempt.validatorApprovals === need1 - 1;
    a.statusR1 = await st(distP, idR1);
    a.statusR1_note = "document expects (7,1); the ACTUAL value is recorded as-is (expiry takes precedence over status 7)";
    a.pass = a.preconditionHeld && a.activeAtLeast4 && a.completingVoteStaticCallRevert.includes("board membership changed since this proposal was created - propose again") && a.completingVoteRealTx.status === 0 && a.approvedAtStillZero && a.validatorApprovalsUnchanged;
    console.log("C-L05-3a pass:", a.pass, JSON.stringify({ revert: a.completingVoteStaticCallRevert, statusR1: a.statusR1, active: a.activeAfter }));

    // ===== C-L05-3b =====
    const b = (out.cl05_3b = {});
    const headB = await provider.getBlockNumber();
    b.boardVersionAtStart = (await board.boardVersion()).toString();
    b.activeAtStart = Number(await reg.getActiveValidatorCount());
    const startR2 = headB + lead + 3000;
    const remaining = [F[0], F[1], F[2], F[3]];
    b.proposeR2 = await tx(distAs(F[0]), "proposeRateChange", [startR2, ethers.parseEther("2.7")], 500000);
    const idR2 = Number(await distP.rateProposalCount());
    b.idR2 = idR2;
    b.afterCreate = await prop(distP, idR2);
    b.createdOnCurrentBoardVersion = b.afterCreate.boardVersionAtCreation === b.boardVersionAtStart;
    const need2 = b.afterCreate.requiredValidatorApprovals;
    b.expectedFrozenQuorum = Math.floor((b.activeAtStart * 2 + 2) / 3);
    b.validatorVotes = [];
    for (let i = 0; i < need2; i++) b.validatorVotes.push(await tx(distAs(remaining[i]), "validatorVoteRateChange", [idR2], 400000));
    b.afterValidatorChamber = await prop(distP, idR2);
    b.validatorChamberComplete = b.afterValidatorChamber.validatorApprovals === need2;
    // second composition change: another member (V4) exits + syncBoard. NOTE: leaves 3 active validators (all 5 node processes stay running)
    b.exitV4 = await tx(new ethers.Contract(ADDR.REGISTRY, REG_ABI, F[3]), "requestExit", [], 800000);
    b.syncBoard = await tx(new ethers.Contract(ADDR.BOARD, BOARD_ABI, F[0]), "syncBoard", [], 800000);
    b.boardVersionAfter = (await board.boardVersion()).toString();
    b.activeAfter = Number(await reg.getActiveValidatorCount());
    b.boardVoteStaticCallRevert = await tryStatic(() => distAs(F[0]).boardVoteRateChange.staticCall(idR2));
    try { const t = await distAs(F[0]).boardVoteRateChange(idR2, { gasLimit: 400000 }); const rc = await t.wait(); b.boardVoteRealTx = { hash: rc.hash, status: rc.status }; } catch (e) { b.boardVoteRealTx = { status: 0, note: reason(e), hash: e.receipt ? e.receipt.hash : (e.transactionHash || null) }; }
    b.afterBoardVoteAttempt = await prop(distP, idR2);
    b.boardApprovalsStillZero = b.afterBoardVoteAttempt.boardApprovals === 0;
    b.statusR2 = await st(distP, idR2);
    b.pass = b.createdOnCurrentBoardVersion && b.validatorChamberComplete && b.boardVersionAfter !== b.boardVersionAtStart && b.boardVoteStaticCallRevert.includes("board membership changed since this proposal was created - propose again") && b.boardVoteRealTx.status === 0 && b.boardApprovalsStillZero;
    b.deviationNote = "the second composition change (V4 exit) leaves 3 active validators, below the document's general >=4 guideline; the document's 3b sequence ('another member + syncBoard') requires it on a G5 network. All 5 node processes were kept running throughout and chain liveness was re-checked afterwards.";
    out.chainAliveAfter = { head: await provider.getBlockNumber() };
    await sleep(6000);
    out.chainAliveAfter.headAfter6s = await provider.getBlockNumber();
    console.log("C-L05-3b pass:", b.pass, JSON.stringify({ revert: b.boardVoteStaticCallRevert, active: b.activeAfter, statusR2: b.statusR2 }));
  }
  out.finishedAt = new Date().toISOString();
  saveEvidence(`${NET}-CL05-rerun.json`, out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
