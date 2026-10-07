// Reward-rate governance with ACTIVATION TIMESTAMPS (v2.2): a change is proposed with the unix time at which Besu applies it (the
// value operators write into the transitions of the genesis) plus an estimated start block; the oracle later certifies the actual
// start block within RATE_START_TOLERANCE_BLOCKS. REAL ValidatorsBoard (v2.1.0: monthly board, live authority, composition version)
// and REAL BlockRewardDistributor, both compiled from the Plan's contracts/ folder; Registry and Identity are checkpoint-faithful
// mocks. Hardhat, not Besu.
// Under test: two chambers (board 3 of 5 + two thirds of the validators eligible at creation), 7-day delay after BOTH chambers,
// activation time at least 7 days after the executing block (a time, not a block count), non-overlapping tolerance windows,
// full re-check at execution, and the oracle's limited power (certify only; it cannot add or change a rate).
const hre = require("hardhat"); const solc = require("solc"); const { compile } = require("./_compile.js");
const REG = "0x3333333333333333333333333333333333333333", BOARD = "0x4444444444444444444444444444444444444444", IDR = "0x6666666666666666666666666666666666666666", DIST = "0x2222222222222222222222222222222222222222";
let results = [];
function ok(n, c, x = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + n + (c === true ? "" : " → " + c) + (x ? "  " + x : "")); }
const msgOf = e => { const m = e.reason || e.shortMessage || e.message || ""; const r = m.match(/reason string '([^']*)'/); return r ? r[1] : m; };
async function reverts(fn, expected) { try { await (await fn()).wait(); return "did NOT revert"; } catch (e) { return msgOf(e).includes(expected) ? true : "wrong reason: " + msgOf(e).slice(0, 170); } }
const DAY = 86400, LEAD = 7 * DAY, W = 10000;
const ts = (y, m, d, h = 0, mi = 0, s = 0) => Math.floor(Date.UTC(y, m - 1, d, h, mi, s) / 1000);
const slotOf = (art, n) => hre.ethers.toBeHex(BigInt(art.layout.storage.find(s => s.label === n).slot));
const setS = (addr, sl, v) => hre.network.provider.send("hardhat_setStorageAt", [addr, sl, hre.ethers.zeroPadValue(hre.ethers.toBeHex(v), 32)]);
const blockNo = () => hre.ethers.provider.getBlockNumber();
const latestTs = async () => (await hre.ethers.provider.getBlock("latest")).timestamp;
const at = async (t, fn) => { await hre.network.provider.send("evm_setNextBlockTimestamp", [t]); return fn(); };
const MOCK = `pragma solidity ^0.8.24;
contract MockRegistry { address[] public vals; mapping(address=>bool) public active; mapping(address=>uint8) public st; mapping(address=>bool) public ever; mapping(address=>uint256) public activationSeq; mapping(address=>uint256) public membershipEpoch;
 function setActive(address a, bool on) external { if (on && !active[a]) { active[a]=true; ever[a]=true; vals.push(a); _cp(a,true);} else if (!on && active[a]) { active[a]=false; _cp(a,false); for (uint i=0;i<vals.length;i++) if (vals[i]==a) { vals[i]=vals[vals.length-1]; vals.pop(); break; } } }
 uint256 public statusNonce; struct Cp { uint256 n; bool a; } mapping(address=>Cp[]) cps;
 function _cp(address x, bool on) internal { statusNonce++; cps[x].push(Cp(statusNonce, on)); }
 function wasActiveAt(address x, uint256 n) external view returns (bool) { Cp[] storage c=cps[x]; bool r=false; for (uint i=0;i<c.length;i++){ if (c[i].n<=n) r=c[i].a; else break; } return r; }
 function setStatus(address a, uint8 s) external { st[a]=s; } function setSeq(address a, uint256 s) external { activationSeq[a]=s; }
 function isValidator(address a) external view returns (bool) { return active[a]; }
 function getActiveValidatorCount() external view returns (uint256) { return vals.length; }
 function getValidators() external view returns (address[] memory) { return vals; }
 function getValidatorInfo(address a) external view returns (uint8,uint256,uint256,uint256,uint256,bool) { return (st[a],0,0,0,0,false); }
 function recoveryPeriod() external pure returns (uint256) { return 172800; } }
contract MockIdentity { function hasIdentity(address) external pure returns (bool) { return true; } }`;
(async () => {
  const signers = await hre.ethers.getSigners(); const deployer = signers[0]; const oracle = signers[1]; const A = signers.slice(2, 14); const OUTSIDER = signers[15];
  const install = async (addr, abi, bc) => { const t = await new hre.ethers.ContractFactory(abi, bc, deployer).deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); };
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "M.sol": { content: MOCK } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } })));
  const mr = out.contracts["M.sol"].MockRegistry, mi = out.contracts["M.sol"].MockIdentity;
  await install(REG, mr.abi, "0x" + mr.evm.bytecode.object); await install(IDR, mi.abi, "0x" + mi.evm.bytecode.object);
  const b = compile("ValidatorsBoard.sol", "ValidatorsBoard"), dArt = compile("BlockRewardDistributor.sol", "BlockRewardDistributor");
  await install(BOARD, b.abi, b.bytecode); await install(DIST, dArt.abi, dArt.bytecode);
  await setS(BOARD, slotOf(b, "boardVersion"), 1); await setS(DIST, slotOf(dArt, "distributionOracle"), BigInt(oracle.address));
  const reg = new hre.ethers.Contract(REG, mr.abi, deployer), board = new hre.ethers.Contract(BOARD, b.abi, deployer);
  for (let i = 0; i < 10; i++) { await (await reg.setActive(A[i].address, true)).wait(); await (await reg.setStatus(A[i].address, 2)).wait(); await (await reg.setSeq(A[i].address, i + 1)).wait(); }
  for (let v = 0; v < 10; v++) for (const c of (v < 6 ? [0, 1, 2, 3, 4] : [0, 1, 2, 3, 5])) await (await board.connect(A[v]).voteFor(A[c].address)).wait();
  const T0 = ts(2027, 3, 1, 0, 0, 30); await at(T0, async () => board.refreshBoard([])); // the month's board is seated on 1 March 2027
  const d = w => new hre.ethers.Contract(DIST, dArt.abi, w);
  let snap = await hre.network.provider.send("evm_snapshot");
  const fresh = async () => { await hre.network.provider.send("evm_revert", [snap]); snap = await hre.network.provider.send("evm_snapshot"); };
  const P = id => d(deployer).rateProposals(id), status = async id => { const [s, p] = await d(deployer).rateChangeStatus(id); return [Number(s), Number(p)]; };
  const approve = async id => { const need = Number((await P(id)).requiredValidatorApprovals); for (let i = 0; i < 3; i++) await (await d(A[i]).boardVoteRateChange(id)).wait(); for (let i = 0; i < need; i++) await (await d(A[i]).validatorVoteRateChange(id)).wait(); return Number((await P(id)).approvedAt); };
  // propose at block timestamp `t` an activation time `T` and estimate `E`
  const propose = async (t, T, Eb, rate, who = A[0]) => { await at(t, () => d(who).proposeRateChange(T, Eb, rate, { gasLimit: 800000 }).then(x => x.wait())); return Number(await d(deployer).rateProposalCount()); };
  const entry = async i => { const [sb, rt, ac, ce] = await d(deployer).rewardRateChange(i); return { sb: Number(sb), rt, ac: Number(ac), ce }; };
  ok("R0) real Board seated A0..A4 for March 2027; boardVersion 2; 10 validators active", (await board.boardVersion()) === 2n && (await board.getBoardMembers()).length === 5 && (await reg.getActiveValidatorCount()) === 10n && (await board.boardMonthId()) === BigInt(2027 * 12 + 2));

  console.log("\n=== G — constants and who can write the history ===");
  ok("G1) constants: board 3 of 5, voting 30 d, delay 7 d, lead 7 days (seconds), tolerance 10,000 blocks",
    (await d(deployer).RATE_CHANGE_BOARD_APPROVALS()) === 3n && (await d(deployer).RATE_VOTING_EXPIRY()) === BigInt(30 * DAY) && (await d(deployer).RATE_CHANGE_DELAY()) === BigInt(7 * DAY) && (await d(deployer).MIN_RATE_CHANGE_LEAD_SECONDS()) === BigInt(LEAD) && (await d(deployer).RATE_START_TOLERANCE_BLOCKS()) === BigInt(W));
  ok("G2) the old block-count lead constant no longer exists", !dArt.abi.some(x => x.name === "MIN_RATE_CHANGE_LEAD_BLOCKS"));
  const writers = dArt.abi.filter(x => x.type === "function" && x.stateMutability !== "view" && x.stateMutability !== "pure" && /rate/i.test(x.name)).map(x => x.name).sort();
  ok("G3) state-changing rate functions: propose, boardVote, validatorVote, execute, certify (the oracle has no setter for rates)", JSON.stringify(writers) === JSON.stringify(["boardVoteRateChange", "certifyRateStart", "executeRateChange", "proposeRateChange", "validatorVoteRateChange"]));

  console.log("\n=== P — proposing (activation time in seconds, estimate in blocks) ===");
  const tP = T0 + 600; let head = await blockNo();
  ok("P1) a non-validator cannot propose", await reverts(() => at(tP, () => d(OUTSIDER).proposeRateChange(tP + LEAD + DAY, head + 5000, 5, { gasLimit: 500000 })), "only an active validator may propose a rate change"));
  ok("P2) the distribution oracle (not a validator) cannot propose either", await reverts(() => at(tP + 1, () => d(oracle).proposeRateChange(tP + LEAD + DAY, head + 5000, 5, { gasLimit: 500000 })), "only an active validator may propose a rate change"));
  ok("P3) activation time = executing block time + 7 days - 1 second rejected", await reverts(() => at(tP + 2, () => d(A[0]).proposeRateChange(tP + 2 + LEAD - 1, (head += 1) + 5000, 5, { gasLimit: 500000 })), "closer than MIN_RATE_CHANGE_LEAD_SECONDS"));
  head = await blockNo();
  ok("P4) activation time not in the future (= block time) rejected with its own message", await reverts(() => at(tP + 3, () => d(A[0]).proposeRateChange(tP + 3, head + 5000, 5, { gasLimit: 500000 })), "activation time is not in the future"));
  head = await blockNo();
  ok("P5) estimated start block not in the future (= head) rejected with its own message", await reverts(() => at(tP + 4, () => d(A[0]).proposeRateChange(tP + 4 + LEAD + DAY, head, 5, { gasLimit: 500000 })), "estimated start block is not in the future"));
  ok("P6) activation time above uint64 and rate above uint128 rejected", await reverts(() => d(A[0]).proposeRateChange(2n ** 64n, head + 5000, 5, { gasLimit: 500000 }), "does not fit its type") === true && await reverts(() => d(A[0]).proposeRateChange(tP + 10 * DAY, head + 5000, 2n ** 128n, { gasLimit: 500000 }), "does not fit its type") === true);
  head = await blockNo(); const tB = tP + 100; // exact boundary: activation = block time + 7 days
  { const id = await propose(tB, tB + LEAD, head + 1 + 5000, 5); const p = await P(id);
    ok("P7) activation time = executing block time + 7 days accepted (exact boundary); stored activation time and estimate", id === 1 && Number(p.activationTime) === tB + LEAD && Number(p.startBlock) === head + 1 + 5000 && p.ratePerBlock === 5n); }
  await fresh();

  console.log("\n=== V — lifecycle: propose, two chambers, delay, execute (provisional entry) ===");
  const t1 = T0 + 1200; head = await blockNo(); const E1 = head + 1 + 1500, T1 = T0 + 26 * DAY;
  const id1 = await propose(t1, T1, E1, hre.ethers.parseEther("3"));
  { const rc = await (await d(deployer).queryFilter(d(deployer).filters.RateChangeProposed(id1)))[0];
    ok("V1) RateChangeProposed carries activation time, estimated block, rate and proposer", rc && Number(rc.args.activationTime) === T1 && Number(rc.args.estimatedStartBlock) === E1 && rc.args.ratePerBlock === hre.ethers.parseEther("3") && rc.args.proposer === A[0].address); }
  ok("V2) status: voting (1, 0)", JSON.stringify(await status(id1)) === JSON.stringify([1, 0]));
  const approvedAt = await at(t1 + 60, async () => approve(id1)).catch(e => { throw e; });
  ok("V3) both chambers complete: approved; status 4 (waiting for the delay)", approvedAt > 0 && JSON.stringify(await status(id1)) === JSON.stringify([4, 0]));
  ok("V4) execution before the 7-day delay is rejected", await reverts(() => at(approvedAt + 6 * DAY, () => d(deployer).executeRateChange(id1, { gasLimit: 500000 })), "execution delay has not elapsed"));
  const tExec = approvedAt + 7 * DAY + 5;
  { const rc = await (await at(tExec, () => d(deployer).executeRateChange(id1))).wait(); const e0 = await entry(0);
    ok("V5) execution after the delay: history has one entry, provisional, with the proposed activation time, estimate and rate", rc.status === 1 && (await d(deployer).rewardRateChangeCount()) === 1n && e0.sb === E1 && e0.ac === T1 && e0.rt === hre.ethers.parseEther("3") && e0.ce === false); }
  ok("V6) executing twice is rejected", await reverts(() => d(deployer).executeRateChange(id1, { gasLimit: 500000 }), "already executed"));
  ok("V7) status 3 (executed)", JSON.stringify(await status(id1)) === JSON.stringify([3, 0]));
  ok("V8) provisional cap: the larger rate (3 SUR) applies inside the window, 2 SUR before it would (estimate is inside the first 10,000 blocks, so from block 1)", (await d(deployer).rewardRateAt(1)) === hre.ethers.parseEther("3") && (await d(deployer).maxRewardsForRange(E1 + W, E1 + W + 4)) === hre.ethers.parseEther("15"));

  console.log("\n=== X — a change whose activation time is too close at execution stays unexecuted ===");
  await fresh(); head = await blockNo();
  { const tc = T0 + 1200; const idx = await propose(tc, tc + 10 * DAY, head + 1 + 3000, hre.ethers.parseEther("1")); const ap = await at(tc + 60, async () => approve(idx));
    ok("X1) at execution (approval + 7 days) the activation time is only 3 days away: rejected", await reverts(() => at(ap + 7 * DAY + 5, () => d(deployer).executeRateChange(idx, { gasLimit: 500000 })), "closer than MIN_RATE_CHANGE_LEAD_SECONDS"));
    ok("X2) status: approved but currently unexecutable (6, 3) — the proposal is left exactly as it is", JSON.stringify(await status(idx)) === JSON.stringify([6, 3]) && (await d(deployer).rewardRateChangeCount()) === 0n); }
  await fresh(); head = await blockNo();
  { const tc = T0 + 1200; const idx = await propose(tc, tc + 8 * DAY, head + 1 + 3000, hre.ethers.parseEther("1"));
    await hre.network.provider.send("evm_setNextBlockTimestamp", [tc + 2 * DAY]); await hre.network.provider.send("evm_mine");
    ok("X3) not yet approved and the activation time is now less than 7 days away: status (7, 3), voting can no longer lead to a change", JSON.stringify(await status(idx)) === JSON.stringify([7, 3])); }

  console.log("\n=== O — ordering and non-overlapping tolerance windows (history built from V) ===");
  await fresh(); head = await blockNo(); const E1o = head + 1 + 1500, T1o = T0 + 26 * DAY;
  { const i1 = await propose(T0 + 1200, T1o, E1o, hre.ethers.parseEther("3")); const ap = await at(T0 + 1260, async () => approve(i1)); await at(ap + 7 * DAY + 5, () => d(deployer).executeRateChange(i1).then(x => x.wait()));
    const now = await latestTs(); const hd = await blockNo();
    ok("O1) a later change with an activation time not after the last one is rejected", await reverts(() => at(now + 1, () => d(A[0]).proposeRateChange(T1o, E1o + 3 * W, 1, { gasLimit: 500000 })), "must be after the last approved rate change"));
    ok("O2) estimate = last estimate + 2 x tolerance (windows touch/overlap) rejected", await reverts(() => at(now + 2, () => d(A[0]).proposeRateChange(T1o + DAY, E1o + 2 * W, 1, { gasLimit: 500000 })), "must be after the last approved rate change"));
    { const rc = await (await at(now + 3, () => d(A[0]).proposeRateChange(T1o + DAY, E1o + 2 * W + 1, 1))).wait(); ok("O3) estimate = last estimate + 2 x tolerance + 1 (non-overlapping) accepted", rc.status === 1); }
    // certification shrinks the previous window: after certifying the first change at E1o + 4000 the next estimate only has to exceed that + tolerance
    await hre.network.provider.send("hardhat_mine", ["0x" + (6000).toString(16)]);
    await at(T1o, async () => d(oracle).certifyRateStart(0, E1o + 4000).then(x => x.wait()));
    const n2 = await latestTs() + 1;
    ok("O4) after certification at E1o+4000 the next estimate must exceed E1o+4000+10,000: E1o+14,000 rejected", await reverts(() => at(n2, () => d(A[0]).proposeRateChange(T1o + 10 * DAY, E1o + 4000 + W, 1, { gasLimit: 500000 })), "must be after the last approved rate change"));
    { const rc = await (await at(n2 + 1, () => d(A[0]).proposeRateChange(T1o + 10 * DAY, E1o + 4000 + W + 1, 1))).wait(); ok("O5) E1o+14,001 accepted", rc.status === 1); } }

  console.log("\n=== C — certification by the oracle ===");
  await fresh(); head = await blockNo(); const E1c = head + 1 + 1500, T1c = T0 + 26 * DAY;
  { const i1 = await propose(T0 + 1200, T1c, E1c, hre.ethers.parseEther("3")); const ap = await at(T0 + 1260, async () => approve(i1)); await at(ap + 7 * DAY + 5, () => d(deployer).executeRateChange(i1).then(x => x.wait()));
    ok("C1) only the oracle can certify", await reverts(() => d(A[0]).certifyRateStart(0, E1c + 100, { gasLimit: 300000 }), "caller is not the distribution oracle"));
    ok("C2) certification before the activation time is rejected", await reverts(() => d(oracle).certifyRateStart(0, E1c + 100, { gasLimit: 300000 }), "activation time has not been reached"));
    await hre.network.provider.send("hardhat_mine", ["0x" + (12000).toString(16)]); // head above estimate + tolerance, so the tolerance check is the one that fires
    ok("C3) a start block more than 10,000 blocks from the estimate is rejected", await reverts(() => at(T1c, () => d(oracle).certifyRateStart(0, E1c + W + 1, { gasLimit: 300000 })), "outside the tolerance window"));
    { const hd = await blockNo(); ok("C3b) a start block above the head is rejected as in the future", await reverts(() => at(T1c + 2, () => d(oracle).certifyRateStart(0, hd + 50, { gasLimit: 300000 })), "start block is in the future")); }
    const rc = await (await at(T1c + 5, () => d(oracle).certifyRateStart(0, E1c + 4000))).wait(); const ev = rc.logs.map(l => { try { return d(deployer).interface.parseLog(l); } catch (e) { return null; } }).find(e => e && e.name === "RateStartCertified"); const e0 = await entry(0);
    ok("C4) certification at estimate + 4,000 accepted: event, stored start block, certified, activation time unchanged", rc.status === 1 && ev && Number(ev.args.actualStartBlock) === E1c + 4000 && e0.sb === E1c + 4000 && e0.ce === true && e0.ac === T1c);
    ok("C5) a second certification is rejected", await reverts(() => d(oracle).certifyRateStart(0, E1c + 4000, { gasLimit: 300000 }), "already certified"));
    ok("C6) after certification the cap is exact at the certified block: [E1c+3999] = 2 SUR, [E1c+4000] = 3 SUR",
      (await d(deployer).rewardRateAt(E1c + 3999)) === hre.ethers.parseEther("2") && (await d(deployer).rewardRateAt(E1c + 4000)) === hre.ethers.parseEther("3")); }

  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
