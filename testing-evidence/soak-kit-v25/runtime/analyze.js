// ANALYSIS (collect-results.sh runs this in a container, read-only on the run directory except for its own outputs):
// writes summary.md, occurrences-analysis.csv, per-phase.csv, per-hour.csv into <RUN_DIR>. No network access needed.
"use strict";
const { fs, path, readJson, RUN_DIR, KIT, pct, iso, stripAnsi } = require("./common");

const dir = (...p) => path.join(RUN_DIR, ...p);
const jsonl = (p) => { try { return fs.readFileSync(p, "utf8").split("\n").filter(Boolean).map((l) => { try { return JSON.parse(l); } catch (e) { return null; } }).filter(Boolean); } catch (e) { return []; } };
const run = readJson(dir("meta", "run.json"), {});
const win = readJson(dir("meta", "window.json"), null);
const NET = run.net || process.env.NET || "n7";
const nodesInfo = readJson(path.join(KIT, "nets", NET, "nodes-info.json"), []);
const opOf = Object.fromEntries(nodesInfo.map((n) => [n.node, n.operatorAddress.toLowerCase()]));
const nodeOfOp = Object.fromEntries(nodesInfo.map((n) => [n.operatorAddress.toLowerCase(), n.node]));

// ---- blocks
const blocks = [];
if (fs.existsSync(dir("blocks.csv"))) for (const l of fs.readFileSync(dir("blocks.csv"), "utf8").split("\n").slice(1)) { if (!l) continue; const f = l.split(","); blocks.push({ n: +f[0], ts: +f[1], seen: +f[2], hash: f[3], miner: f[4].toLowerCase(), tx: +f[5], gas: +f[6], round: +f[7], nv: +f[8], vs: +f[9] }); }
const byN = new Map(blocks.map((b) => [b.n, b]));
const valsets = new Map(jsonl(dir("valsets.jsonl")).map((v) => [v.id, v.validators]));
const events = jsonl(dir("load", "events.jsonl"));
const phaseEvents = events.filter((e) => e.type === "phase").sort((a, b) => a.ms - b.ms);
const startMs = win ? win.startMs : (blocks.length ? blocks[0].ts * 1000 : 0);
const endMs = win ? win.endMs : (blocks.length ? blocks[blocks.length - 1].ts * 1000 : 0);
const phaseOfMs = (ms) => { if (ms < startMs) return "bootstrap"; let p = null; for (const e of phaseEvents) { if (e.ms <= ms) p = e.name; else break; } return p || (ms > endMs + 5000 ? "after" : "unknown"); };
for (const b of blocks) b.phase = phaseOfMs(b.ts * 1000);
const inWindow = (b) => b.ts * 1000 >= startMs && b.ts * 1000 <= endMs + 5000;
const wb = blocks.filter(inWindow);
const idxOf = new Map(blocks.map((b, i) => [b.n, i]));
const delta = (b) => { const i = idxOf.get(b.n); return i > 0 ? b.ts - blocks[i - 1].ts : null; };

// list-change blocks = first block of a new validator-set id
const changeBlocks = []; for (let i = 1; i < blocks.length; i++) if (blocks[i].vs !== blocks[i - 1].vs) changeBlocks.push(blocks[i].n);
const changeSet = new Set(changeBlocks);
const winChangeBlocks = changeBlocks.filter((n) => inWindow(byN.get(n)));
const nearChange = (n, w) => { for (let d = -w; d <= w; d++) if (changeSet.has(n + d)) return true; return false; };
const f = (x, d = 2) => (x === null || x === undefined || Number.isNaN(x) ? "-" : Number(x).toFixed(d));
const mdTable = (head, rows) => ["| " + head.join(" | ") + " |", "| " + head.map(() => "---").join(" | ") + " |", ...rows.map((r) => "| " + r.join(" | ") + " |")].join("\n");

