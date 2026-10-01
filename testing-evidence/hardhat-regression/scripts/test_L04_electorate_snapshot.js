// L04 (owner decision 2026-09-30) — electorate snapshot at proposal creation. Hardhat, not Besu.
//  * only those eligible when the proposal was created may vote; quorum frozen at creation by each path's EXISTING formula
//  * members added/activated later may not vote on it; a recorded vote stays; an exited member gets no new vote
//  * joins/exits never invalidate a proposal
//  * suspension: a voter eligible at creation who is suspended cannot vote while suspended; after recovery may vote,
//    if still Active, has not voted, and the proposal is valid & unexpired. Suspension never deletes a recorded vote.
// Parts: F = REAL FoundationDAO, R = REAL ValidatorsRegistry (both on storage produced by the project's genesis seed helpers,
// placeholder addresses replaced by test signers); T/D = REAL ValidatorsTreasury / BlockRewardDistributor wired to a
// checkpoint-faithful mock Registry at the fixed address 0x3333 (they only consume statusNonce()/wasActiveAt()).
// Usage: CONTRACTS_DIR=<contracts|contracts-fa> npx hardhat run scripts/test_L04_electorate_snapshot.js
const hre = require("hardhat"); const fs = require("fs"); const path = require("path"); const solc = require(process.env.SOLC_PATH || "solc");
const DIR = process.env.CONTRACTS_DIR || "../../contracts";
const REG = "0x3333333333333333333333333333333333333333", BOARD = "0x4444444444444444444444444444444444444444",
      TRES = "0x5555555555555555555555555555555555555555", DIST = "0x2222222222222222222222222222222222222222",
      IDR = "0x6666666666666666666666666666666666666666", FOUND = "0x1111111111111111111111111111111111111111";
