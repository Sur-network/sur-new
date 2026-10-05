// v2.1.0 integration: real ValidatorsRegistry + real ValidatorsBoard.
// Registry -> Board hook (syncVoter) on activation / suspension / recovery / exit, MIN_ACTIVE_VALIDATORS = 1 (suspension and exit blocked at the
// floor), electorate snapshot for voteOnDelivery and confirmSlash, activationSeq, and isolation of a failing or gas-burning Board.
const hre = require("hardhat"); const fs = require("fs"); const solc = require("solc");
const REGISTRY_ADDR = "0x3333333333333333333333333333333333333333", DISTRIBUTOR_ADDR = "0x2222222222222222222222222222222222222222", BOARD_ADDR = "0x4444444444444444444444444444444444444444", IDR = "0x6666666666666666666666666666666666666666";
let registry, board, art, bart, deployer, verifier, V = [], results = [];
const H = (s) => hre.ethers.keccak256(hre.ethers.toUtf8Bytes(s));
const inc = async (s) => { await hre.network.provider.send("evm_increaseTime", [s]); await hre.network.provider.send("evm_mine"); };
function ok(name, cond, extra = "") { results.push(cond === true); console.log((cond === true ? "✅ " : "❌ ") + name + (cond === true ? "" : " → " + cond) + (extra ? "  " + extra : "")); }
async function reverts(fn, expected) { try { await (await fn()).wait(); return false; } catch (e) { return (e.message || "").includes(expected) ? true : "wrong reason: " + (e.message || "").slice(0, 200); } }
async function setSlot(label, value) { const s = art.layout.storage.find(x => x.label === label); await hre.network.provider.send("hardhat_setStorageAt", [REGISTRY_ADDR, hre.ethers.toBeHex(BigInt(s.slot)), hre.ethers.zeroPadValue(hre.ethers.toBeHex(value), 32)]); }
const decId = (r, evName) => { for (const l of r.logs) { try { const p = registry.interface.parseLog(l); if (p.name === evName) return p.args[0]; } catch (e) {} } throw new Error("no " + evName); };
async function codeAt(addr, abi, bytecode) { const f = new hre.ethers.ContractFactory(abi, bytecode, deployer); const x = await f.deploy(); await x.waitForDeployment(); await hre.network.provider.send("hardhat_setCode", [addr, await hre.network.provider.send("eth_getCode", [await x.getAddress(), "latest"])]); }
const compileSmall = (src, name) => { const out = JSON.parse(solc.compile(JSON.stringify({ language: "Solidity", sources: { "S.sol": { content: src } }, settings: { outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } } } }))); const c = out.contracts["S.sol"][name]; return { abi: c.abi, bytecode: "0x" + c.evm.bytecode.object }; };

async function setup() {
  art = JSON.parse(fs.readFileSync("artifacts3.json", "utf8")); bart = JSON.parse(fs.readFileSync("board_artifact.json", "utf8"));
  const signers = await hre.ethers.getSigners(); deployer = signers[0]; verifier = signers[1]; V = signers.slice(2, 20);
  await codeAt(REGISTRY_ADDR, art.registry.abi, art.registry.bytecode);
  await codeAt(DISTRIBUTOR_ADDR, art.mock.abi, art.mock.bytecode);
  await codeAt(BOARD_ADDR, bart.abi, bart.bytecode);
  const mid = compileSmall("pragma solidity ^0.8.24; contract MockIdentity { function hasIdentity(address) external pure returns (bool) { return true; } }", "MockIdentity");
  await codeAt(IDR, mid.abi, mid.bytecode);
  registry = new hre.ethers.Contract(REGISTRY_ADDR, art.registry.abi, deployer); board = new hre.ethers.Contract(BOARD_ADDR, bart.abi, deployer);
  await hre.network.provider.send("hardhat_setStorageAt", [REGISTRY_ADDR, hre.ethers.toBeHex(BigInt(art.layout.storage.find(s => s.label === "verifier").slot)), hre.ethers.zeroPadValue(verifier.address, 32)]);
  for (const [k, v] of [["entryThresholdBase", hre.ethers.parseEther("500000")], ["growthFactorPerValidator", 1_017479692102686336n], ["membershipFeeBps", 400], ["maxEntriesPerWindow", 1], ["entryWindowSeconds", 3600], ["probationPeriod", 3600], ["recoveryPeriod", 172800], ["slashBps", 100], ["exitCooldown", 604800]]) await setSlot(k, v);
  for (const s of signers) await hre.network.provider.send("hardhat_setBalance", [s.address, "0x84595161401484A000000"]);
}
async function join(s) { const th = await registry.currentEntryThreshold(), fee = await registry.currentMembershipFee(); await (await registry.connect(s).requestMembership({ value: th + fee })).wait(); await inc(3601); }
async function activate(s) { await inc(3601); await (await registry.connect(verifier).recordActivation(s.address, H("act" + s.address))).wait(); }
const suspend = async (s) => { const r = await (await registry.connect(verifier).recordSuspension(s.address, H("susp" + s.address + Math.random()))).wait(); return decId(r, "StatusDecisionRecorded"); };