// ---- occurrences
const occ = jsonl(dir("occurrences.jsonl"));
const sortedSet = (id) => (valsets.get(id) || []).slice().sort();
const dieEvents = jsonl(dir("docker-events.jsonl")).filter((e) => e.action === "die" && !/^(bootstrap|collector|loadgen)/.test(e.name));
const listEvAll = events.filter((e) => e.type === "listChange");
const lastChangeBefore = (N) => { let best = null; for (const n of changeBlocks) { if (n <= N) best = n; else break; } return best; };
occ.sort((a, b) => String(a.matchTs).localeCompare(String(b.matchTs)));
const rows = occ.map((o, gi) => {
  const N = o.block, bN = byN.get(N), bPrev = byN.get(N - 1), bNext = byN.get(N + 1);
  const setN = bN ? sortedSet(bN.vs) : [], setPrev = bPrev ? sortedSet(bPrev.vs) : [];
  const nodeOp = opOf[o.node];
  const idxMiner = bN && setPrev.length ? setPrev.indexOf(bN.miner) : -1;
  const idxMinerNext = bNext ? setN.indexOf(bNext.miner) : -1;
  const idxNode = nodeOp ? setN.indexOf(nodeOp) : -1;
  const logMs = Date.parse(o.matchTs);
  const nextGap = bN && bNext ? bNext.ts - bN.ts : null;
  let maxGap = null; if (bN) { for (let k = 1; k <= 5; k++) { const b = byN.get(N + k); const p = byN.get(N + k - 1); if (b && p) maxGap = Math.max(maxGap ?? 0, b.ts - p.ts); } }
  return {
    idx: gi + 1, seq: o.seq, node: o.node, sinceChangeBlocks: (() => { const c = lastChangeBefore(N); return c === null ? null : N - c; })(),
    lastChangeOp: (() => { const c = lastChangeBefore(N); const e = listEvAll.find((x) => x.block === c); return c === null ? null : (e ? e.op : "bootstrap/other"); })(),
    nodesRestartedIn30min: [...new Set(dieEvents.filter((e) => { const t = Date.parse(e.t); return t <= logMs && logMs - t <= 1800000; }).map((e) => e.name))].join("+"), block: N, logTime: o.matchTs, phase: bN ? bN.phase : phaseOfMs(logMs), bootstrap: logMs < startMs, validators: bN ? bN.nv : null,
    listChangeAtN: bN && bPrev ? bN.vs !== bPrev.vs : null, listChangeAtNminus1: bPrev && byN.get(N - 2) ? bPrev.vs !== byN.get(N - 2).vs : null, nearChange3: nearChange(N, 3),
    txN: bN ? bN.tx : null, txPrev: bPrev ? bPrev.tx : null, txNext: bNext ? bNext.tx : null, roundN: bN ? bN.round : null, roundNext: bNext ? bNext.round : null,
    minerN: bN ? (nodeOfOp[bN.miner] || bN.miner) : null, proposerIdxN: idxMiner, minerNext: bNext ? (nodeOfOp[bNext.miner] || bNext.miner) : null, proposerIdxNext: idxMinerNext, nodeIdxInSet: idxNode,
    nodeIsProposerOfN: bN ? nodeOp === bN.miner : null, nodeIsProposerOfNext: bNext ? nodeOp === bNext.miner : null,
    logMinusBlockNtsMs: bN ? logMs - bN.ts * 1000 : null, gapToNextBlockS: nextGap, maxGapN_to_N5: maxGap, persistBlockTaskSameMs: o.persistBlockTaskWithin50ms, errorMsg: o.errorMsg, file: o.file,
  };
});
const csvCols = ["idx", "seq", "sinceChangeBlocks", "lastChangeOp", "nodesRestartedIn30min", "node", "block", "logTime", "phase", "bootstrap", "validators", "listChangeAtN", "listChangeAtNminus1", "nearChange3", "txN", "txPrev", "txNext", "roundN", "roundNext", "minerN", "proposerIdxN", "minerNext", "proposerIdxNext", "nodeIdxInSet", "nodeIsProposerOfN", "nodeIsProposerOfNext", "logMinusBlockNtsMs", "gapToNextBlockS", "maxGapN_to_N5", "persistBlockTaskSameMs", "file"];
fs.writeFileSync(dir("occurrences-analysis.csv"), [csvCols.join(","), ...rows.map((r) => csvCols.map((c) => (r[c] === null || r[c] === undefined ? "" : String(r[c]).replace(/,/g, ";"))).join(","))].join("\n") + "\n");

