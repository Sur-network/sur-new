// Group A live checks (A01-A13, A15; A14 is NOT repeated — see A14-static-scan.json / A14-live-stateroot.json) on a PRISTINE network (no transaction ever sent).
// Every check ASSERTS its expectation (brief §7 table + genesis-builder spec §4.2.1 assertion list) and records expected, actual and the raw values.
// env: NET (a key of META), or GLOBAL=1 for the network-independent parts (A01 hashes, compile hashes, A05 immutableReferences).
const { ethers, ADDR, accounts, rpc, hex, ROOT, fs, path, saveEvidence } = require("./v5-lib");
const PLAN = "D:/Amir/Business/SUR/NewSur/Plan";
const FP = JSON.parse(fs.readFileSync(`${ROOT}/evidence/00-baseline/fixed-contracts-fingerprint.json`, "utf8"));
const E18 = 10n ** 18n;
const T300 = [{ block: 300, blockreward: "3000000000000000000" }];
const T6 = [{ block: 100, blockreward: "3000000000000000000" }, { block: 150, blockreward: "2000000000000000000" }, { block: 200, blockreward: "4000000000000000000" }];
const E399 = Array.from({ length: 399 }, (_, i) => [151 + i, 2n * E18]);
const META = {
  "Net-T-F1": { port: 9401, founders: "G5", cand: false, gas: 30000000, chain: 424501, transitions: T300, history: [[300, 3n * E18]], payees: 0, originals: ["Net-F1"] },
  "Net-T-F2": { port: 9411, founders: "G5", cand: false, gas: 30000000, chain: 424502, transitions: T300, history: [], payees: 0, originals: ["Net-F2", "Net-F5", "Net-F5b"] },
  "Net-T-F3": { port: 9421, founders: "G5", cand: false, gas: 30000000, chain: 424503, transitions: null, history: [[300, 3n * E18]], payees: 0, originals: ["Net-F3"] },
  "Net-T-F4": { port: 9431, founders: "G5", cand: false, gas: 30000000, chain: 424504, transitions: null, history: [], payees: 0, originals: ["Net-F4"] },
  "Net-T-F6": { port: 9441, founders: "G5", cand: true, gas: 30000000, chain: 424505, transitions: T6, history: [[100, 3n * E18]], payees: 0, originals: ["Net-F6"] },
  "Net-T-L05": { port: 9451, founders: "G5", cand: false, gas: 30000000, chain: 424506, transitions: null, history: [], payees: 0, originals: ["Net-L05a", "Net-L05b"] },
  "Net-T-D3": { port: 9461, founders: "G6", cand: true, gas: 30000000, chain: 424507, transitions: null, history: [], payees: 0, originals: ["Net-D3", "Net-A14"] },
  "Net-T-E15": { port: 9471, founders: "G5", cand: false, gas: 15000000, chain: 424508, transitions: null, history: E399, payees: 150, originals: ["Net-E15"] },
  "Net-T-E30": { port: 9481, founders: "G5", cand: false, gas: 30000000, chain: 424509, transitions: null, history: E399, payees: 150, originals: ["Net-E30"] },
  "Net-T-E60": { port: 9491, founders: "G5", cand: false, gas: 60000000, chain: 424510, transitions: null, history: E399, payees: 150, originals: ["Net-E60"] },
  "Net-L04f": { port: 9501, founders: "G5", cand: false, gas: 30000000, chain: 424511, transitions: null, history: [], payees: 0, originals: [] },
  "Net-BR": { port: 9601, founders: "G5", cand: false, gas: 30000000, chain: 424601, transitions: null, history: [], payees: 0, originals: [] },
  "Net-BR0": { port: 9611, founders: "G5", cand: false, gas: 30000000, chain: 424602, transitions: null, history: [], payees: 0, originals: [] },
  "Net-L04g": { port: 9621, founders: "G5", cand: false, gas: 30000000, chain: 424603, transitions: null, history: [], payees: 0, originals: [] },
};
const out = { checks: [] };
let provider, call;
function chk(id, sub, expected, actual, pass, note) {
  const rec = { id, sub, expected: String(expected), actual: String(actual), pass: pass === null ? null : !!pass };
  if (note) rec.note = note;
  out.checks.push(rec);
  return rec.pass;
}
async function guard(id, sub, fn) { try { await fn(); } catch (e) { chk(id, sub, "(no error)", "ERROR: " + (e.shortMessage || e.message).slice(0, 160), false); } }
const eq = (a, b) => String(a).toLowerCase() === String(b).toLowerCase();

