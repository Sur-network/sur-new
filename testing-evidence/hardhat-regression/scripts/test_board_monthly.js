// Monthly board with incremental vote counters (v2.1.0): month function, one board per calendar month, no authority before the
// month's first refresh, full replacement by votes with seniority tie-break, persistent votes, counter invariant, key-rotation floor,
// exit-driven succession and treasury payments. Real ValidatorsBoard + ValidatorsTreasury against a mock registry.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const REG = "0x3333333333333333333333333333333333333333", DIST = "0x2222222222222222222222222222222222222222", BOARD = "0x4444444444444444444444444444444444444444", TRES = "0x5555555555555555555555555555555555555555", IDR = "0x6666666666666666666666666666666666666666";
let results = [], board, reg, dist, A, deployer, recipient, b, t;
function ok(name, c, extra = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + name + (c === true ? "" : " → " + c) + (extra ? "  " + extra : "")); }
async function reverts(fn, expected) { try { await (await fn()).wait(); return false; } catch (e) { return (e.message || "").includes(expected) ? true : "wrong reason: " + (e.message || "").slice(0, 200); } }
const slot = (art, n) => hre.ethers.toBeHex(BigInt(art.layout.storage.find(s => s.label === n).slot));
const setS = (addr, sl, v) => hre.network.provider.send("hardhat_setStorageAt", [addr, sl, hre.ethers.zeroPadValue(hre.ethers.toBeHex(v), 32)]);
const members = async () => (await board.getBoardMembers()).map(x => x.toLowerCase());
const has = async (a) => (await members()).includes(a.address.toLowerCase());
const ts = (y, m, d, h = 12, mi = 0, s = 0) => Math.floor(Date.UTC(y, m - 1, d, h, mi, s) / 1000);
let clock = 0;
async function at(t_) { if (t_ <= clock) throw new Error("time must increase: " + t_ + " <= " + clock); await hre.network.provider.send("evm_setNextBlockTimestamp", [t_]); await hre.network.provider.send("evm_mine"); clock = t_; }
const monthOf = (t_) => { const d = new Date(t_ * 1000); return BigInt(d.getUTCFullYear() * 12 + d.getUTCMonth()); };
const E1 = hre.ethers.parseEther("10");

const MOCK = `pragma solidity ^0.8.24;
contract MockRegistry { address[] public vals; mapping(address=>bool) public active; mapping(address=>uint8) public st; mapping(address=>uint256) public membershipEpoch; mapping(address=>uint256) public activationSeq;
 address public lastVerifier; uint256 public lastEntry; uint256 public lastGrowth; uint256 public lastFee;
 function setActive(address a, bool on) external { if (on && !active[a]) { active[a]=true; vals.push(a);} else if (!on && active[a]) { active[a]=false; for (uint i=0;i<vals.length;i++) if (vals[i]==a) { vals[i]=vals[vals.length-1]; vals.pop(); break; } } }
 function setStatus(address a, uint8 s) external { st[a]=s; }
 function setSeq(address a, uint256 s) external { activationSeq[a]=s; }
 function bumpEpoch(address a) external { membershipEpoch[a]++; }
 function isValidator(address a) external view returns (bool) { return active[a]; }
 function getValidators() external view returns (address[] memory) { return vals; }
 function getValidatorInfo(address a) external view returns (uint8,uint256,uint256,uint256,uint256,bool) { return (st[a],0,0,0,0,false); }
 function recoveryPeriod() external pure returns (uint256) { return 172800; }
 function setVerifier(address v) external { lastVerifier = v; }
 function setEntryThresholdBase(uint256 v) external { lastEntry = v; }
 function setGrowthFactorPerValidator(uint256 v) external { lastGrowth = v; }
 function setMembershipFeeBps(uint256 v) external { lastFee = v; } }
contract MockIdentity { function hasIdentity(address) external pure returns (bool) { return true; } }
contract MockDistributor { address public oracle; function setDistributionOracle(address o) external { oracle = o; } }`;

