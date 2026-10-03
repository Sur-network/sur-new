// Counts the rows of REPORT.md's result table by status (the Result column), so the Summary counts are computed, not hand-typed.
// usage: node count-results.js [path-to-REPORT.md]
const fs = require("fs");
const p = process.argv[2] || "D:/Amir/Business/SUR/Test/besu-test-v4/REPORT.md";
const lines = fs.readFileSync(p, "utf8").split("\n");
const start = lines.findIndex((l) => l.startsWith("| ID | Title |"));
const rows = [];
for (let i = start + 2; i < lines.length && lines[i].startsWith("|"); i++) {
  const cells = lines[i].split("|").slice(1, -1).map((c) => c.trim());
  rows.push({ line: i + 1, id: cells[0], result: cells[4] });
}
const classify = (r) => { const m = r.replace(/\*/g, "").match(/^(PASS|FAIL|BLOCKED|INCONCLUSIVE|NOT-RUN|SUPERSEDED)/); return m ? m[1] : "UNCLASSIFIED"; };
const counts = {};
for (const r of rows) { r.status = classify(r.result); counts[r.status] = (counts[r.status] || 0) + 1; }
console.log("total rows:", rows.length);
console.log(JSON.stringify(counts));
for (const s of Object.keys(counts)) console.log(`${s} (${counts[s]}):`, rows.filter((r) => r.status === s).map((r) => `${r.id}@L${r.line}`).join("; "));