// ------------------------------------------------------------------ GLOBAL: A01, compile hashes, A05(a)
async function globalChecks() {
  const brief = fs.readFileSync(`${PLAN}/sur-besu-live-test-brief-v4.md`, "utf8").replace(/\r\n/g, "\n");
  const start = brief.indexOf("### ۲.۱"), end = brief.indexOf("### ۲.۲");
  const blocks = [...brief.slice(start, end).matchAll(/```\n([\s\S]*?)```/g)].map((m) => m[1]);
  const sha = (p) => require("crypto").createHash("sha256").update(fs.readFileSync(p)).digest("hex");
  [["contracts", blocks[0]], ["contracts-fa", blocks[1]]].forEach(([dir, blk]) => {
    let n = 0, bad = [];
    for (const l of blk.split("\n")) { const m = l.match(/^([0-9a-f]{64})\s+(\S+)/); if (!m) continue; n++; const f = `${PLAN}/${dir}/${m[2]}`; if (!fs.existsSync(f) || sha(f) !== m[1]) bad.push(m[2]); }
    chk("A01", `sha256 of ${dir}/ vs the brief §2.1 table (${n} files)`, "all equal", bad.length ? "mismatch: " + bad.join(",") : "all equal", bad.length === 0 && n === 13);
  });
  // the evidence baseline copy (what the Besu genesis code was built from) vs Plan
  let diff = 0; for (const f of fs.readdirSync(`${ROOT}/hardhat/contracts-baseline`).filter((x) => x.endsWith(".sol"))) if (sha(`${ROOT}/hardhat/contracts-baseline/${f}`) !== sha(`${PLAN}/contracts/${f}`)) diff++;
  chk("A01", "hardhat/contracts-baseline (build inputs of every genesis) vs Plan/contracts", "0 differing files", `${diff} differing`, diff === 0);
  // compile hash: fresh runtime bytecode from the hardhat artifacts vs the fingerprint recorded at phase 0
  const bi = JSON.parse(fs.readFileSync(`${ROOT}/hardhat/artifacts/build-info/` + fs.readdirSync(`${ROOT}/hardhat/artifacts/build-info`)[0], "utf8"));
  const solc = bi.solcVersion, opt = bi.input.settings.optimizer, viaIR = !!bi.input.settings.viaIR;
  chk("A01", "compile settings", "solc 0.8.24, optimizer enabled runs=200, viaIR=false", `solc ${solc}, optimizer ${JSON.stringify(opt)}, viaIR=${viaIR}`, solc === "0.8.24" && opt.enabled && opt.runs === 200 && !viaIR);
  for (const [name, v] of Object.entries(FP)) {
    const art = JSON.parse(fs.readFileSync(`${ROOT}/hardhat/artifacts/contracts-baseline/${name}.sol/${name}.json`, "utf8"));
    const h = ethers.keccak256(art.deployedBytecode);
    chk("A01", `runtime-bytecode hash of ${name} (fresh artifact vs phase-0 fingerprint)`, v.runtimeHash, h, h === v.runtimeHash);
  }
  // A05 (a): immutableReferences of the distributor in the compile output
  const ctr = bi.output.contracts["contracts-baseline/BlockRewardDistributor.sol"].BlockRewardDistributor;
  const imm = JSON.stringify(ctr.evm.deployedBytecode.immutableReferences || {});
  chk("A05", "BlockRewardDistributor immutableReferences in the compile output", "{}", imm, imm === "{}");
}