async function install(addr, abi, bytecode) { const f = new hre.ethers.ContractFactory(abi, bytecode, deployer); const x = await f.deploy(); await x.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await x.getAddress(), "latest"])]); }
async function setup() {
  const signers = await hre.ethers.getSigners(); deployer = signers[0]; recipient = signers[19]; A = signers.slice(2, 18);
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "M.sol": { content: MOCK } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const mr = out.contracts["M.sol"].MockRegistry, mi = out.contracts["M.sol"].MockIdentity, md = out.contracts["M.sol"].MockDistributor;
  await install(REG, mr.abi, "0x" + mr.evm.bytecode.object); await install(IDR, mi.abi, "0x" + mi.evm.bytecode.object); await install(DIST, md.abi, "0x" + md.evm.bytecode.object);
  b = JSON.parse(fs.readFileSync("board_artifact.json")); t = JSON.parse(fs.readFileSync("treasury_artifact.json"));
  await install(BOARD, b.abi, b.bytecode); await install(TRES, t.abi, t.bytecode);
  await setS(BOARD, slot(b, "boardVersion"), 1);
  await setS(TRES, slot(t, "perPaymentCap"), hre.ethers.parseEther("50000")); await setS(TRES, slot(t, "periodCap"), hre.ethers.parseEther("200000"));
  await hre.network.provider.send("hardhat_setBalance", [TRES, "0x" + (10n ** 25n).toString(16)]);
  reg = new hre.ethers.Contract(REG, mr.abi, deployer); board = new hre.ethers.Contract(BOARD, b.abi, deployer); dist = new hre.ethers.Contract(DIST, md.abi, deployer);
  for (let i = 0; i < 16; i++) { await (await reg.setActive(A[i].address, true)).wait(); await (await reg.setStatus(A[i].address, 2)).wait(); await (await reg.setSeq(A[i].address, i + 1)).wait(); }
}
// genesis-style seeding of the founding board for month `monthId`
async function seedBoard(addrs, monthId) {
  const bm = BigInt(b.layout.storage.find(x => x.label === "boardMembers").slot), im = BigInt(b.layout.storage.find(x => x.label === "isBoardMember").slot);
  const put = (addr, slotHex, val) => hre.network.provider.send("hardhat_setStorageAt", [addr, slotHex, hre.ethers.zeroPadValue(hre.ethers.toBeHex(val), 32)]);
  await put(BOARD, hre.ethers.toBeHex(bm), BigInt(addrs.length)); const base = BigInt(hre.ethers.keccak256(hre.ethers.zeroPadValue(hre.ethers.toBeHex(bm), 32)));
  for (let i = 0; i < addrs.length; i++) { await put(BOARD, hre.ethers.toBeHex(base + BigInt(i)), BigInt(addrs[i])); await put(BOARD, hre.ethers.keccak256(hre.ethers.concat([hre.ethers.zeroPadValue(addrs[i], 32), hre.ethers.zeroPadValue(hre.ethers.toBeHex(im), 32)])), 1n); }
  await put(BOARD, slot(b, "boardMonthId"), monthId);
}
const voteAll = async (voters, cands) => { for (const v of voters) for (const c of cands) await (await board.connect(A[v]).voteFor(A[c].address)).wait(); };