(async () => {
  await setup();
  for (let i = 0; i < 8; i++) await join(V[i]);
  for (let i = 0; i < 8; i++) await activate(V[i]);
  console.log("8 paid validators activated\n");

  // ---- activationSeq ----
  { const seqs = []; for (let i = 0; i < 8; i++) seqs.push(await registry.activationSeq(V[i].address));
    ok("A1) activationSeq follows the order of first activation (1..8)", seqs.every((s, i) => s === BigInt(i + 1)));
    ok("A2) activationCount = 8; a never-activated address has seq 0", (await registry.activationCount()) === 8n && (await registry.activationSeq(V[10].address)) === 0n);
    ok("A3) every activated validator's votesCounted is true (the activation hook ran)", (await Promise.all(V.slice(0, 8).map(v => board.votesCounted(v.address)))).every(Boolean)); }

  const snap = await hre.network.provider.send("evm_snapshot"); let s = snap;
  const fresh = async () => { await hre.network.provider.send("evm_revert", [s]); s = await hre.network.provider.send("evm_snapshot"); };

  // ---- Registry -> Board hook ----
  { for (const c of [3, 4, 5]) await (await board.connect(V[0]).voteFor(V[c].address)).wait();
    await (await board.connect(V[1]).voteFor(V[3].address)).wait();
    ok("H1) setup: V3 has 2 counted votes, V4 and V5 have 1", (await board.voteCount(V[3].address)) === 2n && (await board.voteCount(V[4].address)) === 1n);
    await suspend(V[0]);
    ok("H2) suspending V0 removes its votes from the counters automatically (hook on recordSuspension)", (await board.voteCount(V[3].address)) === 1n && (await board.voteCount(V[4].address)) === 0n && (await board.votesCounted(V[0].address)) === false);
    ok("H3) V0's own vote list is untouched", (await board.getVotesOf(V[0].address)).length === 3);
    await (await registry.connect(V[1]).requestExit()).wait();
    ok("H4) V1 requesting exit removes its votes too (hook on requestExit)", (await board.voteCount(V[3].address)) === 0n && (await board.votesCounted(V[1].address)) === false);
    // recovery of V0: resolve its case, then recover after the recovery period
    const did = (await registry.statusDecisionCount()); await inc(3601);
    await (await registry.resolveMassFailureCheck(did)).wait();
    const exempt = (await registry.statusDecisions(did)).slashOutcome;
    if (exempt === 0n) { await (await registry.connect(V[0]).confirmDelivery(did)).wait(); await inc(72 * 3600 + 10); await (await registry.executeUncontestedSlash(did)).wait(); }
    await inc(172800 + 10);
    await (await registry.connect(verifier).recordRecovery(V[0].address, H("rec"))).wait();
    ok("H5) recovery of V0 restores its votes to the counters (hook on recordRecovery)", (await board.votesCounted(V[0].address)) === true && (await board.voteCount(V[4].address)) === 1n && (await board.voteCount(V[3].address)) === 1n); }

  // ---- hook failure isolation ----
  await fresh();
  { const bad = compileSmall("pragma solidity ^0.8.24; contract Rev { fallback() external payable { revert('no'); } }", "Rev");
    await codeAt(BOARD_ADDR, bad.abi, bad.bytecode);
    let r = await reverts(() => registry.connect(verifier).recordSuspension(V[2].address, H("iso1")), "NONE");
    ok("I1) a reverting Board does not block recordSuspension", r === false && Number((await registry.getValidatorInfo(V[2].address))[0]) === 3);
    const burn = compileSmall("pragma solidity ^0.8.24; contract Burn { fallback() external payable { while (true) {} } }", "Burn");
    await codeAt(BOARD_ADDR, burn.abi, burn.bytecode);
    const tx = await registry.connect(verifier).recordSuspension(V[3].address, H("iso2")); const rc = await tx.wait();
    ok("I2) a Board that burns all gas does not block recordSuspension; the hook is capped (tx gas used " + rc.gasUsed + ")", Number((await registry.getValidatorInfo(V[3].address))[0]) === 3 && rc.gasUsed < 1_200_000n);
    await hre.network.provider.send("hardhat_setCode", [BOARD_ADDR, "0x"]);
    r = await reverts(() => registry.connect(V[4]).requestExit(), "NONE");
    ok("I3) with no code at the Board address, requestExit still succeeds", r === false);
    await codeAt(BOARD_ADDR, bart.abi, bart.bytecode); }

  // ---- minimum validator count = 1 ----
  await fresh();
  { ok("F0) MIN_ACTIVE_VALIDATORS = 1", (await registry.MIN_ACTIVE_VALIDATORS()) === 1n);
    for (let i = 0; i < 7; i++) await suspend(V[i]);
    ok("F1) seven of eight can be suspended: one active validator remains", (await registry.getActiveValidatorCount()) === 1n);
    ok("F2) the last active validator cannot be suspended", await reverts(() => registry.connect(verifier).recordSuspension(V[7].address, H("last")), "suspension blocked"));
    ok("F3) the last active validator cannot exit", await reverts(() => registry.connect(V[7]).requestExit(), "exit blocked"));
    ok("F4) getValidators() still returns that validator (never empty)", (await registry.getValidators()).length === 1);
    ok("F5) a suspended (not active) validator can still exit", (await reverts(() => registry.connect(V[0]).requestExit(), "NONE")) === false);
    await join(V[8]); await activate(V[8]);
    ok("F6) once a second validator is active, the first can be suspended again", (await reverts(() => registry.connect(verifier).recordSuspension(V[7].address, H("again")), "NONE")) === false);
    ok("F7) and then the new one is the last: blocked", await reverts(() => registry.connect(V[8]).requestExit(), "exit blocked")); }

  // ---- electorate snapshot for voteOnDelivery ----
  await fresh();
  { const did = await suspend(V[0]); await inc(3601); await (await registry.resolveMassFailureCheck(did)).wait();
    await inc(7 * 86400 + 10); await (await registry.assertDeliveryDisputed(did)).wait();
    await join(V[9]); await activate(V[9]); // becomes Active AFTER the dispute was filed
    ok("D1) deliveryDisputeNonce is stored when the dispute is filed", (await registry.deliveryDisputeNonce(did)) > 0n);
    ok("D2) a validator activated after the dispute was filed cannot vote on it", await reverts(() => registry.connect(V[9]).voteOnDelivery(did, true), "not Active when this dispute was filed"));
    ok("D3) a validator active when it was filed can vote", (await reverts(() => registry.connect(V[1]).voteOnDelivery(did, true), "NONE")) === false); }

  // ---- electorate snapshot for confirmSlash ----
  await fresh();
  { const did = await suspend(V[0]); await inc(3601); await (await registry.resolveMassFailureCheck(did)).wait();
    await (await registry.connect(V[0]).confirmDelivery(did)).wait(); await (await registry.connect(V[0]).fileAppeal(did)).wait();
    await join(V[9]); await activate(V[9]); // Active AFTER the appeal was filed
    ok("S1) appealNonce is stored when the appeal is filed", (await registry.appealNonce(did)) > 0n);
    ok("S2) a validator activated after the appeal was filed cannot vote to confirm the slash", await reverts(() => registry.connect(V[9]).confirmSlash(did), "not Active when the appeal was filed"));
    ok("S3) a validator active when it was filed can vote", (await reverts(() => registry.connect(V[1]).confirmSlash(did), "NONE")) === false);
    ok("S4) a validator that was suspended at filing time cannot vote (also not Active now)", await reverts(() => registry.connect(V[0]).confirmSlash(did), "caller is not an active validator")); }

  const pass = results.filter(Boolean).length; console.log("\nresult: " + pass + "/" + results.length + " passed"); process.exit(pass === results.length ? 0 : 1);
})().catch(e => { console.error("error:", e.message); process.exit(1); });