// ------------------------------------------------------------------ PER NETWORK
async function netChecks(NET, M) {
  const URL = `http://127.0.0.1:${M.port}`;
  provider = new ethers.JsonRpcProvider(URL); call = rpc(URL);
  const gpath = `${ROOT}/nets/${NET}/genesis.json`;
  const g = JSON.parse(fs.readFileSync(gpath, "utf8"));
  const ts = BigInt(parseInt(g.timestamp, 16));
  const founders = (M.founders === "G5" ? [1, 2, 3, 4, 5].map((i) => accounts[`g5_v${i}`]) : [1, 2, 3, 4, 5, 6].map((i) => accounts[`g6_v${i}`])).map((a) => a.address);
  const foundation = Array.from({ length: 15 }, (_, i) => accounts[`foundation${i + 1}`].address);
  const head = await provider.getBlockNumber();
  out.net = NET; out.head = head; out.genesisTimestamp = String(ts); out.client = await call("web3_clientVersion");

  // ---- precondition: pristine (no transaction ever, nonces 0) ----
  let txTotal = 0; for (let n = 1; n <= head; n++) { const b = await call("eth_getBlockByNumber", [hex(n), false]); txTotal += b.transactions.length; }
  const nonces = {}; for (const a of [...founders, accounts.verifier.address, accounts.distributionOracle.address]) nonces[a] = Number(BigInt(await call("eth_getTransactionCount", [a, "latest"])));
  const pristine = txTotal === 0 && Object.values(nonces).every((x) => x === 0);
  chk("PRE", "pristine state: no transaction in blocks 1..head, nonces of founders/verifier/oracle are 0", "0 txs, nonces 0", `${txTotal} txs in ${head} blocks; max nonce ${Math.max(...Object.values(nonces))}`, pristine);
  if (!pristine) { out.aborted = "network is not pristine — initial-state checks are not valid here"; return; }

  // ---- A02 genesis structure (file + live) ----
  const c = g.config, q = c.qbft || {};
  const forks = ["homesteadBlock", "eip150Block", "eip155Block", "eip158Block", "byzantiumBlock", "constantinopleBlock", "petersburgBlock", "istanbulBlock", "berlinBlock", "londonBlock"];
  chk("A02", "hard forks homestead..london all 0", "all 0", forks.map((f) => c[f]).join(","), forks.every((f) => c[f] === 0));
  chk("A02", "zeroBaseFee", "true", c.zeroBaseFee, c.zeroBaseFee === true);
  chk("A02", "qbft blockperiodseconds / epochlength / requesttimeoutseconds", "3 / 30000 / 10", `${q.blockperiodseconds} / ${q.epochlength} / ${q.requesttimeoutseconds}`, q.blockperiodseconds === 3 && q.epochlength === 30000 && q.requesttimeoutseconds === 10);
  chk("A02", "qbft validatorcontractaddress / miningbeneficiary", `${ADDR.REGISTRY} / ${ADDR.DISTRIBUTOR}`, `${q.validatorcontractaddress} / ${q.miningbeneficiary}`, eq(q.validatorcontractaddress, ADDR.REGISTRY) && eq(q.miningbeneficiary, ADDR.DISTRIBUTOR));
  chk("A02", "qbft blockreward", "2000000000000000000", q.blockreward, q.blockreward === "2000000000000000000");
  chk("A02", "chainId (file)", M.chain, c.chainId, c.chainId === M.chain);
  chk("A02", "declared gasLimit (file)", M.gas, parseInt(g.gasLimit, 16), parseInt(g.gasLimit, 16) === M.gas);
  chk("A02", "transitions.qbft (file)", JSON.stringify(M.transitions || null), JSON.stringify(c.transitions ? c.transitions.qbft : null), JSON.stringify(M.transitions || null) === JSON.stringify(c.transitions ? c.transitions.qbft : null));
  const b0 = await call("eth_getBlockByNumber", ["0x0", false]);
  chk("A02", "live eth_chainId", M.chain, Number(BigInt(await call("eth_chainId"))), Number(BigInt(await call("eth_chainId"))) === M.chain);
  chk("A02", "live block-0 gasLimit equals the declared gasLimit", M.gas, Number(BigInt(b0.gasLimit)), Number(BigInt(b0.gasLimit)) === M.gas);
  const cfg = fs.readFileSync(`${ROOT}/nets/${NET}/node1/config.toml`, "utf8");
  chk("A02", "node config: min-gas-price=100000000000000 and TRACE api enabled", "both", `min-gas-price ${/min-gas-price=100000000000000/.test(cfg)}; TRACE ${/"TRACE"/.test(cfg)}`, /min-gas-price=100000000000000/.test(cfg) && /"TRACE"/.test(cfg));
  // ---- A03 extraData ----
  const wantExtra = ethers.encodeRlp(["0x" + "00".repeat(32), [], [], "0x", []]);
  chk("A03", "extraData = RLP([vanity 32 bytes, [], [], 0x, []]) (file and live block 0)", wantExtra, `file ${g.extraData}; live ${b0.extraData}`, eq(g.extraData, wantExtra) && eq(b0.extraData, wantExtra));

  // ---- A04 live code hashes ----
  for (const [name, v] of Object.entries(FP)) { const code = await call("eth_getCode", [v.address, "latest"]); const h = ethers.keccak256(code); chk("A04", `live keccak256(eth_getCode) of ${name} (${v.address})`, v.runtimeHash, h, h === v.runtimeHash); }
  // ---- A05 (b): no code on any other alloc account; balances as genesis ----
  const fixed = new Set(Object.values(ADDR).map((a) => a.toLowerCase()));
  let extraCode = 0, balBad = 0, n = 0;
  for (const [k, v] of Object.entries(g.alloc)) { const a = ethers.getAddress(k.startsWith("0x") ? k : "0x" + k).toLowerCase(); if (fixed.has(a)) continue; n++; if ((await call("eth_getCode", [a, "latest"])) !== "0x") extraCode++; if (BigInt(await call("eth_getBalance", [a, "latest"])) !== BigInt(v.balance || 0)) balBad++; }
  chk("A05", `no code at the ${n} non-contract alloc accounts and balances equal the genesis balances`, "0 with code, 0 balance differences", `${extraCode} with code, ${balBad} balance differences`, extraCode === 0 && balBad === 0, "storage/extra-account absence: A14 (static scan + live block-0 state root), not repeated");

  // ---- contracts ----
  const reg = new ethers.Contract(ADDR.REGISTRY, ["function getValidators() view returns (address[])", "function isValidator(address) view returns (bool)", "function everActivated(address) view returns (bool)", "function statusNonce() view returns (uint256)", "function wasActiveAt(address,uint256) view returns (bool)", "function verifier() view returns (address)", "function probationPeriod() view returns (uint256)", "function recoveryPeriod() view returns (uint256)", "function exitCooldown() view returns (uint256)", "function maxEntriesPerWindow() view returns (uint256)", "function windowStart() view returns (uint256)", "function entryThresholdBase() view returns (uint256)", "function growthFactorPerValidator() view returns (uint256)", "function membershipFeeBps() view returns (uint256)", "function entryWindowSeconds() view returns (uint256)", "function slashBps() view returns (uint256)", "function paidValidatorCount() view returns (uint256)", "function getActiveValidatorCount() view returns (uint256)", "function validators(address) view returns (uint8 status,uint256 lockedStake,uint256 periodStartedAt,uint256 pendingSlashEpoch,uint256 demotedAt,bool isPaidEntrant)"], provider);
  const layout = FP.ValidatorsRegistry.storageLayout.storage; const slotOf = (l) => BigInt(layout.find((s) => s.label === l).slot);
  const mapSlot = (a, s) => ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(["address", "uint256"], [a, s]));
  const getSlot = async (a, s) => BigInt(await call("eth_getStorageAt", [a, typeof s === "string" ? s : "0x" + BigInt(s).toString(16), "latest"]));

  // A06
  await guard("A06", "getValidators", async () => { const v = await reg.getValidators(); chk("A06", `getValidators() == the ${founders.length} founders, in seed order`, founders.join(","), v.join(","), v.length === founders.length && v.every((x, i) => eq(x, founders[i]))); });
  // A07
  await guard("A07", "founders", async () => {
    for (const a of founders) {
      const iv = await reg.isValidator(a), ea = await reg.everActivated(a), raw = await getSlot(ADDR.REGISTRY, mapSlot(a, slotOf("everActivated")));
      chk("A07", `${a}: isValidator, everActivated (getter and raw slot ${slotOf("everActivated")})`, "true, true, 0x1", `${iv}, ${ea}, 0x${raw.toString(16)}`, iv && ea && raw === 1n);
    }
  });
  // A08
  await guard("A08", "checkpoint", async () => {
    chk("A08", "statusNonce()", "0", (await reg.statusNonce()).toString(), (await reg.statusNonce()) === 0n);
    const wa = [], bad = [];
    for (const a of founders) { const r = await reg.wasActiveAt(a, 0); wa.push(r); const cp = mapSlot(a, slotOf("activeCheckpoints")); const len = await getSlot(ADDR.REGISTRY, cp); const el = await getSlot(ADDR.REGISTRY, "0x" + BigInt(ethers.keccak256(ethers.zeroPadValue(cp, 32))).toString(16)); if (!(r && len === 1n && el === (1n << 64n))) bad.push(a); }
    chk("A08", `wasActiveAt(founder,0)==true and raw activeCheckpoints (slot ${slotOf("activeCheckpoints")}): length 1, first element 1<<64, for all ${founders.length} founders`, "all true", bad.length ? "failing: " + bad.join(",") : "all true", bad.length === 0);
    const non = [accounts.fakeAddress.address, ...(M.cand ? [accounts.g5_c6.address] : [])];
    const r = await Promise.all(non.map((a) => reg.wasActiveAt(a, 0)));
    chk("A08", "wasActiveAt(non-founder,0) == false (fake address" + (M.cand ? " and the candidate C6" : "") + ")", "false", r.join(","), r.every((x) => x === false));
  });
  // A09
  const board = new ethers.Contract(ADDR.BOARD, ["function getBoardMembers() view returns (address[])", "function boardVersion() view returns (uint256)", "function lastBoardRefreshAt() view returns (uint256)"], provider);
  await guard("A09", "board", async () => {
    const m = await board.getBoardMembers(); chk("A09", "getBoardMembers() == first 5 founders", founders.slice(0, 5).join(","), m.join(","), m.length === 5 && m.every((x, i) => eq(x, founders[i])));
    chk("A09", "boardVersion()", "1 (field initializer)", (await board.boardVersion()).toString(), (await board.boardVersion()) === 1n);
    const last = await board.lastBoardRefreshAt();
    chk("A09", "lastBoardRefreshAt() vs the genesis-builder spec assertion (spec §4.2.1: == network.genesisTimestamp when the board is seeded; brief A09: compare with the spec)", String(ts), last.toString(), last === ts, last === 0n ? "SPEC DISCREPANCY (test-tool gap, not a contract defect): the test builder does not write lastBoardRefreshAt, so it stays 0 and the first refreshBoard() is immediately allowed; the spec asserts it should equal the genesis timestamp. Identical on every network built by this builder, including the earlier Net-B/Net-D (their A09 was recorded without this comparison)." : undefined);
  });
  // A10
  const fd = new ethers.Contract(ADDR.FOUNDATION, ["function memberList(uint256) view returns (string name,address account)", "function membershipNonce() view returns (uint256)", "function memberSinceNonce(address) view returns (uint256)", "function getMemberCount() view returns (uint256)"], provider);
  await guard("A10", "foundation", async () => {
    chk("A10", "getMemberCount()", "15", (await fd.getMemberCount()).toString(), (await fd.getMemberCount()) === 15n);
    chk("A10", "membershipNonce()", "0", (await fd.membershipNonce()).toString(), (await fd.membershipNonce()) === 0n);
    const bad = [];
    for (let i = 0; i < 15; i++) { const [nm, ac] = await fd.memberList(i); const since = await fd.memberSinceNonce(ac); if (!(eq(ac, foundation[i]) && since === 0n && nm.length > 0)) bad.push(i); }
    chk("A10", "15 members: account == seed order, memberSinceNonce == 0, non-empty name", "all 15 ok", bad.length ? "failing indexes " + bad.join(",") : "all 15 ok", bad.length === 0);
  });
  // A11 / A12
  const dist = new ethers.Contract(ADDR.DISTRIBUTOR, ["function INITIAL_REWARD_PER_BLOCK() view returns (uint256)", "function rewardRateChangeCount() view returns (uint256)", "function rateProposalCount() view returns (uint256)", "function lastSettledBlock() view returns (uint256)", "function epochCount() view returns (uint256)", "function distributionOracle() view returns (address)", "function validatorDirectShareBps() view returns (uint256)", "function maxRewardsForRange(uint256,uint256) view returns (uint256)", "function RATE_VOTING_EXPIRY() view returns (uint256)", "function RATE_CHANGE_DELAY() view returns (uint256)", "function MIN_RATE_CHANGE_LEAD_BLOCKS() view returns (uint256)"], provider);
  await guard("A11", "distributor", async () => {
    const eqv = async (sub, fn, want) => { const got = await fn(); chk("A11", sub, want, got.toString(), got.toString() === want.toString()); };
    await eqv("INITIAL_REWARD_PER_BLOCK()", () => dist.INITIAL_REWARD_PER_BLOCK(), 2n * E18);
    await eqv(`rewardRateChangeCount() (seeded entries: ${M.history.length})`, () => dist.rewardRateChangeCount(), M.history.length);
    await eqv("rateProposalCount()", () => dist.rateProposalCount(), 0);
    await eqv("lastSettledBlock()", () => dist.lastSettledBlock(), 0);
    await eqv("epochCount()", () => dist.epochCount(), 0);
    const o = await dist.distributionOracle(); chk("A11", "distributionOracle()", accounts.distributionOracle.address, o, eq(o, accounts.distributionOracle.address));
    await eqv("validatorDirectShareBps() (genesis value)", () => dist.validatorDirectShareBps(), 5000);
    let want = 0n, cursor = 1n, rate = 2n * E18; for (const [s, r] of M.history) { if (BigInt(s) > 1000n) break; want += (BigInt(s) - cursor) * rate; cursor = BigInt(s); rate = BigInt(r); } want += (1000n - cursor + 1n) * rate;
    await eqv(`maxRewardsForRange(1,1000) (independent formula over the ${M.history.length} seeded entries)`, () => dist.maxRewardsForRange(1, 1000), want);
    await eqv("RATE_VOTING_EXPIRY()", () => dist.RATE_VOTING_EXPIRY(), 30 * 86400);
    await eqv("RATE_CHANGE_DELAY()", () => dist.RATE_CHANGE_DELAY(), 7 * 86400);
    await eqv("MIN_RATE_CHANGE_LEAD_BLOCKS()", () => dist.MIN_RATE_CHANGE_LEAD_BLOCKS(), 201600);
  });
  await guard("A12", "slots", async () => {
    const vals = []; for (let s = 24; s <= 28; s++) vals.push(await getSlot(ADDR.DISTRIBUTOR, s));
    const want = [BigInt(M.history.length), 0n, 0n, 0n, 0n];
    chk("A12", `distributor slots 24..28 (rewardRateChanges length${M.history.length ? " = seeded count" : " = 0"}; rateProposals, rateBoardVoted, rateValidatorVoted, rateProposalCount = 0)`, want.join(","), vals.join(","), vals.every((v, i) => v === want[i]), M.history.length ? "TEST-ONLY-SEED: slot 24 holds the seeded history length" : undefined);
  });
  // A13 overlays + spec assertion list
  await guard("A13", "registry overlays", async () => {
    const eqv = async (sub, fn, want) => { const got = await fn(); chk("A13", sub, want, got.toString(), got.toString().toLowerCase() === want.toString().toLowerCase()); };
    await eqv("Registry.verifier()", () => reg.verifier(), accounts.verifier.address);
    await eqv("Registry.probationPeriod() (test overlay)", () => reg.probationPeriod(), 300);
    await eqv("Registry.recoveryPeriod() (test overlay; must stay > MASS_DEMOTION_WINDOW 3600)", () => reg.recoveryPeriod(), 3700);
    await eqv("Registry.exitCooldown() (test overlay)", () => reg.exitCooldown(), 600);
    await eqv("Registry.maxEntriesPerWindow() (test overlay)", () => reg.maxEntriesPerWindow(), 10);
    await eqv("Registry.windowStart() == genesis timestamp", () => reg.windowStart(), ts);
    await eqv("Registry.entryThresholdBase() (source value)", () => reg.entryThresholdBase(), 500000n * E18);
    await eqv("Registry.growthFactorPerValidator() (source value)", () => reg.growthFactorPerValidator(), 1017479692102686336n);
    await eqv("Registry.membershipFeeBps() (source value)", () => reg.membershipFeeBps(), 400);
    await eqv("Registry.entryWindowSeconds() (source value)", () => reg.entryWindowSeconds(), 86400);
    await eqv("Registry.slashBps() (source value)", () => reg.slashBps(), 100);
    await eqv("Registry.paidValidatorCount() (must stay 0)", () => reg.paidValidatorCount(), 0);
    await eqv("Registry.getActiveValidatorCount()", () => reg.getActiveValidatorCount(), founders.length);
    const pe = []; for (const a of founders) pe.push((await reg.validators(a)).isPaidEntrant);
    chk("A13", "validators(founder).isPaidEntrant == false for every founder", "all false", pe.join(","), pe.every((x) => x === false));
  });
  const tre = new ethers.Contract(ADDR.TREASURY, ["function perPaymentCap() view returns (uint256)", "function periodCap() view returns (uint256)"], provider);
  await guard("A13", "treasury", async () => {
    chk("A13", "Treasury.perPaymentCap() (source initializer, brief: 50,000 SUR)", String(50000n * E18), (await tre.perPaymentCap()).toString(), (await tre.perPaymentCap()) === 50000n * E18);
    chk("A13", "Treasury.periodCap() (source initializer, brief: 200,000 SUR)", String(200000n * E18), (await tre.periodCap()).toString(), (await tre.periodCap()) === 200000n * E18);
  });

  // A15
  const periods = [];
  if (head >= 100) {
    let prev = BigInt((await call("eth_getBlockByNumber", ["0x0", false])).timestamp);
    for (let i = 1; i <= 100; i++) { const t = BigInt((await call("eth_getBlockByNumber", [hex(i), false])).timestamp); periods.push(Number(t - prev)); prev = t; }
    const all = [...periods].sort((a, b) => a - b), rest = periods.slice(1).sort((a, b) => a - b);
    const st = (a) => ({ avg: +(a.reduce((x, y) => x + y, 0) / a.length).toFixed(2), min: a[0], max: a[a.length - 1], p95: a[Math.floor(a.length * 0.95)] });
    out.A15_stats = { first100IncludingGenesisGap: st(all), first100ExcludingGenesisGap: st(rest), genesisToBlock1Gap: periods[0] };
    chk("A15", "the chain advances over the first 100 blocks (brief: 'the chain advances'; block-period mean/min/max/p95 recorded, no numeric threshold in the brief)", "100 consecutive blocks produced", `${periods.length} blocks; ${JSON.stringify(out.A15_stats.first100ExcludingGenesisGap)} (blocks 2..100); genesis->block1 gap ${periods[0]} s`, periods.length === 100);
  } else chk("A15", "first 100 blocks", ">= 100 blocks", `only ${head}`, false);
  await guard("A15", "qbft", async () => {
    const q1 = await call("qbft_getValidatorsByBlockNumber", ["latest"]); const gv = await reg.getValidators();
    const same = q1.length === gv.length && [...q1].map((x) => x.toLowerCase()).sort().join() === [...gv].map((x) => x.toLowerCase()).sort().join();
    chk("A15", "qbft_getValidatorsByBlockNumber('latest') equals Registry.getValidators() (as sets)", gv.join(","), q1.join(","), same);
  });
  out.preconditionNoTxHead = head;
}

async function main() {
  if (process.env.GLOBAL === "1") { await globalChecks(); out.net = "(global)"; }
  else { const NET = process.env.NET; if (!META[NET]) throw new Error("unknown NET " + NET); await netChecks(NET, META[NET]); }
  const fails = out.checks.filter((c) => c.pass === false);
  out.summary = { total: out.checks.length, pass: out.checks.filter((c) => c.pass === true).length, fail: fails.length, failing: fails.map((c) => `${c.id}: ${c.sub}`) };
  out.at = new Date().toISOString();
  console.log(out.net, JSON.stringify(out.summary));
  saveEvidence(process.env.GLOBAL === "1" ? "A-live-GLOBAL.json" : `A-live-${out.net}.json`, out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
