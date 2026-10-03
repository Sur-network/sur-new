// A14 — unexpected-storage scan. Run:  npx hardhat run scripts/testonly-a14.js --network hardhat   (from the hardhat/ dir)
// For every baseline network genesis: derive the EXPECTED alloc independently of the genesis builder's output (accounts + per-contract storage =
// "clean constructor slots" of a fresh deploy  +  the document's seed list computed analytically from the compiled storageLayout), then diff it
// against the genesis.json alloc: any extra account, extra storage slot, missing slot or wrong value is reported.
// Also: (1) code at the 6 fixed addresses vs compiled runtimes, (2) a semantic round-trip of the seeded state into fresh deployments of the real
// contracts, (3) the Merkle-Patricia state root of the genesis alloc (compared elsewhere with the live node's block-0 stateRoot).
const { ethers, network } = require("hardhat");
const hre = require("hardhat");
const fs = require("fs");
const path = require("path");
const { allocStateRoot } = require("./v5-mpt");

const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const accounts = JSON.parse(fs.readFileSync(path.join(ROOT, "TEST-KEYS-DO-NOT-REUSE.json"), "utf8"));
const FIXED = { FoundationDAO: "0x1111111111111111111111111111111111111111", BlockRewardDistributor: "0x2222222222222222222222222222222222222222", ValidatorsRegistry: "0x3333333333333333333333333333333333333333", ValidatorsBoard: "0x4444444444444444444444444444444444444444", ValidatorsTreasury: "0x5555555555555555555555555555555555555555", IdentityRegistry: "0x6666666666666666666666666666666666666666" };
const NETS = (process.env.A14_NETS || "Net-B,Net-L01,Net-L02,Net-L04,Net-L05,Net-D,Net-F1,Net-F2,Net-F3,Net-F4,Net-F5,Net-F5b,Net-F6,Net-L05a,Net-L05b,Net-D3,Net-E15,Net-E30,Net-E60,Net-A14").split(",");

// Build recipes recovered from the original build commands (session transcript): these four networks were built with BUILDER_SEED_FOUNDATION=0,
// i.e. FoundationDAO deliberately NOT seeded (they run no FoundationDAO test). Every other network was built with it = 1. Board was seeded everywhere.
const NO_FOUNDATION_SEED = new Set(['Net-L01', 'Net-L02', 'Net-L04', 'Net-L05']);
const T = (v) => ethers.zeroPadValue(ethers.toBeHex(BigInt(v)), 32).toLowerCase();
const mapSlot = (addr, base) => BigInt(ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["address", "uint256"], [addr, base])));
const arrBase = (slot) => BigInt(ethers.keccak256(T(slot)));
const addrWord = (a) => T(BigInt(a));
const norm = (k) => ethers.zeroPadValue(k.startsWith("0x") ? k : "0x" + k, 32).toLowerCase();

