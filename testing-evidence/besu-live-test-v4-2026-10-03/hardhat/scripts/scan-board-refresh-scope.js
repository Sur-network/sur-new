// Scope of the A09 `lastBoardRefreshAt` defect: reads every genesis.json of every network of this campaign (evidence/02-genesis/*/ and nets/*/) and reports
// ValidatorsBoard storage slot 0 (boardMembers.length), slot 6 (boardVersion) and slot 7 (lastBoardRefreshAt) against the genesis timestamp.
// Also scans the test scripts and raw results for any call of refreshBoard(), and the compiled source for every reader of lastBoardRefreshAt.
const fs = require("fs"), path = require("path");
const ROOT = "D:/Amir/Business/SUR/Test/besu-test-v4";
const BOARD = "4444444444444444444444444444444444444444";
const slotKey = (i) => "0x" + BigInt(i).toString(16).padStart(64, "0");
const layout = JSON.parse(fs.readFileSync(`${ROOT}/evidence/00-baseline/storage-layout-ValidatorsBoard.json`, "utf8"));
const rows = [];
const seen = new Set();
for (const base of [`${ROOT}/evidence/02-genesis`, `${ROOT}/nets`]) {
  for (const net of fs.readdirSync(base).sort()) {
    const f = path.join(base, net, "genesis.json");
    if (!fs.existsSync(f)) continue;
    const g = JSON.parse(fs.readFileSync(f, "utf8"));
    const b = (g.alloc[BOARD] || g.alloc["0x" + BOARD] || {});
    const st = b.storage || {};
    const ts = BigInt(g.timestamp);
    const members = BigInt(st[slotKey(layout.boardMembers)] || "0x0");
    const last = BigInt(st[slotKey(layout.lastBoardRefreshAt)] || "0x0");
    const ver = BigInt(st[slotKey(layout.boardVersion)] || "0x0");
    rows.push({ network: net, source: base.endsWith("nets") ? "nets" : "evidence/02-genesis", genesisTimestamp: ts.toString(), boardSeededMembers: Number(members), boardVersion: Number(ver), lastBoardRefreshAt: last.toString(), equalsGenesisTimestamp: last === ts, status: net === "Net-BR0" ? "NEGATIVE CONTROL (value 0 on purpose, built with BUILDER_BOARD_REFRESH_ZERO=1)" : members === 0n ? "board not seeded (spec: refresh allowed at once — by design)" : last === ts ? "OK (fixed)" : last === 0n ? "AFFECTED (value 0, board seeded)" : "UNEXPECTED" });
  }
}
// de-duplicate evidence/02-genesis vs nets (same network twice): keep one row per network, prefer evidence copy, but report mismatch if the two differ
const byNet = {};
for (const r of rows) { if (!byNet[r.network]) byNet[r.network] = r; else if (byNet[r.network].lastBoardRefreshAt !== r.lastBoardRefreshAt || byNet[r.network].genesisTimestamp !== r.genesisTimestamp) byNet[r.network].copyMismatch = `nets copy differs: ${r.lastBoardRefreshAt} / ${r.genesisTimestamp}`; }
const nets = Object.values(byNet);

// who reads lastBoardRefreshAt (contract source) and which test scripts/results call refreshBoard
const src = fs.readFileSync("D:/Amir/Business/SUR/NewSur/Plan/contracts/ValidatorsBoard.sol", "utf8").split("\n");
const readers = src.map((l, i) => ({ line: i + 1, text: l.trim() })).filter((x) => /lastBoardRefreshAt/.test(x.text) && !x.text.startsWith("//") && !x.text.startsWith("///"));
const scripts = [];
for (const dir of [`${ROOT}/hardhat/scripts`, `${ROOT}/hardhat-fork/scripts`]) {
  if (!fs.existsSync(dir)) continue;
  for (const f of fs.readdirSync(dir)) {
    if (!f.endsWith(".js") || f.includes("pre-A09-fix")) continue;
    // this pass's own tools mention refreshBoard by design; the question is whether any EARLIER test called it
    if (["make-a-coverage.js","scan-board-refresh-scope.js","testonly-a-live.js","testonly-board-refresh.js","testonly-cl04-6b.js"].includes(f)) continue;
    const t = fs.readFileSync(path.join(dir, f), "utf8");
    const m = t.match(/refreshBoard/g);
    if (m) scripts.push({ file: path.relative(ROOT, path.join(dir, f)).replace(/\\/g, "/"), refreshBoardMentions: m.length });
  }
}
const results = [];
for (const f of fs.readdirSync(`${ROOT}/evidence/04-results`)) {
  if (!f.endsWith(".json") && !f.endsWith(".md")) continue;
  if (f.startsWith("A-live-") || f.startsWith("A09-fix") || f.includes("board-refresh")) continue; // this pass's own outputs (they mention refreshBoard in their notes)
  const t = fs.readFileSync(`${ROOT}/evidence/04-results/${f}`, "utf8");
  if (/refreshBoard/.test(t)) results.push(f);
}
const out = {
  generatedAt: new Date().toISOString(),
  networks: nets,
  counts: { total: nets.length, negativeControl: nets.filter((r) => r.status.startsWith("NEGATIVE CONTROL")).length, affected: nets.filter((r) => r.status.startsWith("AFFECTED")).length, fixed: nets.filter((r) => r.status.startsWith("OK")).length, notSeeded: nets.filter((r) => r.status.startsWith("board not seeded")).length, unexpected: nets.filter((r) => r.status.startsWith("UNEXPECTED")).length },
  contractReadersOfLastBoardRefreshAt: readers,
  scriptsMentioningRefreshBoard: scripts,
  rawResultsMentioningRefreshBoard: results,
};
fs.writeFileSync(`${ROOT}/evidence/04-results/A09-fix-genesis-scope.json`, JSON.stringify(out, null, 2) + "\n");
console.log(JSON.stringify(out.counts));
for (const r of nets) console.log(r.network.padEnd(18), String(r.boardSeededMembers).padStart(2), r.lastBoardRefreshAt.padEnd(12), r.status, r.copyMismatch || "");
console.log("contract readers:", readers.map((r) => `L${r.line}`).join(", "));
console.log("scripts mentioning refreshBoard:", scripts.map((s) => `${s.file}(${s.refreshBoardMentions})`).join("; "));
console.log("raw results mentioning refreshBoard:", results.join("; "));