let results = [];
function ok(n, c, x = "") { results.push(c === true); console.log((c === true ? "✅ " : "❌ ") + n + (c === true ? "" : " → " + c) + (x ? "  " + x : "")); }
const msgOf = e => { const m = e.reason || e.shortMessage || e.message || ""; const r = m.match(/reason string '([^']*)'/); return r ? r[1] : m; };
async function reverts(fn, expected) { try { await (await fn()).wait(); return "did NOT revert"; } catch (e) { return msgOf(e).includes(expected) ? true : "wrong reason: " + msgOf(e).slice(0, 170); } }
const inc = async s => { await hre.network.provider.send("evm_increaseTime", [s]); await hre.network.provider.send("evm_mine"); };
function compile(files) {
  const sources = {}; for (const [k, v] of Object.entries(files)) sources[k] = { content: v };
  const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources, settings: { optimizer: { enabled: true, runs: 200 }, outputSelection: { "*": { "*": ["abi", "evm.bytecode.object", "evm.deployedBytecode.object", "storageLayout"] } } } }),
    { import: p => { const f = path.join(DIR, path.basename(p)); return fs.existsSync(f) ? { contents: fs.readFileSync(f, "utf8") } : { error: "nf " + p }; } }));
  const errs = (out.errors || []).filter(e => e.severity === "error"); if (errs.length) throw new Error(errs.map(e => e.formattedMessage).join("\n"));
  return out.contracts;
}
const patchHelper = (src, signers) => { let i = 0; return [src.replace(/address\(0\)(,?)(\s*)\/\/ /g, (_, c, sp) => signers[i++].address + c + sp + "// "), i]; };
async function realOnSeed(helperSrc, helperName, realSrc, realName, deployer) {
  const c = compile({ "H.sol": helperSrc, [realName + ".sol"]: realSrc });
  const h = c["H.sol"][helperName], r = c[realName + ".sol"][realName];
  const inst = await new hre.ethers.ContractFactory(h.abi, "0x" + h.evm.bytecode.object, deployer).deploy(); await inst.waitForDeployment();
  const addr = await inst.getAddress(); await hre.network.provider.send("hardhat_setCode", [addr, "0x" + r.evm.deployedBytecode.object]);
  return { addr, abi: r.abi, layout: r.storageLayout };
}
const automine = on => hre.network.provider.send("evm_setAutomine", [on]);
(async () => {
  const S = await hre.ethers.getSigners(); const dep = S[0];
  console.log(`source dir: ${DIR}  solc ${solc.version()}`);
  let snap0 = await hre.network.provider.send("evm_snapshot");

  // ============================================================ F: FoundationDAO (real)
  console.log("\n=== F — FoundationDAO ===");
  const [fh, nF] = patchHelper(fs.readFileSync(path.join(DIR, "genesis-seed-helpers/FoundationDAO_GenesisSeed.sol"), "utf8"), S.slice(1));
  const F = await realOnSeed(fh, "FoundationDAO_GenesisSeed", fs.readFileSync(path.join(DIR, "FoundationDAO.sol"), "utf8"), "FoundationDAO", dep);
  const M = S.slice(1, 16), X = S[17], Y = S[18];
  const dao = w => new hre.ethers.Contract(F.addr, F.abi, w);
  const meta = async id => await dao(dep).getProposalMeta(id);
  const passAdd = async (who, name) => { await (await dao(M[0]).proposeAddMember("add", name, who.address)).wait(); const id = await dao(dep).proposalCount(); const need = (await meta(id)).requiredVotes; let v = (await dao(dep).getProposal(id)).votes; for (let k = 1; v < need; k++) { if (!(await dao(dep).hasVoted(id, M[k].address)) && (await dao(dep).isMember(M[k].address))) { await (await dao(M[k]).vote(id)).wait(); v++; } } return id; };
  const passRemove = async (who) => { await (await dao(M[1]).proposeRemoveMember("rm", who.address)).wait(); const id = await dao(dep).proposalCount(); const need = (await meta(id)).requiredVotes; let v = (await dao(dep).getProposal(id)).votes; for (let k = 2; v < need; k++) { if (M[k].address !== who.address && !(await dao(dep).hasVoted(id, M[k].address)) && (await dao(dep).isMember(M[k].address))) { await (await dao(M[k]).vote(id)).wait(); v++; } } return id; };
  ok("F0) 15 genesis members seeded; membershipNonce = 0", nF === 15 && (await dao(dep).membershipNonce()) === 0n);
  await (await dao(M[0]).proposeSendETH("P", M[0].address, 1)).wait(); const P = await dao(dep).proposalCount();
  const reqP = (await meta(P)).requiredVotes;
  ok("F1) genesis member can vote on P (memberSinceNonce 0 <= createdAtNonce 0)", (await (await dao(M[1]).vote(P)).wait()).status === 1);
  await passAdd(X, "X");
  ok("F2) X added after P was created cannot vote on P", await reverts(() => dao(X).vote(P), "not eligible - not a member when this proposal was created"));
  await (await dao(M[0]).proposeSendETH("Q", M[0].address, 1)).wait(); const Q = await dao(dep).proposalCount();
  ok("F3) X can vote on a proposal created after its admission", (await (await dao(X).vote(Q)).wait()).status === 1);
  // M[2] votes on P, is then removed: vote stays, no new vote
  await (await dao(M[2]).vote(P)).wait(); const votesBefore = (await dao(dep).getProposal(P)).votes;
  await passRemove(M[2]);
  ok("F4) removed member's earlier vote on P is still counted", (await dao(dep).getProposal(P)).votes === votesBefore);
  ok("F5) removed member cannot vote again (onlyMember)", await reverts(() => dao(M[2]).vote(Q), "not a member"));
  ok("F6) P still Pending and quorum unchanged after add+remove (not invalidated)", Number((await dao(dep).getProposal(P)).status) === 0 && (await meta(P)).requiredVotes === reqP);
  // re-add M[2]: becomes a NEW member for older proposals
  await passAdd(M[2], "M2-again");
  // Q was created before M2's re-admission and M2 never voted on Q (on P it had already voted -> "already voted" would fire first)
  ok("F7) re-added member cannot vote on Q (created before re-admission, never voted by it)", await reverts(() => dao(M[2]).vote(Q), "not eligible - not a member when this proposal was created"));
  await (await dao(M[0]).proposeSendETH("R", M[0].address, 1)).wait(); const Rr = await dao(dep).proposalCount();
  ok("F8) re-added member can vote on a proposal created after re-admission", (await (await dao(M[2]).vote(Rr)).wait()).status === 1);
  ok("F9) double vote rejected", await reverts(() => dao(M[1]).vote(P), "already voted"));
  // same-block ordering: AddMember executes and SendETH proposal is created in ONE block — both orders
  for (const order of ["create-then-add", "add-then-create"]) {
    const s = await hre.network.provider.send("evm_snapshot");
    await (await dao(M[0]).proposeAddMember("addY", "Y", Y.address)).wait(); const A = await dao(dep).proposalCount();
    const need = (await meta(A)).requiredVotes; let v = (await dao(dep).getProposal(A)).votes; let k = 1; const voters = [];
    while (v < need - 1n) { if ((await dao(dep).isMember(M[k].address)) && !(await dao(dep).hasVoted(A, M[k].address))) { await (await dao(M[k]).vote(A)).wait(); v++; } k++; }
    while (!(await dao(dep).isMember(M[k].address)) || (await dao(dep).hasVoted(A, M[k].address))) k++;
    const last = M[k];
    await automine(false);
    const tCreate = () => dao(M[0]).proposeSendETH("SB", M[0].address, 1, { gasLimit: 1_000_000 });
    const tAdd = () => dao(last).vote(A, { gasLimit: 1_000_000 });
    if (order === "create-then-add") { await tCreate(); await tAdd(); } else { await tAdd(); await tCreate(); }
    await hre.network.provider.send("evm_mine"); await automine(true);
    const SB = await dao(dep).proposalCount();
    const isY = await dao(dep).isMember(Y.address);
    const r = await reverts(() => dao(Y).vote(SB), "not eligible");
    ok(`F10.${order}) same block: Y is member=${isY}; Y ${order === "create-then-add" ? "may NOT" : "MAY"} vote on SB`,
       isY && (order === "create-then-add" ? r === true : r === "did NOT revert"));
    await hre.network.provider.send("evm_revert", [s]);
  }

  // ============================================================ R: ValidatorsRegistry (real)
  await hre.network.provider.send("evm_revert", [snap0]); snap0 = await hre.network.provider.send("evm_snapshot");
  console.log("\n=== R — ValidatorsRegistry ===");
  const V = S.slice(1, 8), NEWV = S[9], VER = S[10], outsider = S[11];
  const [rh, nR] = patchHelper(fs.readFileSync(path.join(DIR, "genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol"), "utf8"), V);
  const RG = await realOnSeed(rh, "ValidatorsRegistry_GenesisSeed", fs.readFileSync(path.join(DIR, "ValidatorsRegistry.sol"), "utf8"), "ValidatorsRegistry", dep);
  const reg = w => new hre.ethers.Contract(RG.addr, RG.abi, w);
  const vslot = BigInt(RG.layout.storage.find(x => x.label === "verifier").slot);
  await hre.network.provider.send("hardhat_setStorageAt", [RG.addr, hre.ethers.toBeHex(vslot), hre.ethers.zeroPadValue(VER.address, 32)]);
  // entry parameters are genesis-overlay values (zero in helper-seeded storage) -> set them as a real genesis would
  for (const [label, val] of [["maxEntriesPerWindow", 10], ["entryWindowSeconds", 86400]]) {
    const sl = RG.layout.storage.find(x => x.label === label); if (!sl) throw new Error("no slot " + label);
    await hre.network.provider.send("hardhat_setStorageAt", [RG.addr, hre.ethers.toBeHex(BigInt(sl.slot)), hre.ethers.zeroPadValue(hre.ethers.toBeHex(val), 32)]); }
  // mock at the fixed Distributor address so requestMembership's fee call (if any) cannot fail
  const sink = compile({ "K.sol": "pragma solidity ^0.8.24; contract K { function receiveMembershipFee() external payable {} receive() external payable {} }" })["K.sol"].K;
  { const t = await new hre.ethers.ContractFactory(sink.abi, "0x" + sink.evm.bytecode.object, dep).deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [DIST, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); }
  const all = [...V, NEWV];
  const invariant = async tag => { const set = new Set((await reg(dep).getValidators()).map(a => a.toLowerCase())); for (const s of all) { if ((await reg(dep).isValidator(s.address)) !== set.has(s.address.toLowerCase())) return `${tag}: mismatch for ${s.address}`; } return true; };
  const suspend = async who => { const id = await reg(VER).recordSuspension.staticCall(who.address, hre.ethers.ZeroHash); await (await reg(VER).recordSuspension(who.address, hre.ethers.ZeroHash)).wait(); return id; };
  const recover = async (who, decIds) => { await inc(3601); for (const d of decIds) { try { await (await reg(dep).resolveMassFailureCheck(d)).wait(); } catch (e) {} } await (await reg(VER).recordRecovery(who.address, hre.ethers.ZeroHash)).wait(); };
  const propose = async who => { await (await reg(who).proposeParameterChange(2, 777)).wait(); return await reg(dep).paramProposalCount(); };
  ok("R0) 7 founders seeded; statusNonce = 0; invariant isValidator ⇔ getValidators holds at genesis", nR === 7 && (await reg(dep).statusNonce()) === 0n && (await invariant("genesis")) === true);
  ok("R1) no history -> wasActiveAt(outsider, any) = false", (await reg(dep).wasActiveAt(outsider.address, 0)) === false && (await reg(dep).wasActiveAt(outsider.address, 999)) === false);
  ok("R2) founder seeded checkpoint {0,true}: wasActiveAt(founder, 0) = true", (await reg(dep).wasActiveAt(V[3].address, 0)) === true);
  const P1 = await propose(V[0]); const p1 = await reg(dep).paramProposals(P1);
  ok("R3) quorum frozen by the existing formula (active/2 + 1 = 4) and createdAtNonce recorded", p1.requiredVotes === 4n && p1.createdAtNonce === 0n);
  // V[1] votes, then is suspended and recovered: vote stays, cannot vote twice
  await (await reg(V[1]).voteParameterChange(P1)).wait();
  const d1 = await suspend(V[1]); const d2 = await suspend(V[2]); // 2 of 7 -> mass failure, slash paused -> recovery allowed
  const n1 = await reg(dep).statusNonce();
  ok("R4) exact nonce boundary: wasActiveAt(V1, n-1 of its change) true, at its change false", (await reg(dep).wasActiveAt(V[1].address, 0)) === true && (await reg(dep).wasActiveAt(V[1].address, 1)) === false);
  ok("R5) invariant holds after two suspensions", (await invariant("after suspensions")) === true);
  ok("R6) suspended voter cannot vote while suspended", await reverts(() => reg(V[2]).voteParameterChange(P1), "not an active validator"));
  const P2 = await propose(V[0]); // created while V[2] is suspended
  await recover(V[2], [d1, d2]);
  ok("R7) invariant holds after recovery", (await invariant("after recovery")) === true);
  ok("R8) eligible-at-creation voter, suspended then recovered, may vote (P1)", (await (await reg(V[2]).voteParameterChange(P1)).wait()).status === 1);
  ok("R9) suspended AT creation (P2), recovered later -> not eligible", await reverts(() => reg(V[2]).voteParameterChange(P2), "not eligible - not Active when this proposal was created"));
  await recover(V[1], []);
  ok("R10) voter who voted before suspension cannot vote again after recovery", await reverts(() => reg(V[1]).voteParameterChange(P1), "already voted"));
  ok("R11) suspension did not delete the recorded vote (P1 votes = 3: V0, V1, V2)", (await reg(dep).paramProposals(P1)).votes === 3n);
  // new member activated after P1
  const cost = (await reg(dep).currentEntryThreshold()) + (await reg(dep).currentMembershipFee());
  await (await reg(NEWV).requestMembership({ value: cost })).wait(); await inc(1);
  await (await reg(VER).recordActivation(NEWV.address, hre.ethers.ZeroHash)).wait();
  ok("R12) invariant holds after a new activation", (await invariant("after activation")) === true);
  ok("R13) validator activated after P1 cannot vote on P1", await reverts(() => reg(NEWV).voteParameterChange(P1), "not eligible - not Active when this proposal was created"));
  const P3 = await propose(V[0]);
  ok("R14) ...but can vote on a proposal created after its activation", (await (await reg(NEWV).voteParameterChange(P3)).wait()).status === 1);
  // exit after voting
  await (await reg(V[4]).voteParameterChange(P3)).wait(); const vP3 = (await reg(dep).paramProposals(P3)).votes;
  await (await reg(V[4]).requestExit()).wait();
  ok("R15) exited voter's vote stays counted", (await reg(dep).paramProposals(P3)).votes === vP3);
  ok("R16) exited validator cannot vote", await reverts(() => reg(V[4]).voteParameterChange(P1), "not an active validator"));
  ok("R17) invariant holds after exit", (await invariant("after exit")) === true);
  // while still Exiting the status check fires first ("already registered"); after withdrawStake() permanentlyExited fires ("may not rejoin")
  { const r = await reverts(() => reg(V[4]).requestMembership({ value: cost }), "already registered"); const r2 = r === true ? true : await reverts(() => reg(V[4]).requestMembership({ value: cost }), "may not rejoin");
    ok("R18) exited address cannot re-register", r === true || r2 === true, `${r}`); }
  // multiple consecutive transitions: full history check at every nonce
  const d3 = await suspend(V[5]); const d4 = await suspend(V[6]); await recover(V[5], [d3, d4]); const d5 = await suspend(V[5]); const d6 = await suspend(V[3]); await recover(V[5], [d5, d6]);
  const hist = []; const last = Number(await reg(dep).statusNonce());
  for (let n = 0; n <= last; n++) hist.push((await reg(dep).wasActiveAt(V[5].address, n)) ? 1 : 0);
  const seq = hist.join(""); let transitions = 0; for (let i = 1; i < hist.length; i++) if (hist[i] !== hist[i - 1]) transitions++;
  ok("R19) consecutive transitions: V5 history is 1→0→1→0→1 across nonces (4 boundaries)", seq.startsWith("1") && seq.endsWith("1") && transitions === 4, `seq=${seq}`);
  // same block: activation of a candidate vs proposal creation, both orders
  for (const order of ["create-then-activate", "activate-then-create"]) {
    const s = await hre.network.provider.send("evm_snapshot");
    const C = S[12]; await (await reg(C).requestMembership({ value: cost })).wait(); await inc(1);
    await automine(false);
    const tC = () => reg(V[0]).proposeParameterChange(2, 555, { gasLimit: 2_000_000 });
    const tA = () => reg(VER).recordActivation(C.address, hre.ethers.ZeroHash, { gasLimit: 2_000_000 });
    if (order === "create-then-activate") { await tC(); await tA(); } else { await tA(); await tC(); }
    await hre.network.provider.send("evm_mine"); await automine(true);
    const PX = await reg(dep).paramProposalCount(); const r = await reverts(() => reg(C).voteParameterChange(PX), "not eligible");
    ok(`R20.${order}) same block: C ${order === "create-then-activate" ? "may NOT" : "MAY"} vote`, order === "create-then-activate" ? r === true : r === "did NOT revert");
    await hre.network.provider.send("evm_revert", [s]);
  }

  // ============================================================ T/D: Treasury + Distributor (real) with checkpoint-faithful mock
  await hre.network.provider.send("evm_revert", [snap0]);
  console.log("\n=== T/D — ValidatorsTreasury and BlockRewardDistributor (validator chamber) ===");
  const MOCK = `pragma solidity ^0.8.24;
  contract MockRegistry { mapping(address=>bool) public act; address[] vals; uint256 public statusNonce; struct Cp { uint256 n; bool a; } mapping(address=>Cp[]) cps;
    function setActive(address x, bool on) external { if (act[x]==on) return; act[x]=on; statusNonce++; cps[x].push(Cp(statusNonce,on)); if (on) vals.push(x); else { for (uint i=0;i<vals.length;i++) if (vals[i]==x) { vals[i]=vals[vals.length-1]; vals.pop(); break; } } }
    function isValidator(address x) external view returns (bool) { return act[x]; }
    function everActivated(address x) external view returns (bool) { return cps[x].length>0; }
    function getValidators() external view returns (address[] memory) { return vals; }
    function getActiveValidatorCount() external view returns (uint256) { return vals.length; }
    function wasActiveAt(address x, uint256 n) external view returns (bool) { Cp[] storage c=cps[x]; bool r=false; for (uint i=0;i<c.length;i++){ if (c[i].n<=n) r=c[i].a; else break; } return r; } }
  contract MockBoard { uint256 public boardVersion = 1; function isBoardMember(address) external pure returns (bool) { return true; } function hasBoardAuthority(address) external pure returns (bool) { return true; } }`;
  const mk = compile({ "M.sol": MOCK })["M.sol"];
  const put = async (addr, abi, bc) => { const t = await new hre.ethers.ContractFactory(abi, bc, dep).deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); };
  await put(REG, mk.MockRegistry.abi, "0x" + mk.MockRegistry.evm.bytecode.object); await put(BOARD, mk.MockBoard.abi, "0x" + mk.MockBoard.evm.bytecode.object);
  const core = compile({ "T.sol": fs.readFileSync(path.join(DIR, "ValidatorsTreasury.sol"), "utf8"), "B.sol": fs.readFileSync(path.join(DIR, "BlockRewardDistributor.sol"), "utf8") });
  await hre.network.provider.send("hardhat_setCode", [TRES, "0x" + core["T.sol"].ValidatorsTreasury.evm.deployedBytecode.object]);
  await hre.network.provider.send("hardhat_setCode", [DIST, "0x" + core["B.sol"].BlockRewardDistributor.evm.deployedBytecode.object]);
  const bl = core["B.sol"].BlockRewardDistributor.storageLayout.storage.find(x => x.label === "validatorDirectShareBps");
  await hre.network.provider.send("hardhat_setStorageAt", [DIST, hre.ethers.toBeHex(BigInt(bl.slot)), hre.ethers.zeroPadValue(hre.ethers.toBeHex(5000), 32)]);
  const mreg = new hre.ethers.Contract(REG, mk.MockRegistry.abi, dep);
  const tre = w => new hre.ethers.Contract(TRES, core["T.sol"].ValidatorsTreasury.abi, w), dis = w => new hre.ethers.Contract(DIST, core["B.sol"].BlockRewardDistributor.abi, w);
  const W = S.slice(1, 7); for (const w of W) await (await mreg.setActive(w.address, true)).wait();
  await (await tre(W[0]).proposeCapChange(0, hre.ethers.parseEther("40000"))).wait(); const C1 = await tre(dep).capChangeProposalCount();
  await (await dis(W[0]).proposeShareChange(5500)).wait(); const SP = await dis(dep).shareProposalCount();
  const late = S[8]; await (await mreg.setActive(late.address, true)).wait();
  ok("T1) Treasury: validator activated after creation cannot vote", await reverts(() => tre(late).voteCapChange(C1), "not eligible - not Active when this proposal was created"));
  ok("D1) Distributor validator chamber: activated after creation cannot vote", await reverts(() => dis(late).validatorVoteShareChange(SP), "not eligible - not Active when this proposal was created"));
  await (await mreg.setActive(W[1].address, false)).wait();
  ok("T2) Treasury: suspended voter blocked while suspended", await reverts(() => tre(W[1]).voteCapChange(C1), "not an active validator"));
  await (await mreg.setActive(W[1].address, true)).wait();
  ok("T3) Treasury: eligible-at-creation voter recovered -> may vote once", (await (await tre(W[1]).voteCapChange(C1)).wait()).status === 1 && (await reverts(() => tre(W[1]).voteCapChange(C1), "already voted")) === true);
  ok("D2) Distributor: eligible-at-creation voter (suspended+recovered) may vote once", (await (await dis(W[1]).validatorVoteShareChange(SP)).wait()).status === 1 && (await reverts(() => dis(W[1]).validatorVoteShareChange(SP), "validator already voted")) === true);
  ok("T4) Treasury quorum still the existing formula (6 active at creation -> 4)", (await tre(dep).capChangeProposals(C1)).requiredVotes === 4n);
  ok("D3) Distributor quorum still the existing formula (ceil(2/3·6) = 4)", (await dis(dep).shareProposals(SP)).requiredValidatorApprovals === 4n);

  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