async function main() {
  // ---- layouts + clean constructor slots (one fresh deploy per contract) ----
  const layouts = {}, ctor = {}, runtime = {};
  for (const name of Object.keys(FIXED)) {
    const f = await ethers.getContractFactory(name);
    const d = await f.deploy(); await d.waitForDeployment();
    const addr = await d.getAddress();
    const art = await hre.artifacts.readArtifact(name);
    runtime[name] = ethers.keccak256(art.deployedBytecode);
    const bi = await hre.artifacts.getBuildInfo(`contracts-baseline/${name}.sol:${name}`);
    layouts[name] = bi.output.contracts[`contracts-baseline/${name}.sol`][name].storageLayout;
    ctor[name] = {};
    for (let i = 0; i < 150; i++) { const v = await network.provider.send("eth_getStorageAt", [addr, T(i), "latest"]); if (BigInt(v) !== 0n) ctor[name][T(i)] = BigInt(v); }
  }
  const slotOf = (name, label) => { const s = layouts[name].storage.find((x) => x.label === label); if (!s) throw new Error(`no slot ${name}.${label}`); return BigInt(s.slot); };
  const layoutSummary = Object.fromEntries(Object.entries(layouts).map(([n, l]) => [n, l.storage.slice(0, 6).map((s) => `${s.slot}:${s.label}`)]));

  const results = {};
  for (const net of NETS) {
    const gpath = `${ROOT}/nets/${net}/genesis.json`;
    const g = JSON.parse(fs.readFileSync(gpath, "utf8"));
    const meta = JSON.parse(fs.readFileSync(`${ROOT}/evidence/02-genesis/${net}/seed-summary.json`, "utf8"));
    const ts = BigInt(parseInt(g.timestamp, 16));
    const G5 = meta.FOUNDERS === "G5";
    const founders = (G5 ? [1, 2, 3, 4, 5].map((i) => accounts[`g5_v${i}`].address) : [1, 2, 3, 4, 5, 6].map((i) => accounts[`g6_v${i}`].address));
    const foundation = Array.from({ length: 15 }, (_, i) => accounts[`foundation${i + 1}`].address);
    const payees = fs.existsSync(`${ROOT}/nets/${net}/payees.json`) ? JSON.parse(fs.readFileSync(`${ROOT}/nets/${net}/payees.json`, "utf8")) : [];
    let history = [];
    const spec = meta.RATE_HISTORY_SPEC || "";
    if (spec === "F300") history = [[300, 3000000000000000000n]]; else if (spec === "E399") history = Array.from({ length: 399 }, (_, i) => [151 + i, 2000000000000000000n]); else if (spec) history = JSON.parse(spec).map(([s, r]) => [Number(s), BigInt(r)]);

    // ---------- expected storage per contract: key -> BigInt value, or null = "must be non-zero, value checked by round-trip only" ----------
    const E = {};
    for (const n of Object.keys(FIXED)) E[n] = Object.fromEntries(Object.entries(ctor[n]).map(([k, v]) => [k, v]));
    const R = E.ValidatorsRegistry, Dn = E.BlockRewardDistributor, B = E.ValidatorsBoard, FD = E.FoundationDAO;
    // Registry overlays + founders
    R[T(slotOf("ValidatorsRegistry", "verifier"))] = BigInt(accounts.verifier.address);
    R[T(slotOf("ValidatorsRegistry", "probationPeriod"))] = 300n;
    R[T(slotOf("ValidatorsRegistry", "recoveryPeriod"))] = 3700n;
    R[T(slotOf("ValidatorsRegistry", "exitCooldown"))] = 600n;
    R[T(slotOf("ValidatorsRegistry", "maxEntriesPerWindow"))] = 10n;
    R[T(slotOf("ValidatorsRegistry", "windowStart"))] = ts;
    const avSlot = slotOf("ValidatorsRegistry", "activeValidators");
    R[T(avSlot)] = BigInt(founders.length);
    founders.forEach((a, i) => { R[T(arrBase(avSlot) + BigInt(i))] = BigInt(a); });
    const everSlot = slotOf("ValidatorsRegistry", "everActivated"), idxSlot = slotOf("ValidatorsRegistry", "activeIndex"), cpSlot = slotOf("ValidatorsRegistry", "activeCheckpoints"), valSlot = slotOf("ValidatorsRegistry", "validators");
    for (const [fi, a] of founders.entries()) {
      const vb = mapSlot(a, valSlot);
      R[T(vb)] = null;                 // status = Active (non-zero)
      R[T(vb + 2n)] = ts;              // periodStartedAt = genesis timestamp
      R[T(mapSlot(a, idxSlot))] = BigInt(fi + 1); // activeIndex is 1-based (ValidatorsRegistry.sol: activeIndex[v] = activeValidators.length + 1)
      R[T(mapSlot(a, everSlot))] = 1n;
      const cp = mapSlot(a, cpSlot);
      R[T(cp)] = 1n;                   // checkpoints length 1
      R[T(arrBase(cp))] = 1n << 64n;   // {nonce:0, active:true} packed (A08)
    }
    for (const p of payees) R[T(mapSlot(p, everSlot))] = 1n;
    // Board
    const bmSlot = slotOf("ValidatorsBoard", "boardMembers"), ibSlot = slotOf("ValidatorsBoard", "isBoardMember");
    B[T(bmSlot)] = 5n; founders.slice(0, 5).forEach((a, i) => { B[T(arrBase(bmSlot) + BigInt(i))] = BigInt(a); B[T(mapSlot(a, ibSlot))] = 1n; });
    // FoundationDAO: 15 members, struct {string name; address wallet} = 2 slots each
    const mlSlot = slotOf("FoundationDAO", "memberList"), miSlot = slotOf("FoundationDAO", "memberIndex");
    const fdLabels = layouts.FoundationDAO.storage.map((s) => `${s.slot}:${s.label}`);
    const third = layouts.FoundationDAO.storage.find((s) => s.slot === "2");
    const seedFoundation = !NO_FOUNDATION_SEED.has(net);
    if (seedFoundation) FD[T(mlSlot)] = 15n;
    if (seedFoundation) foundation.forEach((a, i) => { FD[T(arrBase(mlSlot) + BigInt(2 * i))] = null; FD[T(arrBase(mlSlot) + BigInt(2 * i + 1))] = BigInt(a); FD[T(mapSlot(a, miSlot))] = BigInt(i + 1); if (third) FD[T(mapSlot(a, 2n))] = 1n; });
    // Distributor
    Dn[T(slotOf("BlockRewardDistributor", "distributionOracle"))] = BigInt(accounts.distributionOracle.address);
    if (history.length) { const hs = slotOf("BlockRewardDistributor", "rewardRateChanges"); Dn[T(hs)] = BigInt(history.length); history.forEach(([s, r], i) => { Dn[T(arrBase(hs) + BigInt(i))] = (BigInt(r) << 128n) | BigInt(s); }); }

    // ---------- accounts ----------
    const BIG = 5000000n * 10n ** 18n, ORC = 50000n * 10n ** 18n;
    const expAcct = {};
    for (const a of founders) expAcct[a.toLowerCase()] = BIG;
    if (meta.INCLUDE_C6) expAcct[accounts.g5_c6.address.toLowerCase()] = BIG;
    for (const r of ["verifier", "distributionOracle"]) expAcct[accounts[r].address.toLowerCase()] = ORC;
    for (const r of ["serviceStakingUser1", "serviceStakingUser2"]) expAcct[accounts[r].address.toLowerCase()] = BIG;
    const A = { missing: [], extra: [], balanceMismatch: [], codeOrStorageOnEOA: [], fixedWithBalance: [] };
    const allocKeys = Object.keys(g.alloc).map((k) => ethers.getAddress(k.startsWith("0x") ? k : "0x" + k).toLowerCase());
    const fixedSet = new Set(Object.values(FIXED).map((a) => a.toLowerCase()));
    for (const k of allocKeys) if (!fixedSet.has(k) && !(k in expAcct)) A.extra.push(k);
    for (const k of Object.keys(expAcct)) if (!allocKeys.includes(k)) A.missing.push(k);
    for (const f of fixedSet) if (!allocKeys.includes(f)) A.missing.push(f);
    const allocBy = Object.fromEntries(Object.entries(g.alloc).map(([k, v]) => [ethers.getAddress(k.startsWith("0x") ? k : "0x" + k).toLowerCase(), v]));
    for (const [k, v] of Object.entries(expAcct)) if (allocBy[k]) { if (BigInt(allocBy[k].balance || 0) !== v) A.balanceMismatch.push({ addr: k, got: String(BigInt(allocBy[k].balance || 0)), want: String(v) }); if (allocBy[k].code || (allocBy[k].storage && Object.keys(allocBy[k].storage).length)) A.codeOrStorageOnEOA.push(k); }
    for (const f of fixedSet) if (allocBy[f] && BigInt(allocBy[f].balance || 0) !== 0n) A.fixedWithBalance.push(f);

    // ---------- code + storage per fixed contract ----------
    const S = {};
    for (const [name, addr] of Object.entries(FIXED)) {
      const al = allocBy[addr.toLowerCase()];
      const codeHash = al && al.code ? ethers.keccak256(al.code) : null;
      const act = {};
      for (const [k, v] of Object.entries((al && al.storage) || {})) act[norm(k)] = BigInt(v);
      const exp = E[name];
      const missing = [], extra = [], valueMismatch = [], zeroWhereNonZeroExpected = [];
      let keyOnly = 0, valueChecked = 0;
      for (const [k, v] of Object.entries(exp)) {
        if (!(k in act)) { missing.push(k); continue; }
        if (v === null) { keyOnly++; if (act[k] === 0n) zeroWhereNonZeroExpected.push(k); } else { valueChecked++; if (act[k] !== v) valueMismatch.push({ slot: k, got: "0x" + act[k].toString(16), want: "0x" + v.toString(16) }); }
      }
      for (const k of Object.keys(act)) if (!(k in exp)) extra.push({ slot: k, value: "0x" + act[k].toString(16) });
      // FoundationDAO name slots: must be valid short-string encodings
      let shortStringBad = 0;
      if (name === "FoundationDAO" && seedFoundation) foundation.forEach((_, i) => { const v = act[T(arrBase(mlSlot) + BigInt(2 * i))]; if (v === undefined) return; const len = Number(v & 0xffn); if (len % 2 !== 0 || len / 2 > 31 || len === 0) shortStringBad++; });
      S[name] = { codeMatchesCompiled: codeHash === runtime[name], expectedSlots: Object.keys(exp).length, actualSlots: Object.keys(act).length, valueChecked, keyOnlyChecked: keyOnly, missing, extra, valueMismatch, zeroWhereNonZeroExpected, shortStringBad };
    }

    // ---------- semantic round-trip into fresh deployments of the REAL contracts ----------
    const RT = {};
    const load = async (name, deployName) => { const f = await ethers.getContractFactory(deployName || name); const c = await f.deploy(); await c.waitForDeployment(); const ad = await c.getAddress(); const al = allocBy[FIXED[name].toLowerCase()]; for (const [k, v] of Object.entries(al.storage || {})) await network.provider.send("hardhat_setStorageAt", [ad, norm(k), T(BigInt(v))]); return c; };
    try {
      const reg = await load("ValidatorsRegistry");
      const vs = await reg.getValidators();
      RT.registryGetValidators = vs.length === founders.length && vs.every((a, i) => a.toLowerCase() === founders[i].toLowerCase());
      RT.registryFoundersActiveAndEver = (await Promise.all(founders.map(async (a) => (await reg.isValidator(a)) && (await reg.everActivated(a)) && (await reg.wasActiveAt(a, 0))))).every(Boolean);
      RT.registryPayeesEverNotValidators = payees.length === 0 ? "n/a" : (await Promise.all(payees.map(async (a) => (await reg.everActivated(a)) && !(await reg.isValidator(a))))).every(Boolean);
      RT.registryStatusNonce = (await reg.statusNonce()).toString();
      const bd = await load("ValidatorsBoard");
      const bm = await bd.getBoardMembers();
      RT.boardMembers = bm.length === 5 && bm.every((a, i) => a.toLowerCase() === founders[i].toLowerCase());
      const fd = await load("FoundationDAO");
      RT.foundation15 = !seedFoundation ? "n/a (FoundationDAO not seeded in this network's build recipe)" : (await Promise.all(foundation.map(async (a, i) => { const m = await fd.memberList(i); return m[1].toLowerCase() === a.toLowerCase(); }))).every(Boolean);
      const di = await load("BlockRewardDistributor");
      RT.distributorOracle = (await di.distributionOracle()).toLowerCase() === accounts.distributionOracle.address.toLowerCase();
      RT.distributorHistoryCount = (await di.rewardRateChangeCount()).toString();
      RT.distributorHistoryExpected = String(history.length);
      RT.distributorHistoryEntriesMatch = (await Promise.all(history.map(async ([s, r], i) => { const e = await di.rewardRateChange(i); return Number(e[0]) === s && BigInt(e[1]) === BigInt(r); }))).every(Boolean);
    } catch (e) { RT.error = e.message.slice(0, 300); }

    const stateRoot = allocStateRoot(g.alloc);
    const bad = A.missing.length + A.extra.length + A.balanceMismatch.length + A.codeOrStorageOnEOA.length + A.fixedWithBalance.length +
      Object.values(S).reduce((n, s) => n + s.missing.length + s.extra.length + s.valueMismatch.length + s.zeroWhereNonZeroExpected.length + s.shortStringBad + (s.codeMatchesCompiled ? 0 : 1), 0);
    const rtOk = !RT.error && RT.registryGetValidators && RT.registryFoundersActiveAndEver && RT.boardMembers && (RT.foundation15 === true || !seedFoundation) && RT.distributorOracle && RT.distributorHistoryCount === RT.distributorHistoryExpected && RT.distributorHistoryEntriesMatch && (RT.registryPayeesEverNotValidators === true || RT.registryPayeesEverNotValidators === "n/a") && RT.registryStatusNonce === "0";
    results[net] = { meta: { foundationSeeded: seedFoundation, FOUNDERS: meta.FOUNDERS, INCLUDE_C6: meta.INCLUDE_C6, rateHistoryEntries: history.length, payees: payees.length, genesisTimestamp: String(ts) }, accounts: A, contracts: S, roundTrip: RT, genesisAllocStateRoot: stateRoot, deviations: bad, roundTripOk: rtOk, verdict: bad === 0 && rtOk ? "PASS" : "FAIL" };
    console.log(`${net}: deviations=${bad} roundTrip=${rtOk} -> ${results[net].verdict}  stateRoot(genesis alloc)=${stateRoot.slice(0, 14)}…`);
  }
  const out = { generatedAt: new Date().toISOString(), method: "independent derivation of expected alloc (clean-constructor slots of a fresh deploy + analytically computed seed list from storageLayout) vs genesis.json alloc; semantic round-trip; MPT state root", assumption: "constructors write only plain (sequential-slot) state variables; hashed-location slots (mappings/arrays) can only come from the seed list", layoutSummary, fdLabels: Object.fromEntries([["FoundationDAO", layouts.FoundationDAO.storage.map((s) => `${s.slot}:${s.label}`)]]), results };
  fs.mkdirSync(`${ROOT}/evidence/04-results`, { recursive: true });
  fs.writeFileSync(`${ROOT}/evidence/04-results/${process.env.A14_OUT || "A14-static-scan.json"}`, JSON.stringify(out, (k, v) => (typeof v === "bigint" ? v.toString() : v), 2));
  console.log("wrote scan json; overall:", Object.values(results).every((r) => r.verdict === "PASS") ? "ALL PASS" : "SEE FAILURES");
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
