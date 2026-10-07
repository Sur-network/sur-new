// L05 governance — approved reward-rate changes. REAL ValidatorsBoard (live authority + composition version from its own logic) and
// REAL BlockRewardDistributor; Registry/Identity are checkpoint-faithful mocks. Hardhat, not Besu.
// Owner decisions under test: two chambers (board 3 of 5 + two thirds of the validators eligible at creation, L04 snapshot),
// 30-day expiry for the VOTING phase only, 7-day delay from completion of BOTH chambers, 201,600-block minimum distance from the
// executing block to startBlock (a block count, independent of the 7 days), and a full re-check at execution.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const REG = "0x3333333333333333333333333333333333333333", BOARD = "0x4444444444444444444444444444444444444444", IDR = "0x6666666666666666666666666666666666666666", DIST = "0x2222222222222222222222222222222222222222";
let results = [];
function ok(n, c, x = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + n + (c === true ? "" : " → " + c) + (x ? "  " + x : "")); }
const msgOf = e => { const m = e.reason || e.shortMessage || e.message || ""; const r = m.match(/reason string '([^']*)'/); return r ? r[1] : m; };
async function reverts(fn, expected) { try { await (await fn()).wait(); return "did NOT revert"; } catch (e) { return msgOf(e).includes(expected) ? true : "wrong reason: " + msgOf(e).slice(0, 170); } }
async function succeeds(fn) { try { const r = await (await fn()).wait(); return r.status === 1 ? true : "status 0"; } catch (e) { return "reverted: " + msgOf(e).slice(0, 140); } }
const DAY = 86400, LEAD = 201600;
const slotOf = (art, n) => hre.ethers.toBeHex(BigInt(art.layout.storage.find(s => s.label === n).slot));
const setS = (addr, sl, v) => hre.network.provider.send("hardhat_setStorageAt", [addr, sl, hre.ethers.zeroPadValue(hre.ethers.toBeHex(v), 32)]);
const latestTs = async () => (await hre.ethers.provider.getBlock("latest")).timestamp;
const blockNo = () => hre.ethers.provider.getBlockNumber();
const at = async (t, fn) => { await hre.network.provider.send("evm_setNextBlockTimestamp", [t]); return fn(); };
const MOCK = `pragma solidity ^0.8.24;
contract MockRegistry { address[] public vals; mapping(address=>bool) public active; mapping(address=>uint8) public st; mapping(address=>bool) public ever;
 function setActive(address a, bool on) external { if (on && !active[a]) { active[a]=true; ever[a]=true; vals.push(a); _cp(a,true);} else if (!on && active[a]) { active[a]=false; _cp(a,false); for (uint i=0;i<vals.length;i++) if (vals[i]==a) { vals[i]=vals[vals.length-1]; vals.pop(); break; } } }
  uint256 public statusNonce; struct Cp { uint256 n; bool a; } mapping(address=>Cp[]) cps;
  function _cp(address x, bool on) internal { statusNonce++; cps[x].push(Cp(statusNonce, on)); }
  function wasActiveAt(address x, uint256 n) external view returns (bool) { Cp[] storage c=cps[x]; bool r=false; for (uint i=0;i<c.length;i++){ if (c[i].n<=n) r=c[i].a; else break; } return r; }
 function setStatus(address a, uint8 s) external { st[a]=s; }
 function isValidator(address a) external view returns (bool) { return active[a]; }
 function everActivated(address a) external view returns (bool) { return ever[a]; }
 function getActiveValidatorCount() external view returns (uint256) { return vals.length; }
 function getValidators() external view returns (address[] memory) { return vals; }
 function getValidatorInfo(address a) external view returns (uint8,uint256,uint256,uint256,uint256,bool) { return (st[a],0,0,0,0,false); }
 function recoveryPeriod() external pure returns (uint256) { return 172800; }
 mapping(address=>uint256) public membershipEpoch;
 function bumpEpoch(address a) external { membershipEpoch[a]++; } }
contract MockIdentity { function hasIdentity(address) external pure returns (bool) { return true; } }`;
(async () => {
  const signers = await hre.ethers.getSigners(); const deployer = signers[0]; const A = signers.slice(2, 14); const OUTSIDER = signers[15];
  const install = async (addr, abi, bc) => { const t = await new hre.ethers.ContractFactory(abi, bc, deployer).deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); };
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "M.sol": { content: MOCK } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const mr = out.contracts["M.sol"].MockRegistry, mi = out.contracts["M.sol"].MockIdentity;
  await install(REG, mr.abi, "0x" + mr.evm.bytecode.object); await install(IDR, mi.abi, "0x" + mi.evm.bytecode.object);
  const b = JSON.parse(fs.readFileSync("board_artifact.json")), dArt = JSON.parse(fs.readFileSync("distributor_artifact.json"));
  await install(BOARD, b.abi, b.bytecode); await install(DIST, dArt.abi, dArt.bytecode);
  await setS(BOARD, slotOf(b, "boardVersion"), 1);
  const reg = new hre.ethers.Contract(REG, mr.abi, deployer), board = new hre.ethers.Contract(BOARD, b.abi, deployer);
  for (let i = 0; i < 10; i++) { await (await reg.setActive(A[i].address, true)).wait(); await (await reg.setStatus(A[i].address, 2)).wait(); }
  for (let v = 0; v < 10; v++) for (const c of (v < 6 ? [0, 1, 2, 3, 4] : [0, 1, 2, 3, 5])) await (await board.connect(A[v]).voteFor(A[c].address)).wait();
  await (await board.refreshBoard()).wait();
  const d = w => new hre.ethers.Contract(DIST, dArt.abi, w);
  const exitOf = async i => { await (await reg.setActive(A[i].address, false)).wait(); await (await reg.setStatus(A[i].address, 4)).wait(); await (await reg.bumpEpoch(A[i].address)).wait(); };
  let snap = await hre.network.provider.send("evm_snapshot");
  const fresh = async () => { await hre.network.provider.send("evm_revert", [snap]); snap = await hre.network.provider.send("evm_snapshot"); };
  const propose = async (who, start, rate) => { await (await d(who).proposeRateChange(start, rate)).wait(); return await d(deployer).rateProposalCount(); };
  const boardVotes = async (id, n = 3) => { for (let i = 0; i < n; i++) await (await d(A[i]).boardVoteRateChange(id)).wait(); };
  const valVotes = async (id, n) => { for (let i = 0; i < n; i++) await (await d(A[i]).validatorVoteRateChange(id)).wait(); };
  const approve = async id => { const need = Number((await d(deployer).rateProposals(id)).requiredValidatorApprovals); await boardVotes(id); await valVotes(id, need); return (await d(deployer).rateProposals(id)).approvedAt; };
  const P = id => d(deployer).rateProposals(id);
  const status = async id => { const [s, p] = await d(deployer).rateChangeStatus(id); return [Number(s), Number(p)]; };
  const histCount = async () => await d(deployer).rewardRateChangeCount();
  ok("R0) real Board seated A0..A4; boardVersion = 2; 10 validators active", (await board.boardVersion()) === 2n && (await board.getBoardMembers()).length === 5 && (await reg.getActiveValidatorCount()) === 10n);

  console.log("\n=== G — constants and who can write the history ===");
  ok("G1) constants: board 3 (= BOARD_SIZE/2+1 = 3 of 5), voting 30 d, delay 7 d, lead 201,600 blocks",
    (await d(deployer).RATE_CHANGE_BOARD_APPROVALS()) === 3n && (await d(deployer).BOARD_SIZE()) === 5n && (await d(deployer).BOARD_SIZE()) / 2n + 1n === 3n && (await d(deployer).RATE_VOTING_EXPIRY()) === BigInt(30 * DAY) && (await d(deployer).RATE_CHANGE_DELAY()) === BigInt(7 * DAY) && (await d(deployer).MIN_RATE_CHANGE_LEAD_BLOCKS()) === 201600n);
  ok("G2) initial history empty, no proposals", (await histCount()) === 0n && (await d(deployer).rateProposalCount()) === 0n);
  const writers = dArt.abi.filter(x => x.type === "function" && x.stateMutability !== "view" && x.stateMutability !== "pure" && /rate/i.test(x.name)).map(x => x.name).sort();
  ok("G3) the only state-changing functions touching rate governance are propose/boardVote/validatorVote/execute (no oracle or owner setter)", JSON.stringify(writers) === JSON.stringify(["boardVoteRateChange", "executeRateChange", "proposeRateChange", "validatorVoteRateChange"]), writers.join(","));

  console.log("\n=== P — proposing ===");
  const base = await blockNo();
  ok("P1) a non-validator cannot propose", await reverts(() => d(OUTSIDER).proposeRateChange(base + 300000, 5), "only an active validator may propose a rate change"));
  { const txb = (await blockNo()) + 1;
    ok("P2) start = executing block + 201,599 rejected", await reverts(() => d(A[0]).proposeRateChange(txb + LEAD - 1, 5, { gasLimit: 500000 }), "closer than MIN_RATE_CHANGE_LEAD_BLOCKS"));
    const t2 = (await blockNo()) + 1;
    ok("P3) start = executing block + 201,600 accepted (exact boundary)", (await (await d(A[0]).proposeRateChange(t2 + LEAD, 5)).wait()).status === 1);
    const cur = await blockNo();
    ok("P4) start not in the future (= current block) rejected with its own message", await reverts(() => d(A[0]).proposeRateChange(cur, 5, { gasLimit: 500000 }), "not in the future")); }
  ok("P5) rate above uint128 rejected", await reverts(() => d(A[0]).proposeRateChange(base + 400000, 2n ** 128n, { gasLimit: 500000 }), "does not fit uint128"));
  await fresh();
  { const need = []; const probes = [[10, 7], [9, 6], [8, 6], [7, 5]]; const ids = [];
    for (const [n, exp] of probes) { while (Number(await reg.getActiveValidatorCount()) > n) { const k = 9 - (10 - Number(await reg.getActiveValidatorCount())); await (await reg.setActive(A[k].address, false)).wait(); }
      const id = await propose(A[0], (await blockNo()) + 300000 + ids.length, 2n * 10n ** 18n); ids.push(id); need.push(Number((await P(id)).requiredValidatorApprovals) === exp ? true : `n=${n}: ${(await P(id)).requiredValidatorApprovals} != ${exp}`); }
    ok("P6) required validator approvals = ceil(2/3 of the active set at creation): 10→7, 9→6, 8→6, 7→5, each frozen", need.every(x => x === true), need.join(" | ")); }
  await fresh();

  console.log("\n=== B — board chamber (3 of 5, live authority) ===");
  const idB = await propose(A[0], (await blockNo()) + 300000, 3n * 10n ** 18n);
  ok("B1) a non-board validator cannot cast a board vote", await reverts(() => d(A[7]).boardVoteRateChange(idB), "no live board authority"));
  await (await d(A[0]).boardVoteRateChange(idB)).wait(); await (await d(A[1]).boardVoteRateChange(idB)).wait();
  ok("B2) two board votes: nothing approved", (await P(idB)).boardApprovals === 2n && (await P(idB)).approvedAt === 0n);
  ok("B3) the same member cannot vote twice", await reverts(() => d(A[0]).boardVoteRateChange(idB), "board member already voted"));
  await exitOf(4);
  ok("B4) a member who requested exit has no live authority (before syncBoard) and cannot vote", (await board.isBoardMember(A[4].address)) === true && (await board.hasBoardAuthority(A[4].address)) === false && (await reverts(() => d(A[4]).boardVoteRateChange(idB), "no live board authority")) === true);
  await fresh();

  { const id = await propose(A[0], (await blockNo()) + 300000, 3n * 10n ** 18n);
    await (await d(A[0]).boardVoteRateChange(id)).wait(); await (await d(A[1]).boardVoteRateChange(id)).wait(); await valVotes(id, 7);
    ok("B5) 2 board votes + all 7 required validator votes: NOT approved (the board needs 3 of 5)", (await P(id)).approvedAt === 0n && (await P(id)).validatorApprovals === 7n && (await P(id)).boardApprovals === 2n);
    await (await d(A[2]).boardVoteRateChange(id)).wait();
    ok("B6) the third board vote completes the approval", (await P(id)).approvedAt !== 0n); }
  await fresh();

  console.log("\n=== V — validator chamber (two thirds of the electorate at creation, L04) ===");
  const idV = await propose(A[0], (await blockNo()) + 300000, 3n * 10n ** 18n);
  await boardVotes(idV);
  ok("V1) board chamber complete, validators not: still not approved", (await P(idV)).boardApprovals === 3n && (await P(idV)).approvedAt === 0n && JSON.stringify(await status(idV)) === JSON.stringify([1, 0]));
  await valVotes(idV, 6);
  ok("V2) 6 of the required 7: not approved", (await P(idV)).validatorApprovals === 6n && (await P(idV)).approvedAt === 0n);
  { const rcpt = await (await d(A[6]).validatorVoteRateChange(idV)).wait(); const ev = rcpt.logs.map(l => { try { return d(deployer).interface.parseLog(l); } catch (e) { return null; } }).filter(e => e && e.name === "RateChangeApproved");
    ok("V3) the 7th vote completes both chambers: approvedAt = that block's timestamp; RateChangeApproved(executableAt = +7 d) emitted", (await P(idV)).approvedAt === BigInt(await latestTs()) && ev.length === 1 && ev[0].args.executableAt === ev[0].args.approvedAt + BigInt(7 * DAY)); }
  ok("V4) further votes after approval are refused (voting closed)", await reverts(() => d(A[7]).validatorVoteRateChange(idV), "voting closed"));
  await fresh();
  { const id1 = await propose(A[0], (await blockNo()) + 300000, 3n * 10n ** 18n); await boardVotes(id1);
    const late = A[10]; await (await reg.setActive(late.address, true)).wait();
    ok("V5) a validator activated after creation cannot vote (L04)", await reverts(() => d(late).validatorVoteRateChange(id1), "not eligible - not Active when this proposal was created"));
    await (await reg.setActive(A[8].address, false)).wait(); const id2 = await propose(A[0], (await blockNo()) + 300001, 3n * 10n ** 18n); await (await reg.setActive(A[8].address, true)).wait();
    ok("V6) suspended AT creation, back later: not eligible", await reverts(() => d(A[8]).validatorVoteRateChange(id2), "not eligible - not Active when this proposal was created"));
    await (await reg.setActive(A[5].address, false)).wait();
    ok("V7) eligible at creation but suspended now: cannot vote while suspended", await reverts(() => d(A[5]).validatorVoteRateChange(id1), "caller is not an active validator"));
    await (await reg.setActive(A[5].address, true)).wait();
    ok("V8) recovered: may vote once, and not again", (await (await d(A[5]).validatorVoteRateChange(id1)).wait()).status === 1 && (await reverts(() => d(A[5]).validatorVoteRateChange(id1), "validator already voted")) === true);
    const before = (await P(id1)).validatorApprovals; await (await reg.setActive(A[5].address, false)).wait(); await (await reg.setStatus(A[5].address, 4)).wait();
    ok("V9) a voter who then exits keeps the recorded vote; no new vote possible", (await P(id1)).validatorApprovals === before && (await reverts(() => d(A[5]).validatorVoteRateChange(id1), "caller is not an active validator")) === true); }
  await fresh();

  console.log("\n=== T — time: delay from BOTH chambers, voting expiry, queue not removed ===");
  { const id = await propose(A[0], (await blockNo()) + 300000, 3n * 10n ** 18n); const c0 = (await P(id)).createdAt;
    await boardVotes(id); const tBoardDone = await latestTs();
    await hre.network.provider.send("evm_setNextBlockTimestamp", [tBoardDone + 10 * DAY]); await (await d(A[0]).validatorVoteRateChange(id)).wait();
    for (let i = 1; i < 7; i++) await (await d(A[i]).validatorVoteRateChange(id)).wait();
    const tApproved = Number((await P(id)).approvedAt);
    ok("T1) approvedAt is when the SECOND chamber completed (10 days after the board), not when the first did", tApproved >= tBoardDone + 10 * DAY && tApproved < tBoardDone + 10 * DAY + 60);
    ok("T2) executing at board-completion + 7 d is refused: the delay has not started counting from there", await reverts(() => at(tBoardDone + 17 * DAY - 1, () => d(deployer).executeRateChange(id, { gasLimit: 500000 })), "execution delay has not elapsed"));
    ok("T3) executing 1 second before approvedAt + 7 d is refused", await reverts(() => at(tApproved + 7 * DAY - 1, () => d(deployer).executeRateChange(id, { gasLimit: 500000 })), "execution delay has not elapsed"));
    const tNow = await latestTs(); const target = tApproved + 7 * DAY;
    const r4 = await succeeds(() => at(target, () => d(deployer).executeRateChange(id)));
    ok("T4) exactly at approvedAt + 7 d it executes", target > tNow && r4 === true && (await histCount()) === 1n, String(r4));
    const [rs, rp] = await status(id); ok("T5) status = executed (3)", rs === 3 && rp === 0); }
  await fresh();
  { const id = await propose(A[0], (await blockNo()) + 300000, 3n * 10n ** 18n); const exp = Number((await P(id)).votingExpiresAt);
    await boardVotes(id); for (let i = 0; i < 6; i++) await (await d(A[i]).validatorVoteRateChange(id)).wait();
    ok("T6) voting at exactly votingExpiresAt is still accepted (inclusive)", (await (await at(exp, () => d(A[6]).validatorVoteRateChange(id))).wait()).status === 1);
    const a = Number((await P(id)).approvedAt); const r7 = await succeeds(() => at(a + 7 * DAY, () => d(deployer).executeRateChange(id)));
    ok("T7) the proposal approved at day 30 is executable at day 37 — beyond the 30-day expiry — the queue is not removed", a === exp && r7 === true && (await histCount()) === 1n, String(r7)); }
  await fresh();
  { const id = await propose(A[0], (await blockNo()) + 300000, 3n * 10n ** 18n); const exp = Number((await P(id)).votingExpiresAt); await boardVotes(id);
    ok("T8) one second after the voting period the second chamber can no longer complete", await reverts(() => at(exp + 1, () => d(A[0]).validatorVoteRateChange(id, { gasLimit: 500000 })), "voting period has expired"));
    const s = await status(id); ok("T9) never approved: status = voting expired (2); executing it is refused", s[0] === 2 && (await reverts(() => d(deployer).executeRateChange(id, { gasLimit: 500000 }), "not approved by both chambers")) === true); }
  await fresh();

  console.log("\n=== E — final execution re-checks (proposal left exactly as it is on failure) ===");
  const snapProp = async id => JSON.stringify((await P(id)).map(x => x.toString()));
  { const id = await propose(A[0], (await blockNo()) + 300000, 3n * 10n ** 18n); const a = await approve(id); const before = await snapProp(id);
    await exitOf(4); await (await board.syncBoard()).wait();
    ok("E1) board composition changed after approval (real exit + syncBoard bumps boardVersion)", (await board.boardVersion()) === 3n);
    ok("E2) status view reports approved-but-unexecutable, problem 1 (board changed)", JSON.stringify(await status(id)) === JSON.stringify([6, 1]));
    ok("E3) execution refused: board membership changed", await reverts(() => at(Number(a) + 7 * DAY, () => d(deployer).executeRateChange(id, { gasLimit: 500000 })), "board membership changed since this proposal was created"));
    ok("E4) proposal unchanged, history unchanged", (await snapProp(id)) === before && (await histCount()) === 0n); }
  await fresh();
  { const id = await propose(A[0], (await blockNo()) + LEAD + 9000, 3n * 10n ** 18n); const a = await approve(id); const before = await snapProp(id);
    await hre.network.provider.send("hardhat_mine", ["0x" + (12000).toString(16)]);
    ok("E5) blocks passed during the delay: remaining distance < 201,600 → status problem 3", JSON.stringify(await status(id)) === JSON.stringify([6, 3]));
    const tE6 = (await latestTs()) + 7 * DAY;
    ok("E6) execution refused: closer than MIN_RATE_CHANGE_LEAD_BLOCKS (start still in the future)", await reverts(() => at(tE6, () => d(deployer).executeRateChange(id, { gasLimit: 500000 })), "closer than MIN_RATE_CHANGE_LEAD_BLOCKS"));
    ok("E7) proposal unchanged — neither the start block nor the time was moved", (await snapProp(id)) === before && (await histCount()) === 0n); }
  await fresh();
  { const id = await propose(A[0], (await blockNo()) + LEAD + 100, 3n * 10n ** 18n); const a = await approve(id); const before = await snapProp(id);
    await hre.network.provider.send("hardhat_mine", ["0x" + (LEAD + 500).toString(16)]);
    ok("E8) start block already in the past: status problem 2", JSON.stringify(await status(id)) === JSON.stringify([6, 2]));
    const tE9 = (await latestTs()) + 7 * DAY;
    ok("E9) execution refused: start block is not in the future", await reverts(() => at(tE9, () => d(deployer).executeRateChange(id, { gasLimit: 500000 })), "start block is not in the future"));
    ok("E10) proposal unchanged, history unchanged", (await snapProp(id)) === before && (await histCount()) === 0n); }
  await fresh();

  console.log("\n=== C — concurrent proposals and unexecutable proposals ===");
  for (const order of ["descending (largest start first)", "ascending (smallest start first)"]) {
    await fresh(); const b0 = await blockNo(); const S = { p1: b0 + 300000, p2: b0 + 400000, p3: b0 + 400000, p4: b0 + 350000 };
    const ids = {}; for (const k of ["p1", "p2", "p3", "p4"]) { ids[k] = await propose(A[0], S[k], BigInt(Number(k[1]) + 1) * 10n ** 18n); }
    const aps = {}; for (const k of ["p1", "p2", "p3", "p4"]) aps[k] = await approve(ids[k]);
    const latestA = Math.max(...Object.values(aps).map(Number)); const T0 = latestA + 7 * DAY + 5;
    await hre.network.provider.send("evm_setNextBlockTimestamp", [T0]); await hre.network.provider.send("evm_mine");
    const seq = order.startsWith("desc") ? ["p2", "p3", "p4", "p1"] : ["p1", "p4", "p2", "p3"];
    const res = {}; for (const k of seq) { const before = await snapProp(ids[k]); const r = await reverts(() => d(deployer).executeRateChange(ids[k], { gasLimit: 600000 }), "must be after the last approved rate change"); res[k] = r === true ? "refused(ascending)" : (r === "did NOT revert" ? "executed" : "UNEXPECTED: " + r); if (r === true) { res[k + "_unchanged"] = (await snapProp(ids[k])) === before; } }
    const exp = order.startsWith("desc") ? { p2: "executed", p3: "refused(ascending)", p4: "refused(ascending)", p1: "refused(ascending)" } : { p1: "executed", p4: "executed", p2: "executed", p3: "refused(ascending)" };
    // 'reverts' returns "did NOT revert" when it executed (and the tx was mined) -> the tx above already executed it
    const norm = {}; for (const k of seq) norm[k] = res[k];
    ok(`C1) order ${order}: outcomes follow strict ascending history exactly`, JSON.stringify(norm) === JSON.stringify(exp), JSON.stringify(norm));
    const nExec = Object.values(norm).filter(x => x === "executed").length; ok(`C2) order ${order}: history length = ${nExec}, strictly ascending`, (await histCount()) === BigInt(nExec) && await (async () => { let prev = 0n; for (let i = 0; i < nExec; i++) { const [s] = await d(deployer).rewardRateChange(i); if (s <= prev) return false; prev = s; } return true; })());
    const refused = seq.filter(k => norm[k] === "refused(ascending)"); ok(`C3) order ${order}: every refused proposal is left untouched, still approved, status (6, problem 4) — no time or height moved`, (await Promise.all(refused.map(async k => res[k + "_unchanged"] === true && JSON.stringify(await status(ids[k])) === JSON.stringify([6, 4])))).every(x => x));
  }
  await fresh();

  console.log("\n=== I — interaction with the cap ===");
  { const b0 = await blockNo(); const S = b0 + 300000; const id = await propose(A[0], S, 3n * 10n ** 18n); const a = await approve(id);
    const share0 = await d(deployer).validatorDirectShareBps(); const rcpt = await (await at(Number(a) + 7 * DAY, () => d(deployer).executeRateChange(id))).wait();
    const ev = rcpt.logs.map(l => { try { return d(deployer).interface.parseLog(l); } catch (e) { return null; } }).find(e => e && e.name === "RateChangeExecuted");
    ok("I1) RateChangeExecuted carries the start block and rate; rewardRateChange(0) returns them", ev.args.startBlock === BigInt(S) && ev.args.ratePerBlock === 3n * 10n ** 18n && (await d(deployer).rewardRateChange(0)).toString() === [S, 3n * 10n ** 18n].toString());
    ok("I2) rate 2 SUR until S−1, 3 SUR from S", (await d(deployer).rewardRateAt(S - 1)) === 2n * 10n ** 18n && (await d(deployer).rewardRateAt(S)) === 3n * 10n ** 18n);
    ok("I3) a range crossing S: 5 blocks at 2 SUR + 5 blocks at 3 SUR = 25 SUR", (await d(deployer).maxRewardsForRange(S - 5, S + 4)) === 25n * 10n ** 18n);
    ok("I4) executing does not touch validatorDirectShareBps (formula and governance of the share unchanged)", (await d(deployer).validatorDirectShareBps()) === share0); }
  await fresh();
  { const id = await propose(A[0], (await blockNo()) + 300000, 0); const a = await approve(id); await (await at(Number(a) + 7 * DAY, () => d(deployer).executeRateChange(id))).wait();
    const [s] = await d(deployer).rewardRateChange(0); ok("I5) a zero rate is a valid approved rate (zero-reward segment)", (await d(deployer).rewardRateAt(s)) === 0n); }
  await fresh();

  console.log("\n=== S — completion re-check after a board change, and status of proposals that cannot continue ===");
  const valVoteList = async (id, idxs) => { for (const i of idxs) await (await d(A[i]).validatorVoteRateChange(id)).wait(); };
  const changeBoard = async () => { await exitOf(4); await (await board.syncBoard()).wait(); };
  const approvedEvents = async id => (await d(deployer).queryFilter(d(deployer).filters.RateChangeApproved(id), 0, "latest")).length;
  { // S1: board chamber complete -> real board change -> the LAST validator vote must not register approval
    const id = await propose(A[0], (await blockNo()) + 300000, 3n * 10n ** 18n); await boardVotes(id);
    await changeBoard(); const boardV = await board.boardVersion();
    await valVoteList(id, [0, 1, 2, 3, 5, 6]);
    ok("S1) after the board changed, six of the seven validator votes are still accepted (nothing is approved yet)", (await P(id)).validatorApprovals === 6n && (await P(id)).approvedAt === 0n);
    ok("S2) the completing (7th) validator vote is refused: board membership changed", await reverts(() => d(A[7]).validatorVoteRateChange(id, { gasLimit: 500000 }), "board membership changed since this proposal was created"));
    ok("S3) no approval was registered: approvedAt = 0, validator count still 6, no RateChangeApproved event", (await P(id)).approvedAt === 0n && (await P(id)).validatorApprovals === 6n && (await approvedEvents(id)) === 0);
    ok("S4) status = 7 (cannot continue), problem 1 (board composition changed) — not 'voting'", JSON.stringify(await status(id)) === JSON.stringify([7, 1]), `boardVersion=${boardV}`);
    ok("S5) execution refused: never approved", await reverts(() => d(deployer).executeRateChange(id, { gasLimit: 500000 }), "not approved by both chambers")); }
  await fresh();
  { // S6: validator chamber complete first -> board change -> a board vote is refused; status 7/1
    const id = await propose(A[0], (await blockNo()) + 300000, 3n * 10n ** 18n); await valVotes(id, 7); await changeBoard();
    ok("S6) validators complete first, then the board changes: a board vote is refused", await reverts(() => d(A[0]).boardVoteRateChange(id, { gasLimit: 500000 }), "board membership changed since this proposal was created"));
    ok("S7) status = 7, problem 1; never approved", JSON.stringify(await status(id)) === JSON.stringify([7, 1]) && (await P(id)).approvedAt === 0n && (await approvedEvents(id)) === 0);
    const id2 = await propose(A[0], (await blockNo()) + 300001, 3n * 10n ** 18n); await boardVotes(id2); await valVoteList(id2, [0, 1, 2, 3, 5, 6]);
    ok("S8) a proposal created AFTER the board change completes normally (required 6 of 9 active): approved, status 4", Number((await P(id2)).requiredValidatorApprovals) === 6 && (await P(id2)).approvedAt !== 0n && JSON.stringify(await status(id2)) === JSON.stringify([4, 0])); }
  await fresh();
  { // S9: expiry takes precedence over 'cannot continue'; a healthy proposal still reads 'voting'
    const idH = await propose(A[0], (await blockNo()) + 300000, 3n * 10n ** 18n); const idV = await propose(A[0], (await blockNo()) + 300001, 3n * 10n ** 18n);
    ok("S9) a healthy proposal reads status 1 (voting), problem 0", JSON.stringify(await status(idH)) === JSON.stringify([1, 0]));
    await changeBoard();
    ok("S10) both proposals now read 7/1 (the board they belonged to is gone)", JSON.stringify(await status(idH)) === JSON.stringify([7, 1]) && JSON.stringify(await status(idV)) === JSON.stringify([7, 1]));
    await hre.network.provider.send("evm_increaseTime", [31 * DAY]); await hre.network.provider.send("evm_mine");
    ok("S11) after the 30-day voting period the same proposal reads 2 (expired) — expiry takes precedence", JSON.stringify(await status(idH)) === JSON.stringify([2, 0])); }
  await fresh();
  { // S12/S13: start-block problems of a proposal that is still being voted on are permanent too
    const id = await propose(A[0], (await blockNo()) + LEAD + 9000, 3n * 10n ** 18n);
    await hre.network.provider.send("hardhat_mine", ["0x" + (12000).toString(16)]);
    ok("S12) blocks passed: remaining distance < 201,600 → status 7, problem 3 (a later approval could never execute it)", JSON.stringify(await status(id)) === JSON.stringify([7, 3]));
    await hre.network.provider.send("hardhat_mine", ["0x" + (LEAD).toString(16)]);
    ok("S13) start block now in the past → status 7, problem 2", JSON.stringify(await status(id)) === JSON.stringify([7, 2])); }
  await fresh();
  { // S14: another proposal executed first makes this one unable to continue (strictly ascending history)
    const b0 = await blockNo(); const idA = await propose(A[0], b0 + 400000, 3n * 10n ** 18n); const idB = await propose(A[0], b0 + 350000, 4n * 10n ** 18n);
    ok("S14) before A is executed, B (earlier start) is a normal voting proposal: 1/0", JSON.stringify(await status(idB)) === JSON.stringify([1, 0]));
    const a = await approve(idA); await (await at(Number(a) + 7 * DAY, () => d(deployer).executeRateChange(idA))).wait();
    ok("S15) after A (later start) is executed, B reads status 7, problem 4 and is left untouched", JSON.stringify(await status(idB)) === JSON.stringify([7, 4]) && (await P(idB)).startBlock === BigInt(b0 + 350000)); }
  await fresh();

  console.log("\n=== K — cost: governance operations do not grow with the history ===");
  const RS = BigInt(dArt.layout.storage.find(x => x.label === "rewardRateChanges").slot); const baseS = BigInt(hre.ethers.keccak256(hre.ethers.zeroPadValue(hre.ethers.toBeHex(RS), 32)));
  const setSchedule = async n => { await setS(DIST, hre.ethers.toBeHex(RS), n); for (let i = 0; i < n; i++) await setS(DIST, hre.ethers.toBeHex(baseS + BigInt(i)), BigInt(100 + i * 10) + ((2n * 10n ** 18n) << 128n)); };
  const gas = {};
  for (const n of [0, 400]) { await fresh(); await setSchedule(n); const g1 = (await (await d(A[0]).proposeRateChange((await blockNo()) + 300000, 3n * 10n ** 18n)).wait()).gasUsed; const id = await d(deployer).rateProposalCount(); const a = await approve(id); const g2 = (await (await at(Number(a) + 7 * DAY, () => d(deployer).executeRateChange(id))).wait()).gasUsed; gas[n] = [g1, g2]; }
  ok("K1) propose: gas with 400 old entries within +3% of gas with none", gas[400][0] <= gas[0][0] * 103n / 100n, `0=${gas[0][0]} 400=${gas[400][0]}`);
  ok("K2) execute: gas with 400 old entries within +3% of gas with none", gas[400][1] <= gas[0][1] * 103n / 100n, `0=${gas[0][1]} 400=${gas[400][1]}`);
  await fresh();

  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