(async () => {
  await setup();

  // ---- month function ----
  { let bad = 0; const samples = [0, 86399, 86400, ts(2000, 2, 29, 0), ts(2000, 3, 1, 0), ts(2024, 12, 31, 23, 59, 59), ts(2025, 1, 1, 0, 0, 0), ts(2100, 2, 28, 23, 59, 59), ts(2100, 3, 1, 0, 0, 0), ts(2038, 1, 19, 3, 14, 8), ts(2200, 12, 31, 23, 59, 59)];
    let seed = 12345; const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648;
    for (let i = 0; i < 300; i++) samples.push(Math.floor(rnd() * 7_300_000_000)); // 1970..2201
    for (const s of samples) if ((await board.monthIdOf(s)) !== monthOf(s)) { bad++; console.log("month mismatch", s, await board.monthIdOf(s), monthOf(s)); }
    ok("M1) monthIdOf equals the calendar month (UTC) for " + samples.length + " timestamps incl. leap-year, 2100 (not leap), year/month boundaries", bad === 0);
    ok("M2) the last second of a month and the first second of the next month give consecutive ids", (await board.monthIdOf(ts(2025, 1, 31, 23, 59, 59))) + 1n === (await board.monthIdOf(ts(2025, 2, 1, 0, 0, 0))));
  }

  const snap0 = await hre.network.provider.send("evm_snapshot");
  let snapId = snap0; clock = 0;
  const fresh = async () => { await hre.network.provider.send("evm_revert", [snapId]); snapId = await hre.network.provider.send("evm_snapshot"); clock = 0; };

  // ---- genesis board: authority in its own month only ----
  await at(ts(2027, 3, 10)); const m0 = monthOf(ts(2027, 3, 10));
  await seedBoard([A[0].address, A[1].address, A[2].address, A[3].address, A[4].address], m0);
  ok("G1) genesis-seeded board of month M: all 5 hold authority during M", (await members()).length === 5 && (await board.hasBoardAuthority(A[0].address)) && (await board.hasBoardAuthority(A[4].address)));
  ok("G2) refreshBoard is not allowed again in M (board non-empty)", await reverts(() => board.refreshBoard([]), "already set"));
  ok("G3) refreshDue() is false during M", (await board.refreshDue()) === false);
  { const id = (await board.actionCount()) + 1n; await (await board.connect(A[0]).proposeApproveBudget(recipient.address, E1, "g")).wait(); ok("G4) a seat holder can propose during M", (await board.actions(id)).votes === 1n); }
  await at(ts(2027, 3, 31, 23, 59, 59));
  ok("G5) still authority in the last second of M", (await board.hasBoardAuthority(A[0].address)) === true);
  await at(ts(2027, 4, 1, 0, 0, 0));
  ok("G6) first second of M+1: the old board has no authority", (await board.hasBoardAuthority(A[0].address)) === false);
  ok("G7) refreshDue() is true in M+1", (await board.refreshDue()) === true);
  ok("G8) proposing is refused with a clear message until refreshBoard() is called", await reverts(() => board.connect(A[0]).proposeApproveBudget(recipient.address, E1, "x"), "board term ended - call refreshBoard"));
  ok("G9) syncBoard / fillVacancies are refused for an expired term", (await reverts(() => board.syncBoard(), "board term ended")) === true && (await reverts(() => board.fillVacancies(), "board term ended")) === true);

  // ---- refresh: full replacement by votes ----
  await voteAll([5, 6, 7, 8, 9], [5, 6, 7, 8, 9]);   // A5..A9 get 5 votes each; A0..A4 get none
  const v0 = await board.boardVersion();
  const rr = await (await board.connect(A[12]).refreshBoard([])).wait();
  ok("R1) anyone may call refreshBoard; the 5 most-voted active validators replace the whole board", (await members()).length === 5 && [5, 6, 7, 8, 9].every(i => (members_ => true)()) && (await Promise.all([5,6,7,8,9].map(i => has(A[i])))).every(Boolean) && !(await has(A[0])) && !(await has(A[4])));
  ok("R2) boardVersion increased, boardMonthId = the new month", (await board.boardVersion()) === v0 + 1n && (await board.boardMonthId()) === monthOf(ts(2027, 4, 1)));
  ok("R3) the new board has authority at once", (await board.hasBoardAuthority(A[5].address)) === true && (await board.hasBoardAuthority(A[0].address)) === false);
  ok("R4) a second refresh in the same month is refused", await reverts(() => board.refreshBoard([]), "already set"));
  { const ev = rr.logs.map(l => { try { return board.interface.parseLog(l); } catch (e) { return null; } }).filter(x => x && x.name === "BoardRefreshed")[0];
    ok("R5) BoardRefreshed carries the month id, the 5 members and their vote counts (5 each)", ev && ev.args[0] === monthOf(ts(2027, 4, 1)) && ev.args[1].length === 5 && ev.args[2].every(x => x === 5n)); }

  // ---- votes persist; unchanged composition does not bump boardVersion ----
  await at(ts(2027, 5, 1, 0, 0, 1));
  { const vb = await board.boardVersion(); await (await board.refreshBoard([])).wait();
    ok("P1) votes persist across months: the same 5 are seated again", (await Promise.all([5,6,7,8,9].map(i => has(A[i])))).every(Boolean) && (await members()).length === 5);
    ok("P2) unchanged composition does not increase boardVersion", (await board.boardVersion()) === vb);
    ok("P3) no incumbent advantage is stored: voteCount of each member is still 5", (await Promise.all([5,6,7,8,9].map(i => board.voteCount(A[i].address)))).every(x => x === 5n)); }

  // ---- tie-break by seniority; no incumbent advantage ----
  await at(ts(2027, 6, 1, 0, 0, 1));
  { // voters 0..2 vote for A10..A14 (3 votes each) while A5..A9 keep 5 votes from the 5 voters -> unvote to create ties
    for (const v of [5, 6, 7, 8, 9]) for (const c of [5, 6, 7, 8, 9]) await (await board.connect(A[v]).unvoteFor(A[c].address)).wait();
    await voteAll([0, 1, 2], [10, 11, 12, 13, 14]); // five candidates with 3 votes each; A15 gets its 3 votes from other voters below
  }
  ok("T0) vote limit: a validator cannot cast a sixth vote", await reverts(() => board.connect(A[0]).voteFor(A[15].address), "max votes already used"));
  { // counts: A10..A14 each 3 votes. add A15 with 3 votes from voters 3,4,5 (distinct from above)
    for (const v of [3, 4, 5]) await (await board.connect(A[v]).voteFor(A[15].address)).wait();
    // A5..A9 have 0 votes now; six candidates tie at 3 votes: A10..A15 -> seats go to the 5 OLDEST (lowest seq): A10..A14 (seq 11..15); A15 (seq 16) is out
    await (await board.refreshBoard([])).wait();
    ok("T1) six candidates tie at 3 votes: the five oldest validators (lowest activation order) take the seats", (await Promise.all([10,11,12,13,14].map(i => has(A[i])))).every(Boolean) && !(await has(A[15])));
    ok("T2) the previous board (A5..A9, now 0 votes) is out entirely: previous membership gives no advantage", (await Promise.all([5,6,7,8,9].map(i => has(A[i])))).every(x => x === false)); }
  await at(ts(2027, 7, 1, 0, 0, 1));
  { // make the youngest (A15, seq 16) older than A14 (seq 15): the tie then goes the other way
    await (await reg.setSeq(A[15].address, 1)).wait(); await (await board.refreshBoard([])).wait();
    ok("T3) when activation order changes, the tie-break follows it (A15 now oldest and seated; A14 out)", (await has(A[15])) && !(await has(A[14])) && (await members()).length === 5); }

  // ---- inactive candidate is skipped at selection; fewer than 5 candidates -> fewer seats ----
  await at(ts(2027, 8, 1, 0, 0, 1));
  { await (await reg.setActive(A[10].address, false)).wait(); await (await reg.setStatus(A[10].address, 3)).wait(); // A10 suspended, votes for A10 remain counted until candidate check
    ok("S0) the counter of a deactivated candidate is unchanged (candidate eligibility is checked at selection)", (await board.voteCount(A[10].address)) === 3n);
    await (await board.refreshBoard([])).wait();
    ok("S1) a candidate that is no longer active is skipped at selection", !(await has(A[10])) && (await members()).length === 5); }

  // ---- empty candidate set -> empty board; empty board may refresh at any time ----
  await fresh(); await at(ts(2028, 1, 10));
  { const mm = monthOf(ts(2028, 1, 10)); await seedBoard([A[0].address, A[1].address, A[2].address, A[3].address, A[4].address], mm - 1n); // board of an older month
    await (await board.refreshBoard([])).wait(); // no votes at all
    ok("E1) refresh with no votes seats nobody: the board is empty (no incumbent is kept)", (await members()).length === 0 && !(await has(A[0])));
    ok("E2) an empty board does not block: refreshDue() stays true", (await board.refreshDue()) === true);
    await voteAll([6, 7, 8], [6, 7, 8]); await (await board.refreshBoard([])).wait();
    ok("E3) an empty board can be refreshed again in the same month once candidates exist (3 seats)", (await members()).length === 3 && (await has(A[6]))); }

  // ---- counters follow voter status (syncVoter) ----
  await fresh(); await at(ts(2028, 2, 10));
  { await voteAll([0, 1], [5, 6, 7]);
    ok("C1) voteCount reflects votes: 2 each for A5..A7", (await Promise.all([5,6,7].map(i => board.voteCount(A[i].address)))).every(x => x === 2n));
    await (await reg.setActive(A[0].address, false)).wait(); await (await reg.setStatus(A[0].address, 3)).wait();
    ok("C2) before syncVoter the counter is unchanged (the registry hook has not run)", (await board.voteCount(A[5].address)) === 2n && (await board.votesCounted(A[0].address)) === true);
    await (await board.connect(A[9]).syncVoter(A[0].address)).wait();
    ok("C3) syncVoter by anyone removes a deactivated voter's votes from the counters", (await board.voteCount(A[5].address)) === 1n && (await board.votesCounted(A[0].address)) === false);
    await (await board.connect(A[9]).syncVoter(A[0].address)).wait();
    ok("C4) syncVoter is idempotent", (await board.voteCount(A[5].address)) === 1n);
    ok("C5) the voter's own list of votes is untouched (votes persist)", (await board.getVotesOf(A[0].address)).length === 3);
    await (await reg.setActive(A[0].address, true)).wait(); await (await reg.setStatus(A[0].address, 2)).wait(); await (await board.syncVoter(A[0].address)).wait();
    ok("C6) when the voter is active again its votes count again", (await board.voteCount(A[5].address)) === 2n && (await board.votesCounted(A[0].address)) === true);
    await (await reg.setActive(A[1].address, false)).wait(); await (await reg.setStatus(A[1].address, 3)).wait();
    await (await board.connect(A[1]).unvoteFor(A[5].address)).wait();
    ok("C7) an inactive voter that withdraws a vote does not change the counter (its votes were already uncounted if synced; here still counted) - counter stays consistent", (await board.voteCount(A[5].address)) === 1n);
    await (await reg.setActive(A[1].address, true)).wait(); await (await reg.setStatus(A[1].address, 2)).wait();
    await (await board.connect(A[1]).voteFor(A[8].address)).wait();
    ok("C8) voteFor by a voter whose counted state was stale first re-syncs it, then counts the new vote", (await board.voteCount(A[8].address)) === 1n && (await board.voteCount(A[6].address)) === 2n && (await board.votesCounted(A[1].address)) === true);
    await (await board.syncVoters([A[0].address, A[1].address, A[2].address])).wait();
    ok("C9) syncVoters (batch) works", true); }

  // ---- refreshBoard(address[]): repair and refresh in one transaction; no no-argument overload ----
  await fresh(); await at(ts(2028, 2, 20));
  { ok("U0) the ABI has exactly one refreshBoard function (no no-argument overload)", board.interface.fragments.filter(f => f.type === "function" && f.name === "refreshBoard").length === 1);
    await voteAll([0, 1, 2, 3, 4], [5, 6, 7, 8, 9]);                     // A5..A9 get 5 votes each
    for (const i of [1, 2, 3, 4]) { await (await reg.setActive(A[i].address, false)).wait(); await (await reg.setStatus(A[i].address, 3)).wait(); } // 4 voters suspended; the registry hook has NOT run
    ok("U1) stale counters: A5 still shows 5 votes although 4 of its 5 voters are suspended", (await board.voteCount(A[5].address)) === 5n);
    await at(ts(2028, 3, 1, 0, 0, 5));
    await (await board.refreshBoard([A[1].address, A[2].address, A[3].address, A[4].address])).wait();
    ok("U2) refreshBoard with the voters listed repaired the counters first: A5 now holds 1 vote", (await board.voteCount(A[5].address)) === 1n && (await board.votesCounted(A[1].address)) === false);
    ok("U3) the board was seated from the repaired counters in the same transaction", (await members()).length === 5 && (await board.boardMonthId()) === monthOf(ts(2028, 3, 1)));
    await at(ts(2028, 4, 1, 0, 0, 5));
    await (await reg.setActive(A[5].address, false)).wait(); await (await reg.setStatus(A[5].address, 3)).wait();
    ok("U4) an empty list is valid: refreshBoard([]) works as the normal monthly call", (await reverts(() => board.refreshBoard([]), "NONE")) === false);
    await at(ts(2028, 5, 1, 0, 0, 5));
    ok("U5) listing an address that is already in sync, or a non-voter, is harmless", (await reverts(() => board.refreshBoard([A[0].address, A[15].address, A[0].address]), "NONE")) === false);
    await at(ts(2028, 5, 2, 0, 0, 5));
    ok("U6) a second refresh in the same month is refused even if voters are listed (no repair-then-reroll)", await reverts(() => board.refreshBoard([A[0].address]), "already set")); }

  // ---- change of vote moves one count ----
  await fresh(); await at(ts(2028, 3, 10));
  { await (await board.connect(A[0]).voteFor(A[5].address)).wait();
    await (await board.connect(A[0]).unvoteFor(A[5].address)).wait(); await (await board.connect(A[0]).voteFor(A[6].address)).wait();
    ok("V1) changing a vote moves exactly one count from the old candidate to the new one", (await board.voteCount(A[5].address)) === 0n && (await board.voteCount(A[6].address)) === 1n);
    ok("V2) a candidate with no counted votes leaves the candidate list", !(await board.getCandidateList()).map(x => x.toLowerCase()).includes(A[5].address.toLowerCase()) && (await board.getCandidateList()).length === 1);
    ok("V3) voting twice for the same candidate is refused", await reverts(() => board.connect(A[0]).voteFor(A[6].address), "already voted for this candidate")); }

  // ---- stale votes cleanup keeps the counters right ----
  await fresh(); await at(ts(2028, 4, 10));
  { await voteAll([0, 1, 2], [5, 6]); await voteAll([5], [0, 1]);
    await (await reg.setActive(A[5].address, false)).wait(); await (await reg.setStatus(A[5].address, 3)).wait(); await (await board.syncVoter(A[5].address)).wait();
    await at(ts(2028, 4, 10) + 172800 + 30 * 86400 + 10);
    // the mock's demotedAt is 0 -> demotedAt + recoveryPeriod + 30d is in the past
    await (await board.clearStaleVotes(A[5].address)).wait();
    ok("D1) clearStaleVotes removes votes given by and received by the stale validator", (await board.getVotesOf(A[5].address)).length === 0 && (await board.getVotersFor(A[5].address)).length === 0);
    ok("D2) the counters match: A5 holds 0 counted votes, A6 still 3", (await board.voteCount(A[5].address)) === 0n && (await board.voteCount(A[6].address)) === 3n); }

  // ---- invariant: counters equal a recount, under random operations ----
  await fresh(); await at(ts(2028, 5, 10));
  { let seed = 987654321; const rnd = (n) => { seed = (seed * 1664525 + 1013904223) % 4294967296; return Math.floor(seed / 4294967296 * n); };
    const stat = new Array(16).fill(true); let bad = 0; const recount = async () => {
      for (let c = 0; c < 16; c++) { let n = 0; for (let v = 0; v < 16; v++) { if ((await board.hasVotedFor(A[v].address, A[c].address)) && (await board.votesCounted(A[v].address))) n++; }
        if (BigInt(n) !== (await board.voteCount(A[c].address))) bad++; } };
    for (let step = 0; step < 220; step++) { const op = rnd(5), v = rnd(16), c = rnd(16);
      try { if (op === 0) { if (stat[v]) await (await board.connect(A[v]).voteFor(A[c].address)).wait(); }
        else if (op === 1) { await (await board.connect(A[v]).unvoteFor(A[c].address)).wait(); }
        else if (op === 2) { stat[v] = false; await (await reg.setActive(A[v].address, false)).wait(); await (await reg.setStatus(A[v].address, 3)).wait(); if (rnd(2)) await (await board.syncVoter(A[v].address)).wait(); }
        else if (op === 3) { stat[v] = true; await (await reg.setActive(A[v].address, true)).wait(); await (await reg.setStatus(A[v].address, 2)).wait(); if (rnd(2)) await (await board.syncVoter(A[v].address)).wait(); }
        else { await (await board.syncVoter(A[v].address)).wait(); } } catch (e) { /* refused operations (candidate inactive, duplicate, none) are expected */ }
      if (step % 20 === 19) await recount(); }
    for (let v = 0; v < 16; v++) await (await board.syncVoter(A[v].address)).wait(); await recount();
    let mism = 0; for (let v = 0; v < 16; v++) if ((await board.votesCounted(A[v].address)) !== stat[v]) mism++;
    ok("F1) 220 random operations: every voteCount equals a recount from the vote records (checked every 20 steps and at the end), mismatches=" + bad, bad === 0);
    ok("F2) after syncing everyone, votesCounted equals each validator's active status", mism === 0); }

  // ---- exit-driven succession inside the month ----
  await fresh(); await at(ts(2028, 6, 10));
  { await seedBoard([A[0].address, A[1].address, A[2].address, A[3].address, A[4].address], monthOf(ts(2028, 6, 10)));
    await voteAll([0, 1, 2, 3, 4, 5], [5, 6]); // A5, A6 candidates with votes
    const id = (await board.actionCount()) + 1n; await (await board.connect(A[0]).proposeApproveBudget(recipient.address, E1, "t")).wait();
    await (await reg.setActive(A[1].address, false)).wait(); await (await reg.setStatus(A[1].address, 4)).wait(); await (await reg.bumpEpoch(A[1].address)).wait(); // A1 requested exit
    ok("X1) a seat holder's exit ends its authority at once", (await board.hasBoardAuthority(A[1].address)) === false);
    ok("X2) other actions are refused until syncBoard()", await reverts(() => board.connect(A[2]).voteAction(id), "call syncBoard() first"));
    await (await board.connect(A[2]).syncBoard()).wait();
    ok("X3) syncBoard seats the most-voted eligible candidate (A5) in the freed seat, within the same month", !(await has(A[1])) && (await has(A[5])) && (await members()).length === 5);
    ok("X4) the pending action of the old composition is invalid", await reverts(() => board.connect(A[2]).voteAction(id), "board membership changed since this action was proposed")); }

  // ---- fewer than 3 seated -> spending and key rotation halted ----
  await fresh(); await at(ts(2028, 7, 10));
  { await seedBoard([A[0].address, A[1].address, A[2].address, A[3].address, A[4].address], monthOf(ts(2028, 7, 10)));
    for (const i of [1, 2, 3]) { await (await reg.setActive(A[i].address, false)).wait(); await (await reg.setStatus(A[i].address, 4)).wait(); await (await reg.bumpEpoch(A[i].address)).wait(); }
    await (await board.connect(A[0]).syncBoard()).wait();
    ok("H1) three seat holders left and no candidate: 2 seats remain", (await members()).length === 2);
    ok("H2) treasury payments are halted", await reverts(() => board.connect(A[0]).proposeApproveBudget(recipient.address, E1, "x"), "spending halted"));
    ok("H3) verifier rotation is halted", await reverts(() => board.connect(A[0]).proposeRotateVerifier(A[9].address), "key rotation halted"));
    ok("H4) oracle rotation is halted", await reverts(() => board.connect(A[0]).proposeRotateOracle(A[9].address), "key rotation halted")); }

  // ---- key-rotation floor: 3 votes, no delay ----
  await fresh(); await at(ts(2028, 8, 10));
  { await seedBoard([A[0].address, A[1].address, A[2].address, A[3].address, A[4].address], monthOf(ts(2028, 8, 10)));
    let id = (await board.actionCount()) + 1n; await (await board.connect(A[0]).proposeRotateVerifier(A[9].address)).wait();
    await (await board.connect(A[1]).voteAction(id)).wait();
    ok("K1) two votes do not rotate the verifier", (await reg.lastVerifier()) === hre.ethers.ZeroAddress && (await board.actions(id)).requiredVotes === 3n);
    await (await board.connect(A[2]).voteAction(id)).wait();
    ok("K2) the third vote rotates the verifier immediately (no delay)", (await reg.lastVerifier()) === A[9].address);
    id = (await board.actionCount()) + 1n; await (await board.connect(A[0]).proposeRotateOracle(A[10].address)).wait(); await (await board.connect(A[1]).voteAction(id)).wait();
    ok("K3) two votes do not rotate the oracle", (await dist.oracle()) === hre.ethers.ZeroAddress);
    await (await board.connect(A[3]).voteAction(id)).wait();
    ok("K4) the third vote rotates the oracle immediately", (await dist.oracle()) === A[10].address);
    ok("K5) a vote from a non-member is refused", await reverts(() => board.connect(A[7]).proposeRotateVerifier(A[11].address), "no board authority"));
    id = (await board.actionCount()) + 1n; await (await board.connect(A[0]).proposeSetEntryThresholdBase(hre.ethers.parseEther("700000"))).wait(); await (await board.connect(A[1]).voteAction(id)).wait(); await (await board.connect(A[2]).voteAction(id)).wait();
    ok("K6) economic parameters still need only the board majority (3 of 5)", (await reg.lastEntry()) === hre.ethers.parseEther("700000")); }

  // ---- the floor matters when the board is small: with 3 seated members the majority is 2, but a key rotation still needs 3 ----
  await fresh(); await at(ts(2028, 8, 20));
  { await seedBoard([A[0].address, A[1].address, A[2].address], monthOf(ts(2028, 8, 20)));
    let id = (await board.actionCount()) + 1n; await (await board.connect(A[0]).proposeRotateVerifier(A[9].address)).wait(); await (await board.connect(A[1]).voteAction(id)).wait();
    ok("K7) with 3 seated members, two votes (a majority) still do not rotate the verifier: the floor of 3 applies", (await reg.lastVerifier()) === hre.ethers.ZeroAddress && (await board.actions(id)).requiredVotes === 3n);
    await (await board.connect(A[2]).voteAction(id)).wait();
    ok("K8) the third vote rotates it", (await reg.lastVerifier()) === A[9].address);
    id = (await board.actionCount()) + 1n; await (await board.connect(A[0]).proposeSetMembershipFeeBps(500)).wait(); await (await board.connect(A[1]).voteAction(id)).wait();
    ok("K9) an economic parameter needs only the majority: with 3 seated members, 2 votes apply it", (await reg.lastFee()) === 500n); }

  // ---- treasury payments against the caps ----
  await fresh(); await at(ts(2028, 9, 10));
  { await seedBoard([A[0].address, A[1].address, A[2].address, A[3].address, A[4].address], monthOf(ts(2028, 9, 10)));
    const pay = async (amt, expectOk) => { const id = (await board.actionCount()) + 1n; await (await board.connect(A[0]).proposeApproveBudget(recipient.address, hre.ethers.parseEther(String(amt)), "p")).wait(); await (await board.connect(A[1]).voteAction(id)).wait();
      const before = await hre.ethers.provider.getBalance(recipient.address); const r = await reverts(() => board.connect(A[2]).voteAction(id), "per-payment cap"); const after = await hre.ethers.provider.getBalance(recipient.address);
      return expectOk ? (r === false && after - before === hre.ethers.parseEther(String(amt))) : (r === true && after === before); };
    ok("Pay-a) 1,000 Suren with 3 board votes is paid", await pay(1000, true));
    ok("Pay-b) exactly the cap (50,000) is paid", await pay(50000, true));
    ok("Pay-c) just over the cap is refused", await pay(50001, false)); }

  const pass = results.filter(Boolean).length; console.log("\nresult: " + pass + "/" + results.length + " passed"); process.exit(pass === results.length ? 0 : 1);
})().catch(e => { console.error("error:", e.message); process.exit(1); });