// ---- block-time statistics
const stat = (bs) => { const d = bs.map(delta).filter((x) => x !== null).sort((a, b) => a - b); return { n: bs.length, p50: pct(d, 50), p95: pct(d, 95), p99: pct(d, 99), max: d.length ? d[d.length - 1] : null, gt25: d.filter((x) => x > 2.5).length, ge5: d.filter((x) => x >= 5).length, ge10: d.filter((x) => x >= 10).length, ge30: d.filter((x) => x >= 30).length, rc: bs.filter((b) => b.round > 0).length, tx: bs.reduce((a, b) => a + b.tx, 0), txBlocks: bs.filter((b) => b.tx > 0).length }; };
const all = stat(wb);
const F1 = occ.length, F1win = rows.filter((r) => !r.bootstrap).length, F1boot = F1 - F1win;

// ---- per phase
const phaseNames = [...new Set(wb.map((b) => b.phase))];
const perPhase = phaseNames.map((p) => { const bs = wb.filter((b) => b.phase === p); const s = stat(bs); const o = rows.filter((r) => !r.bootstrap && r.phase === p).length; return { phase: p, ...s, f1: o, per1000: bs.length ? (o / bs.length) * 1000 : null, changes: winChangeBlocks.filter((n) => byN.get(n).phase === p).length }; });
fs.writeFileSync(dir("per-phase.csv"), ["phase,blocks,tx_blocks,txs,list_change_blocks,f1,f1_per_1000_blocks,bt_p50,bt_p95,bt_p99,bt_max,gaps_gt_2_5s,gaps_ge_10s,round_change_blocks", ...perPhase.map((p) => [p.phase, p.n, p.txBlocks, p.tx, p.changes, p.f1, f(p.per1000, 3), p.p50, p.p95, p.p99, p.max, p.gt25, p.ge10, p.rc].join(","))].join("\n") + "\n");

// ---- per hour (from the collector rows)
const hourly = jsonl(dir("hourly.jsonl"));
fs.writeFileSync(dir("per-hour.csv"), fs.existsSync(dir("hourly.csv")) ? fs.readFileSync(dir("hourly.csv"), "utf8") : "");

// ---- conditions: share of blocks vs share of occurrences
const cond = [
  ["block N contains a validator-list change", (b) => changeSet.has(b.n)],
  ["block N within +-3 blocks of a list change", (b) => nearChange(b.n, 3)],
  ["block N contains transactions", (b) => b.tx > 0],
  ["block N produced in a round > 0 (round change)", (b) => b.round > 0],
  ["phase has list changes (changes, changes-heavy, ...)", (b) => /change/i.test(b.phase)],
  ["phase is idle (no transactions, no changes)", (b) => b.phase === "idle"],
];
const occWin = rows.filter((r) => !r.bootstrap);
const condRows = cond.map(([name, fn]) => {
  const base = wb.filter(fn).length; const hit = occWin.filter((r) => { const b = byN.get(r.block); return b && fn(b); }).length;
  const share = wb.length ? base / wb.length : null;
  return [name, `${base} / ${wb.length} (${f(share * 100, 2)} %)`, `${hit} / ${occWin.length}${occWin.length ? " (" + f((hit / occWin.length) * 100, 1) + " %)" : ""}`, occWin.length && share !== null ? f(occWin.length * share, 2) : "-"];
});

// ---- per node
const stateJson = readJson(dir("collector", "state.json"), { nodes: {} });
const nodeNames = Object.keys(stateJson.nodes);
const perNode = nodeNames.map((n) => { const s = stateJson.nodes[n]; return [n, s.f1Total, rows.filter((r) => r.node === n && !r.bootstrap).length, s.errTotal, s.warnTotal, s.logLines]; });

// ---- other classes
const classes = {};
for (const n of nodeNames) for (const [c, v] of Object.entries(stateJson.nodes[n].classesTotal || {})) { if (c.includes("F-1 Failed")) continue; (classes[c] = classes[c] || {})[n] = v; }
const classRows = Object.entries(classes).map(([c, m]) => [c, Object.values(m).reduce((a, b) => a + b, 0), Object.entries(m).map(([n, v]) => `${n}:${v}`).join(" ")]).sort((a, b) => b[1] - a[1]).slice(0, 20);

