// L04 — INTEGRATION with the REAL ValidatorsRegistry at its fixed address 0x3333, whose storage is produced exactly like a
// genesis extraction: the project's genesis seed helper is deployed, its deployment is traced (debug_traceTransaction), every
// storage slot its constructor wrote is copied to 0x3333, and the real Registry runtime is installed there. REAL
// ValidatorsTreasury (0x5555) and REAL BlockRewardDistributor (0x2222) then call it through their own interfaces.
// Also: quorum formulas at boundary counts and under membership changes (Registry, Treasury, Distributor, FoundationDAO),
// FoundationDAO current-membership requirement, and re-vote attempts. Hardhat, not Besu.
// Usage: CONTRACTS_DIR=<contracts|contracts-fa> npx hardhat run scripts/test_L04_real_registry_integration.js
const hre = require("hardhat"); const fs = require("fs"); const path = require("path"); const solc = require(process.env.SOLC_PATH || "solc");
const DIR = process.env.CONTRACTS_DIR || "../../contracts";
const REG = "0x3333333333333333333333333333333333333333", BOARD = "0x4444444444444444444444444444444444444444",
      TRES = "0x5555555555555555555555555555555555555555", DIST = "0x2222222222222222222222222222222222222222";
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
const setSlot = (addr, slot, val) => hre.network.provider.send("hardhat_setStorageAt", [addr, hre.ethers.toBeHex(BigInt(slot)), hre.ethers.zeroPadValue(hre.ethers.toBeHex(val), 32)]);
(async () => {
  const S = await hre.ethers.getSigners(); const dep = S[0];
  console.log(`source dir: ${DIR}  solc ${solc.version()}`);
  // ---------- genesis-style extraction of the Registry seed helper into 0x3333
  const V = S.slice(1, 8), VER = S[10];
  const [rh, n] = patchHelper(fs.readFileSync(path.join(DIR, "genesis-seed-helpers/ValidatorsRegistry_GenesisSeed.sol"), "utf8"), V);
  const c = compile({ "H.sol": rh, "R.sol": fs.readFileSync(path.join(DIR, "ValidatorsRegistry.sol"), "utf8"), "T.sol": fs.readFileSync(path.join(DIR, "ValidatorsTreasury.sol"), "utf8"), "B.sol": fs.readFileSync(path.join(DIR, "BlockRewardDistributor.sol"), "utf8"),
    "M.sol": "pragma solidity ^0.8.24; contract MockBoard { uint256 public boardVersion = 1; function isBoardMember(address) external pure returns (bool) { return true; } function hasBoardAuthority(address) external pure returns (bool) { return true; } }" });
  const H = c["H.sol"].ValidatorsRegistry_GenesisSeed, R = c["R.sol"].ValidatorsRegistry;
  const hf = new hre.ethers.ContractFactory(H.abi, "0x" + H.evm.bytecode.object, dep); const hi = await hf.deploy(); const rcpt = await hi.deploymentTransaction().wait();
  const trace = await hre.network.provider.send("debug_traceTransaction", [rcpt.hash, { disableMemory: true, disableStack: true }]);
  let storage = {}; for (const l of trace.structLogs) if (l.storage) storage = l.storage; // cumulative storage of the contract under construction
  const slots = Object.entries(storage).filter(([k, v]) => BigInt("0x" + v) !== 0n);
  for (const [k, v] of slots) await hre.network.provider.send("hardhat_setStorageAt", [REG, "0x" + k, "0x" + v]);
  await hre.network.provider.send("hardhat_setCode", [REG, "0x" + R.evm.deployedBytecode.object]);
  const L = R.storageLayout.storage; const slotOf = lbl => L.find(x => x.label === lbl).slot;
  await setSlot(REG, slotOf("verifier"), VER.address); await setSlot(REG, slotOf("maxEntriesPerWindow"), 10); await setSlot(REG, slotOf("entryWindowSeconds"), 86400);
  await hre.network.provider.send("hardhat_setCode", [TRES, "0x" + c["T.sol"].ValidatorsTreasury.evm.deployedBytecode.object]);
  await hre.network.provider.send("hardhat_setCode", [DIST, "0x" + c["B.sol"].BlockRewardDistributor.evm.deployedBytecode.object]);
  await setSlot(DIST, c["B.sol"].BlockRewardDistributor.storageLayout.storage.find(x => x.label === "validatorDirectShareBps").slot, 5000);
  { const t = await new hre.ethers.ContractFactory(c["M.sol"].MockBoard.abi, "0x" + c["M.sol"].MockBoard.evm.bytecode.object, dep).deploy(); await t.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [BOARD, await hre.network.provider.send("eth_getCode", [await t.getAddress(), "latest"])]); }
  const reg = w => new hre.ethers.Contract(REG, R.abi, w), tre = w => new hre.ethers.Contract(TRES, c["T.sol"].ValidatorsTreasury.abi, w), dis = w => new hre.ethers.Contract(DIST, c["B.sol"].BlockRewardDistributor.abi, w);
  console.log(`   helper wrote ${slots.length} non-zero storage slots; copied to ${REG}`);

  console.log("\n=== G — genesis assertions on the extracted Registry state ===");
  ok("G1) 7 founders, all Active, getValidators() length 7", n === 7 && (await reg(dep).getValidators()).length === 7 && (await Promise.all(V.map(v => reg(dep).isValidator(v.address)))).every(x => x));
  ok("G2) statusNonce = 0 at genesis", (await reg(dep).statusNonce()) === 0n);
  ok("G3) every founder has checkpoint {0, true}: wasActiveAt(founder, 0) = true", (await Promise.all(V.map(v => reg(dep).wasActiveAt(v.address, 0)))).every(x => x));
  ok("G4) everActivated true for every founder", (await Promise.all(V.map(v => reg(dep).everActivated(v.address)))).every(x => x));
  ok("G5) non-founder has no history: wasActiveAt(x, 0) = false", (await reg(dep).wasActiveAt(S[12].address, 0)) === false);

  console.log("\n=== Q — quorum formulas at boundary counts (unchanged formulas, frozen at creation) ===");
  const formulas = { reg: a => Math.floor(a / 2) + 1, tre: a => Math.floor(a / 2) + 1, dis: a => Math.floor((2 * a + 2) / 3) };
  const created = [];
  const createAll = async (who) => {
    await (await reg(who).proposeParameterChange(2, 777)).wait(); const pr = await reg(dep).paramProposalCount();
    await (await tre(who).proposeCapChange(0, hre.ethers.parseEther("40000"))).wait(); const pt = await tre(dep).capChangeProposalCount();
    await (await dis(who).proposeShareChange(5500)).wait(); const pd = await dis(dep).shareProposalCount();
    return { pr, pt, pd }; };
  const check = async (ids, a, tag) => {
    const rq = (await reg(dep).paramProposals(ids.pr)).requiredVotes, tq = (await tre(dep).capChangeProposals(ids.pt)).requiredVotes, dq = (await dis(dep).shareProposals(ids.pd)).requiredValidatorApprovals;
    return rq === BigInt(formulas.reg(a)) && tq === BigInt(formulas.tre(a)) && dq === BigInt(formulas.dis(a)) ? true : `${tag}: reg ${rq}/${formulas.reg(a)} tre ${tq}/${formulas.tre(a)} dis ${dq}/${formulas.dis(a)}`; };
  const suspend = async who => { const id = await reg(VER).recordSuspension.staticCall(who.address, hre.ethers.ZeroHash); await (await reg(VER).recordSuspension(who.address, hre.ethers.ZeroHash)).wait(); return id; };
  const decs = [];
  for (let a = 7; a >= 3; a--) {
    const active = (await reg(dep).getValidators()).length; const ids = await createAll(V[0]); created.push({ ids, a: active });
    ok(`Q.${a}) ${active} active -> reg ${formulas.reg(active)}, treasury ${formulas.tre(active)}, distributor ${formulas.dis(active)}`, active === a && (await check(ids, active, "n=" + a)) === true);
    if (a > 3) decs.push(await suspend(V[a - 1]));
  }
  const NEWV = S[9]; const cost = (await reg(dep).currentEntryThreshold()) + (await reg(dep).currentMembershipFee());
  await (await reg(NEWV).requestMembership({ value: cost })).wait(); await inc(1); await (await reg(VER).recordActivation(NEWV.address, hre.ethers.ZeroHash)).wait();
  { const active = (await reg(dep).getValidators()).length; const ids = await createAll(V[0]); ok(`Q.up) after an activation (${active} active) formulas hold`, active === 4 && (await check(ids, active, "up")) === true); created.push({ ids, a: active }); }
  let frozen = true; for (const x of created) { const r = await check(x.ids, x.a, "frozen a=" + x.a); if (r !== true) frozen = r; }
  ok("Q.frozen) every earlier proposal keeps the quorum frozen at its own creation after all membership changes", frozen);

  console.log("\n=== E — eligibility through the REAL Registry (Treasury + Distributor) ===");
  const first = created[0].ids; // created with 7 active founders
  ok("E1) Treasury: validator activated after creation cannot vote (real Registry checkpoint)", await reverts(() => tre(NEWV).voteCapChange(first.pt), "not eligible - not Active when this proposal was created"));
  ok("E2) Distributor: validator activated after creation cannot vote", await reverts(() => dis(NEWV).validatorVoteShareChange(first.pd), "not eligible - not Active when this proposal was created"));
  // V6 was eligible at 'first' (7 active) and is suspended now -> blocked while suspended; recover -> may vote once
  ok("E3) Treasury: eligible voter blocked while suspended (real isValidator)", await reverts(() => tre(V[6]).voteCapChange(first.pt), "not an active validator"));
  await inc(3601); for (const d of decs) { try { await (await reg(dep).resolveMassFailureCheck(d)).wait(); } catch (e) {} }
  await (await reg(VER).recordRecovery(V[6].address, hre.ethers.ZeroHash)).wait();
  ok("E4) Treasury: eligible voter recovered -> may vote once", (await (await tre(V[6]).voteCapChange(first.pt)).wait()).status === 1 && (await reverts(() => tre(V[6]).voteCapChange(first.pt), "already voted")) === true);
  ok("E5) Distributor: eligible voter recovered -> may vote once", (await (await dis(V[6]).validatorVoteShareChange(first.pd)).wait()).status === 1 && (await reverts(() => dis(V[6]).validatorVoteShareChange(first.pd), "validator already voted")) === true);
  const atFive = created[2].ids; // created with 5 active: V5 and V6 suspended at that moment
  await (await reg(VER).recordRecovery(V[5].address, hre.ethers.ZeroHash)).wait();
  ok("E6) Treasury: suspended AT creation, recovered later -> not eligible", await reverts(() => tre(V[5]).voteCapChange(atFive.pt), "not eligible - not Active when this proposal was created"));
  ok("E7) Distributor: suspended AT creation, recovered later -> not eligible", await reverts(() => dis(V[5]).validatorVoteShareChange(atFive.pd), "not eligible - not Active when this proposal was created"));
  await (await tre(V[1]).voteCapChange(first.pt)).wait(); const tv = (await tre(dep).capChangeProposals(first.pt)).votes;
  await (await reg(V[1]).requestExit()).wait();
  ok("E8) exited voter's Treasury vote stays counted; exited voter cannot vote elsewhere", (await tre(dep).capChangeProposals(first.pt)).votes === tv && (await reverts(() => dis(V[1]).validatorVoteShareChange(first.pd), "not an active validator")) === true);

  console.log("\n=== F — FoundationDAO: current membership + quorum boundaries ===");
  const FS = S.slice(1, 16), X = S[17];
  const fc = compile({ "FH.sol": patchHelper(fs.readFileSync(path.join(DIR, "genesis-seed-helpers/FoundationDAO_GenesisSeed.sol"), "utf8"), FS)[0], "F.sol": fs.readFileSync(path.join(DIR, "FoundationDAO.sol"), "utf8") });
  const fhI = await new hre.ethers.ContractFactory(fc["FH.sol"].FoundationDAO_GenesisSeed.abi, "0x" + fc["FH.sol"].FoundationDAO_GenesisSeed.evm.bytecode.object, dep).deploy(); await fhI.waitForDeployment();
  const FA = await fhI.getAddress(); await hre.network.provider.send("hardhat_setCode", [FA, "0x" + fc["F.sol"].FoundationDAO.evm.deployedBytecode.object]);
  const dao = w => new hre.ethers.Contract(FA, fc["F.sol"].FoundationDAO.abi, w);
  const req = async id => (await dao(dep).getProposalMeta(id)).requiredVotes;
  const members = async () => Number(await dao(dep).getMemberCount());
  const fAdd = n => Math.floor((2 * n + 2) / 3), fSimple = n => Math.floor(n / 2) + 1;
  const passWith = async (id) => { const need = await req(id); let v = (await dao(dep).getProposal(id)).votes; const all = await dao(dep).getAllMembers(); for (const m of all) { if (v >= need) break; const acc = m.account || m[1]; const sgn = S.find(s => s.address === acc); if (sgn && !(await dao(dep).hasVoted(id, acc))) { await (await dao(sgn).vote(id)).wait(); v++; } } };
  const fProposals = [];
  for (const step of ["15", "add->16", "add->17", "remove->16", "remove->15", "remove->14"]) {
    if (step.startsWith("add")) { const who = S[16 + fProposals.length]; await (await dao(FS[0]).proposeAddMember("a", "m", who.address)).wait(); await passWith(await dao(dep).proposalCount()); }
    if (step.startsWith("remove")) { const all = await dao(dep).getAllMembers(); const victim = (all[all.length - 1].account || all[all.length - 1][1]); await (await dao(FS[0]).proposeRemoveMember("r", victim)).wait(); await passWith(await dao(dep).proposalCount()); }
    const m = await members();
    await (await dao(FS[0]).proposeAddMember("q", "z", S[19].address)).wait(); const pa = await dao(dep).proposalCount();
    await (await dao(FS[0]).proposeSendETH("q", FS[0].address, 1)).wait(); const ps = await dao(dep).proposalCount();
    fProposals.push({ pa, ps, m });
    ok(`FQ.${step}) ${m} members -> AddMember ${fAdd(m)}, SendETH ${fSimple(m)}`, (await req(pa)) === BigInt(fAdd(m)) && (await req(ps)) === BigInt(fSimple(m)));
  }
  let fFrozen = true; for (const x of fProposals) if ((await req(x.pa)) !== BigInt(fAdd(x.m)) || (await req(x.ps)) !== BigInt(fSimple(x.m))) fFrozen = `m=${x.m}`;
  ok("FQ.frozen) every FoundationDAO proposal keeps its creation-time quorum after later membership changes", fFrozen);
  // current membership + re-vote attempts: member votes on P, is removed, re-added, tries again
  await (await dao(FS[0]).proposeSendETH("P", FS[0].address, 1)).wait(); const P = await dao(dep).proposalCount();
  await (await dao(FS[3]).vote(P)).wait();
  await (await dao(FS[0]).proposeRemoveMember("r3", FS[3].address)).wait(); await passWith(await dao(dep).proposalCount());
  ok("FM1) removed member cannot vote (current membership required)", await reverts(() => dao(FS[3]).vote(fProposals[0].ps), "not a member"));
  await (await dao(FS[0]).proposeAddMember("back", "m3", FS[3].address)).wait(); await passWith(await dao(dep).proposalCount());
  ok("FM2) re-added member trying to vote again on P (voted before removal) -> already voted", await reverts(() => dao(FS[3]).vote(P), "already voted"));
  ok("FM3) re-added member on an older proposal it never voted on -> not eligible", await reverts(() => dao(FS[3]).vote(fProposals[0].ps), "not eligible - not a member when this proposal was created"));

  const bad = results.filter(x => !x).length; console.log(`\nنتیجه: ${results.length - bad}/${results.length} گذر`); process.exit(bad ? 1 : 0);
})().catch(e => { console.error("خطا:", e.message); process.exit(1); });
