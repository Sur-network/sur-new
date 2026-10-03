// Proves that a fresh "twin" network has the SAME genesis as the original follow-up network it stands in for: identical alloc (accounts, balances, code, storage keys and values)
// and identical config/gasLimit/extraData/difficulty — except (a) the genesis timestamp, (b) storage values that ARE the genesis timestamp (windowStart, periodStartedAt) and (c) chainId.
const { ethers, ROOT, fs, saveEvidence } = require("./v5-lib");
const PAIRS = {
  "Net-T-F1": ["Net-F1"], "Net-T-F2": ["Net-F2", "Net-F5", "Net-F5b"], "Net-T-F3": ["Net-F3"], "Net-T-F4": ["Net-F4"], "Net-T-F6": ["Net-F6"],
  "Net-T-L05": ["Net-L05a", "Net-L05b"], "Net-T-D3": ["Net-D3", "Net-A14"], "Net-T-E15": ["Net-E15"], "Net-T-E30": ["Net-E30"], "Net-T-E60": ["Net-E60"], "Net-L04f": ["Net-L05a"],
};
const only = process.env.TWINS ? process.env.TWINS.split(",") : Object.keys(PAIRS);
const norm = (h) => (h.startsWith("0x") ? h : "0x" + h).toLowerCase();
const tsHex32 = (ts) => ethers.zeroPadValue(ethers.toBeHex(BigInt(ts)), 32).toLowerCase();
function load(net) {
  const f = net === "Net-F4" ? `${ROOT}/nets/Net-F4/genesis-original-no-transition.json` : `${ROOT}/nets/${net}/genesis.json`;
  const g = JSON.parse(fs.readFileSync(f, "utf8")); g._file = f.replace(ROOT + "/", ""); return g;
}
function canon(g) {
  const ts = BigInt(parseInt(g.timestamp, 16)), T = tsHex32(ts);
  const alloc = {};
  for (const [k, v] of Object.entries(g.alloc)) {
    const a = ethers.getAddress(k.startsWith("0x") ? k : "0x" + k).toLowerCase();
    const st = {}; for (const [sk, sv] of Object.entries(v.storage || {})) { const val = ethers.zeroPadValue(norm(sv), 32).toLowerCase(); st[ethers.zeroPadValue(norm(sk), 32).toLowerCase()] = val === T ? "<GENESIS_TIMESTAMP>" : val; }
    alloc[a] = { balance: String(BigInt(v.balance || 0)), code: (v.code || "0x").toLowerCase(), storage: st };
  }
  const cfg = JSON.parse(JSON.stringify(g.config)); delete cfg.chainId;
  return { alloc, cfg, gasLimit: g.gasLimit, difficulty: g.difficulty, extraData: g.extraData, ts };
}
const res = {};
for (const twin of only) {
  const t = canon(load(twin));
  for (const orig of PAIRS[twin]) {
    const o = canon(load(orig)), diffs = [];
    for (const a of new Set([...Object.keys(o.alloc), ...Object.keys(t.alloc)])) {
      if (!o.alloc[a]) { diffs.push(`account only in twin: ${a}`); continue; } if (!t.alloc[a]) { diffs.push(`account only in original: ${a}`); continue; }
      const x = o.alloc[a], y = t.alloc[a];
      if (x.balance !== y.balance) diffs.push(`balance ${a}: ${x.balance} vs ${y.balance}`);
      if (x.code !== y.code) diffs.push(`code ${a}`);
      for (const k of new Set([...Object.keys(x.storage), ...Object.keys(y.storage)])) if (x.storage[k] !== y.storage[k]) diffs.push(`storage ${a} ${k.slice(0, 14)}…: ${x.storage[k]} vs ${y.storage[k]}`);
    }
    if (JSON.stringify(o.cfg) !== JSON.stringify(t.cfg)) diffs.push("config (without chainId) differs");
    if (o.gasLimit !== t.gasLimit) diffs.push("gasLimit differs"); if (o.difficulty !== t.difficulty) diffs.push("difficulty differs"); if (o.extraData !== t.extraData) diffs.push("extraData differs");
    const nAcc = Object.keys(o.alloc).length, nSlots = Object.values(o.alloc).reduce((s, v) => s + Object.keys(v.storage).length, 0);
    const tsSlots = Object.values(o.alloc).reduce((s, v) => s + Object.values(v.storage).filter((x) => x === "<GENESIS_TIMESTAMP>").length, 0);
    res[`${twin} ~ ${orig}`] = { equivalent: diffs.length === 0, accounts: nAcc, storageSlots: nSlots, slotsHoldingGenesisTimestamp: tsSlots, originalGenesisFile: load(orig)._file, differences: diffs.slice(0, 20) };
    console.log(`${twin} ~ ${orig}: ${diffs.length === 0 ? "EQUIVALENT" : "DIFFERENT (" + diffs.length + ")"}  (${nAcc} accounts, ${nSlots} slots, ${tsSlots} timestamp-valued)`);
  }
}
saveEvidence("A-twin-equivalence.json", { rule: "alloc, config (without chainId), gasLimit, difficulty and extraData must be identical; storage values equal to the genesis timestamp are compared symbolically", results: res });