// ---- gaps
const gapList = wb.map((b) => ({ b, d: delta(b) })).filter((x) => x.d !== null && x.d >= 5).sort((a, b) => b.d - a.d).slice(0, 25);
const hist = { "2 s": 0, "3 s": 0, "4-5 s": 0, "6-9 s": 0, ">=10 s": 0, "<2 s": 0 };
for (const b of wb) { const d = delta(b); if (d === null) continue; if (d < 2) hist["<2 s"]++; else if (d === 2) hist["2 s"]++; else if (d === 3) hist["3 s"]++; else if (d <= 5) hist["4-5 s"]++; else if (d <= 9) hist["6-9 s"]++; else hist[">=10 s"]++; }

// ---- docker events / restarts
const dEv = jsonl(dir("docker-events.jsonl")).filter((e) => ["die", "oom", "restart", "kill", "stop", "start"].includes(e.action));
const dieEv = dEv.filter((e) => (e.action === "die" || e.action === "oom") && !/^(bootstrap|loadgen|collector)/.test(e.name));
const lastRow = hourly[hourly.length - 1] || {};
const forkTotal = hourly.reduce((a, r) => a + (r.fork_mismatches || 0), 0);
const forkDetail = hourly.filter((r) => r.fork && r.fork.mismatches && r.fork.mismatches.length).map((r) => `row ${r.row}: ${JSON.stringify(r.fork.mismatches)}`);
const loadStats = readJson(dir("load", "stats.json"), {});
const opErrors = events.filter((e) => e.type === "opError" || e.type === "skip");
const listEv = events.filter((e) => e.type === "listChange");
const countBy = (arr, k) => arr.reduce((m, e) => ((m[e[k]] = (m[e[k]] || 0) + 1), m), {});
let besuVersion = "-";
try { const first = fs.readdirSync(dir("logs")).find((x) => x.endsWith(".log")); if (first) { const t = fs.readFileSync(dir("logs", first), "utf8").slice(0, 60000); const m = /besu\/v[\w.\-]+\/[\w\-]+\/[\w\-.]+/i.exec(t) || /Besu version (\S+)/i.exec(t); if (m) besuVersion = m[0]; } } catch (e) {}

// ---- write summary.md
const dur = (endMs - startMs) / 3600000;
const actualH = wb.length ? (wb[wb.length - 1].ts * 1000 - startMs) / 3600000 : 0;
const L = [];
L.push(`# Soak result summary (generated by collect-results.sh at ${iso()})`, "");
L.push("## Run", "");
L.push(mdTable(["Item", "Value"], [
  ["Besu image", `${run.image || "-"} (${besuVersion})`], ["Validators (net)", `${run.validators || "-"} (${NET}), extra nodes x1 (swap alternate) and x2 (entrant)`], ["Planned duration", `${run.hours || f(dur, 2)} h`],
  ["Soak window", win ? `${iso(win.startMs)} .. ${iso(win.endMs)}` : "-"], ["Actually covered by blocks", `${f(actualH, 2)} h, ${wb.length} blocks in the window (${blocks.length - wb.length} more during bootstrap/after)`],
  ["Phase plan", `\`${run.phasePlan || "-"}\``], ["getValidators poller", run.pollHz === 0 ? "off" : `${run.pollHz ?? "-"} Hz`], ["Interval of the rows", `${run.intervalMinutes || "-"} min (${hourly.length} rows)`],
  ["Kit", run.kitVersion || "soak-kit-v25"],
]), "");
L.push("## Answer in numbers", "");
L.push(`- **F-1 occurrences** (\`Failed validator smart contract call\`): **${F1}** in total, **${F1win}** inside the soak window and ${F1boot} during the bootstrap (validator list growing from 1 to ${run.validators || "N"}).`);
L.push(`- Rate inside the window: **${f(wb.length ? (F1win / wb.length) * 1000 : null, 3)} per 1000 blocks**` + (F1win > 0 ? `, i.e. one every ${f(actualH / F1win, 2)} h on average across all nodes` : "") + `. Round 1 (7 validators, ~1,100 blocks, bootstrap included): 8 occurrences = 7.3 per 1000 blocks.`);
L.push(`- Block time over the window: p50 ${all.p50} s, p95 ${all.p95} s, p99 ${all.p99} s, **max ${all.max} s**; gaps > 2.5 s: ${all.gt25}; gaps >= 5 s: ${all.ge5}; gaps >= 10 s: ${all.ge10}; gaps >= 30 s: ${all.ge30}; blocks produced in a round > 0: ${all.rc}.`);
L.push(`- Forks: ${forkTotal === 0 ? "**none detected** (same hash at the same heights on every node, every row)" : "**" + forkTotal + " MISMATCHES** (see below)"}. Container deaths/OOM recorded by docker events: ${dieEv.length}; restarts at the last row: ${lastRow.restarts_total ?? "-"}; OOM flags: ${lastRow.oom_total ?? "-"}.`);
L.push(`- Validator-list changes seen in the blocks (window): ${winChangeBlocks.length}; load generator reports: ${JSON.stringify(countBy(listEv, "op"))}; skipped/failed: ${loadStats.listChanges ? loadStats.listChanges.skipped + "/" + loadStats.listChanges.failed : "-"}.`);
L.push(`- Transactions in blocks: ${all.tx} in ${all.txBlocks} blocks; load generator sent ${loadStats.transfers ? loadStats.transfers.sent : "-"} transfers (errors ${loadStats.transfers ? loadStats.transfers.errors : "-"}); poller ok/err ${loadStats.poll ? loadStats.poll.ok + "/" + loadStats.poll.err : "-"}.`, "");

L.push("## F-1 per node", "", mdTable(["Node", "F-1 (all time)", "F-1 inside window", "ERROR entries", "WARN entries", "Log lines"], perNode.map((r) => r.map(String))), "");
L.push("## F-1 per phase (conditions)", "");
L.push("Phases come from the load generator's `phase` events (`load/events.jsonl`); blocks are assigned by block timestamp.", "");
L.push(mdTable(["Phase", "Blocks", "Tx blocks", "List-change blocks", "F-1", "F-1 / 1000 blocks", "bt p50", "bt p95", "bt max", "gaps>2.5s", "round>0 blocks"], perPhase.map((p) => [p.phase, p.n, p.txBlocks, p.changes, p.f1, f(p.per1000, 3), p.p50, p.p95, p.max, p.gt25, p.rc].map(String))), "");
L.push("## Where in the chain do the occurrences fall?", "");
L.push("`Share of blocks` is the base rate over all window blocks; `share of occurrences` is how many occurrences hit such a block N (N = the block named in the log message). If an occurrence share is far above the base rate, the condition raises the probability. `Expected` = occurrences x base share, to compare with the hits. Small counts prove nothing.", "");
L.push(mdTable(["Condition", "Share of blocks", "Occurrences in such a block", "Expected at random"], condRows), "");
L.push("## Block-time distribution (window)", "", mdTable(["Gap to previous block", "Blocks"], Object.entries(hist).map(([k, v]) => [k, String(v)])), "");
if (gapList.length) L.push("Longest gaps (>= 5 s):", "", mdTable(["Block", "Gap s", "Phase", "Round", "UTC"], gapList.map((x) => [x.b.n, x.d, x.b.phase, x.b.round, iso(x.b.ts * 1000)].map(String))), "");
else L.push("No gap >= 5 s in the window.", "");

L.push("## Per row (hourly unless --interval-minutes was set)", "");
L.push(mdTable(["#", "UTC", "Phase end", "Blocks", "Val.", "Chg", "p50", "p95", "p99", "max", ">2.5s", "round>0", "F-1", "other ERR", "WARN", "Restarts", "Fork", "Mem MB", "Vol MB"],
  hourly.map((r) => [r.row + (r.partial ? "p" : ""), (r.ts_utc || "").slice(0, 16), r.phase || "-", r.blocks, `${r.validators_min}-${r.validators_max}`, r.list_changes, r.bt_p50, r.bt_p95, r.bt_p99, r.bt_max, r.gaps_gt_2_5s, r.round_change_blocks, r.f1_interval, r.err_other_interval, r.warn_interval, r.restarts_total, r.fork_mismatches, r.mem_mb_max, r.volumes_mb].map((x) => (x === null || x === undefined ? "-" : String(x))))), "");
L.push("F-1 per node per row:", "");
const f1rows = hourly.filter((r) => r.f1PerNode && Object.values(r.f1PerNode).some((v) => v > 0));
L.push(f1rows.length ? f1rows.map((r) => `- row ${r.row} (${(r.intervalEndUtc || "").slice(0, 16)}): ${Object.entries(r.f1PerNode).filter(([, v]) => v > 0).map(([n, v]) => n + "=" + v).join(", ")}`).join("\n") : "- none", "");

L.push("## Each occurrence (correlation)", "");
if (!rows.length) L.push("No occurrence was recorded.", "");
else {
  L.push("`chg@N` = block N is the first block of a new validator set (the block containing the Registry change); `near±3` = a change within 3 blocks; `idxN` = position of the miner of N in the sorted validator set at N-1; `node idx` = position of the node that logged the error in the set at N; `next gap` = timestamp(N+1) - timestamp(N); `log-N ts` = log time minus the timestamp of block N in ms; `PBT` = a PersistBlockTask import line within 50 ms of the ERROR line.", "");
  L.push(mdTable(["#", "Node", "Block N", "Log UTC", "Phase", "Val.", "chg@N", "near±3", "blocks since last change (op)", "node restarted <30 min", "tx N-1/N/N+1", "round N/N+1", "miner N (idx)", "miner N+1 (idx)", "node idx", "node=prop N / N+1", "next gap s", "max gap N..N+5", "log-N ts ms", "PBT"],
    rows.map((r) => [r.idx, r.node, r.block, (r.logTime || "").slice(11, 23), r.bootstrap ? "bootstrap" : r.phase, r.validators, r.listChangeAtN, r.nearChange3, r.sinceChangeBlocks === null ? "-" : `${r.sinceChangeBlocks} (${r.lastChangeOp})`, r.nodesRestartedIn30min || "-", `${r.txPrev}/${r.txN}/${r.txNext}`, `${r.roundN}/${r.roundNext}`, `${r.minerN} (${r.proposerIdxN})`, `${r.minerNext} (${r.proposerIdxNext})`, r.nodeIdxInSet, `${r.nodeIsProposerOfN}/${r.nodeIsProposerOfNext}`, r.gapToNextBlockS, r.maxGapN_to_N5, r.logMinusBlockNtsMs, r.persistBlockTaskSameMs].map((x) => (x === null || x === undefined ? "-" : String(x))))), "");
  const withNext = rows.filter((r) => r.gapToNextBlockS !== null);
  L.push(`Time to the next block after an occurrence: ${withNext.length ? `min ${Math.min(...withNext.map((r) => r.gapToNextBlockS))} s, max ${Math.max(...withNext.map((r) => r.gapToNextBlockS))} s over ${withNext.length} occurrences (normal block time ${all.p50} s)` : "-"}. Occurrences followed by a gap > 2.5 s: ${withNext.filter((r) => r.gapToNextBlockS > 2.5).length}. Occurrences with a PersistBlockTask line in the same ms: ${rows.filter((r) => r.persistBlockTaskSameMs).length} of ${rows.length}.`, "");
  L.push("Raw context of every occurrence (15 lines before, 45 after): `occurrences/`; machine-readable: `occurrences-analysis.csv`.", "");
}
L.push("## Other ERROR / WARN classes (top 20, all nodes, whole run)", "", classRows.length ? mdTable(["Class (level|logger|normalised message)", "Count", "Per node"], classRows.map((r) => r.map(String))) : "None recorded.", "");
L.push("## Containers", "");
L.push(dieEv.length ? mdTable(["UTC", "Node", "Event", "Exit code"], dieEv.slice(0, 50).map((e) => [e.t, e.name, e.action, e.exitCode ?? "-"].map(String))) : "No container die/oom event was recorded.", "");
if (forkDetail.length) L.push("## FORK MISMATCHES", "", ...forkDetail.map((x) => "- " + x), "");
L.push("## Load generator", "", "```json", JSON.stringify({ stats: loadStats, events: countBy(events, "type"), listChangesByOp: countBy(listEv, "op") }, null, 1), "```", "");
if (opErrors.length) L.push("Operation errors / skips:", "", ...opErrors.slice(0, 40).map((e) => `- ${e.t} ${e.type} ${e.op || ""} ${e.reason || e.error || ""}`), "");
L.push("## Notes", "", "- Block time is computed from block header timestamps (integer seconds); with a 2 s block period a gap of 3 s or more means a delayed block, >= 12 s typically means a QBFT round change (`requesttimeoutseconds` = 10).", "- An occurrence is counted once per log entry (the message appears twice in the stack trace).", "- This is measurement on a throw-away test net, not a statement about production.", "");
fs.writeFileSync(dir("summary.md"), L.join("\n"));
console.log(`summary.md written: ${F1} occurrences (${F1win} in window), ${wb.length} window blocks, ${hourly.length} rows`);
