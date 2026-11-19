// COLLECTOR (runs in a container with the Docker socket mounted; talks to the Docker Engine API and to the nodes' JSON-RPC).
//
//   * follows the logs of every node container, keeps them (size-rotated + gzipped), counts the F-1 line
//     "Failed validator smart contract call" and saves 15 lines before + 45 lines after each occurrence into occurrences/
//   * records every block (number, timestamp, hash, miner, tx count, gas, QBFT round from extraData, validator-set id) into blocks.csv
//   * writes one ROW per interval (default 60 min, --interval-minutes / INTERVAL_MIN for tests) into hourly.csv + hourly.jsonl
//   * docker events (die, oom, restart...) into docker-events.jsonl, container state / restarts / OOM, peers, docker stats
//   * writes status.txt (one screen) every 15 s
// Resumable: state in collector/state.json; blocks.csv is reloaded. Stops when <RUN_DIR>/STOP exists.
"use strict";
const zlib = require("zlib");
const { pipeline } = require("stream");
const { ethers } = require("ethers");
const { rpc, rpcBatch, nodeUrl, sleep, log, readJson, writeJsonAtomic, appendJsonl, ensureDir, path, fs, RUN_DIR, PREFIX, iso, dockerReq, stripAnsi, pct, KIT } = require("./common");

const NET = process.env.NET || "n7";
const net = JSON.parse(fs.readFileSync(path.join(KIT, "nets", NET, "soak-net.json"), "utf8"));
const NODES = [...net.validatorNodes, ...net.extraNodes];
const INTERVAL_MS = Number(process.env.INTERVAL_MIN || 60) * 60000;
const ROTATE_BYTES = Number(process.env.ROTATE_MB || 100) * 1048576;
const KEEP_ROTATED = Number(process.env.KEEP_ROTATED || 12);
const CTX_BEFORE = 15, CTX_AFTER = 45;
const F1_RE = /Failed validator smart contract call/;
const dir = (...p) => path.join(RUN_DIR, ...p);
["logs", "occurrences", "collector", "meta", "load"].forEach((d) => ensureDir(dir(d)));
const stopFile = dir("STOP");
let stopping = false;
const clog = (...a) => { const l = `${iso()} ${a.join(" ")}`; console.log(l); try { fs.appendFileSync(dir("collector", "collector.log"), l + "\n"); } catch (e) {} };
let collectorErrors = 0;
const cerr = (where, e) => { collectorErrors++; clog("ERROR", where, String((e && e.message) || e).slice(0, 200)); };

// ------------------------------------------------------------------ state
const state = readJson(dir("collector", "state.json"), { lastBlock: 0, rowsDone: 0, nodes: {}, vsetId: 0, lastVsetKey: "", rowStartBlockIdx: 0 });
for (const n of NODES) state.nodes[n] = state.nodes[n] || { lastLogTs: null, f1Total: 0, f1Interval: 0, errTotal: 0, warnTotal: 0, errInterval: 0, warnInterval: 0, classesTotal: {}, classesInterval: {}, occSeq: 0, logLines: 0, restartsSeen: 0 };
const saveState = () => { try { writeJsonAtomic(dir("collector", "state.json"), state); } catch (e) { cerr("saveState", e); } };

// ------------------------------------------------------------------ log writer with rotation
class LogWriter {
  constructor(node) { this.node = node; this.p = dir("logs", node + ".log"); this.fd = fs.openSync(this.p, "a"); this.size = fs.fstatSync(this.fd).size; }
  write(line) { const b = Buffer.from(line + "\n"); fs.writeSync(this.fd, b); this.size += b.length; if (this.size > ROTATE_BYTES) this.rotate(); }
  rotate() {
    try {
      fs.closeSync(this.fd);
      const stamp = new Date().toISOString().replace(/[:.]/g, "-");
      const dst = dir("logs", `${this.node}.${stamp}.log`);
      fs.renameSync(this.p, dst);
      this.fd = fs.openSync(this.p, "a"); this.size = 0;
      pipeline(fs.createReadStream(dst), zlib.createGzip(), fs.createWriteStream(dst + ".gz"), (err) => {
        if (err) return cerr("gzip", err);
        fs.unlinkSync(dst);
        const olds = fs.readdirSync(dir("logs")).filter((f) => f.startsWith(this.node + ".") && f.endsWith(".log.gz")).sort();
        while (olds.length > KEEP_ROTATED) fs.unlinkSync(dir("logs", olds.shift()));
      });
    } catch (e) { cerr("rotate", e); }
  }
  close() { try { fs.closeSync(this.fd); } catch (e) {} }
}

// ------------------------------------------------------------------ log parsing
const HDR = /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3})\+\d{4} \| (.+?) \| (\w+)\s*\| (.+?) \| (.*)$/;
const norm = (s) => s.replace(/0x[0-9a-fA-F]+/g, "0x..").replace(/@[0-9a-f]{5,}/g, "@..").replace(/\d+(\.\d+)?/g, "#").replace(/\s+/g, " ").slice(0, 140);
const logTsMs = (s) => Date.parse(s.replace(" ", "T") + "Z");
class NodeParser {
  constructor(node) { this.node = node; this.st = state.nodes[node]; this.writer = new LogWriter(node); this.cur = null; this.ring = []; this.captures = []; }
  finalize() { // close the current entry: classify ERROR/WARN
    const c = this.cur; if (!c) return;
    if (c.level === "ERROR" || c.level === "WARN") {
      const key = c.hadF1 ? `${c.level}|F-1 Failed validator smart contract call` : `${c.level}|${c.logger}|${norm(c.msg)}${c.cause ? " <= " + norm(c.cause) : ""}`;
      const add = (m) => { if (Object.keys(m).length < 300 || m[key] !== undefined) m[key] = (m[key] || 0) + 1; };
      add(this.st.classesTotal); add(this.st.classesInterval);
      if (c.level === "ERROR") { this.st.errTotal++; this.st.errInterval++; } else { this.st.warnTotal++; this.st.warnInterval++; }
    }
    this.cur = null;
  }
  line(ts, text) {
    text = stripAnsi(text).replace(/\r$/, "");
    this.st.lastLogTs = ts; this.st.logLines++;
    this.writer.write(`${ts} ${text}`);
    const m = HDR.exec(text);
    if (m) { this.finalize(); this.cur = { ts: m[1], thread: m[2], level: m[3], logger: m[4], msg: m[5], hadF1: false, cause: null, dockerTs: ts }; }
    else if (this.cur && !this.cur.cause) { const c = /^Caused by: (.*)$/.exec(text) || /^([\w.$]+(?:Exception|Error)\b.*)$/.exec(text); if (c) this.cur.cause = c[1]; }
    // feed open captures
    for (const cap of this.captures) { cap.after.push(`${ts} ${text}`); }
    this.captures = this.captures.filter((cap) => { if (cap.after.length >= CTX_AFTER) { this.writeCapture(cap); return false; } return true; });
    // F-1 detection (once per log entry)
    if (F1_RE.test(text) && !(this.cur && this.cur.hadF1)) {
      if (this.cur) this.cur.hadF1 = true;
      this.st.f1Total++; this.st.f1Interval++; this.st.occSeq++;
      const bm = /at block (\d+)/.exec(text);
      const hdr = this.cur || { ts: null, msg: "", dockerTs: ts };
      this.captures.push({ seq: this.st.occSeq, node: this.node, block: bm ? Number(bm[1]) : null, matchTs: ts, errorTs: hdr.ts, errorMsg: (hdr.msg || "").slice(0, 300), before: this.ring.slice(-CTX_BEFORE), match: `${ts} ${text}`, after: [] });
    }
    this.ring.push(`${ts} ${text}`); if (this.ring.length > CTX_BEFORE + 5) this.ring.shift();
  }
  writeCapture(cap) {
    try {
      const stamp = cap.matchTs.replace(/[:.]/g, "-");
      const file = `${cap.node}__${String(cap.seq).padStart(4, "0")}__block${cap.block}__${stamp}.txt`;
      const lines = [`# F-1 occurrence #${cap.seq} on ${cap.node}: block ${cap.block}, first matching line at ${cap.matchTs}`, `# ${cap.before.length} lines before, the matching line, ${cap.after.length} lines after (ANSI colours stripped; docker timestamp prefix)`, "# ---- before", ...cap.before, "# ---- match", cap.match, "# ---- after", ...cap.after];
      fs.writeFileSync(dir("occurrences", file), lines.join("\n") + "\n");
      const samePersist = cap.before.concat(cap.after).some((l) => /PersistBlockTask/.test(l) && cap.errorTs && Math.abs(logTsMs((HDR.exec(l.slice(l.indexOf(" ") + 1)) || [])[1] || "1970-01-01 00:00:00.000") - logTsMs(cap.errorTs)) <= 50);
      appendJsonl(dir("occurrences.jsonl"), { seq: cap.seq, node: cap.node, block: cap.block, matchTs: cap.matchTs, errorTs: cap.errorTs, errorMsg: cap.errorMsg, persistBlockTaskWithin50ms: !!samePersist, file });
    } catch (e) { cerr("writeCapture", e); }
  }
  flushCaptures() { for (const cap of this.captures) this.writeCapture(cap); this.captures = []; this.finalize(); }
}
const parsers = Object.fromEntries(NODES.map((n) => [n, new NodeParser(n)]));

async function followLogs(node) {
  const P = parsers[node];
  while (!stopping) {
    try {
      const last = P.st.lastLogTs;
      const since = last ? Math.max(0, Math.floor(Date.parse(last) / 1000) - 1) : 0;
      const res = await dockerReq(`/containers/${PREFIX}${node}/logs?follow=1&stdout=1&stderr=1&timestamps=1&since=${since}`, { raw: true, timeoutMs: 0 });
      if (res.statusCode !== 200) { res.resume(); await sleep(5000); continue; }
      let buf = Buffer.alloc(0); const partial = { 1: "", 2: "" };
      await new Promise((resolve) => {
        res.on("data", (chunk) => {
          buf = Buffer.concat([buf, chunk]);
          while (buf.length >= 8) {
            const size = buf.readUInt32BE(4);
            if (buf.length < 8 + size) break;
            const stream = buf[0] === 2 ? 2 : 1;
            const text = partial[stream] + buf.slice(8, 8 + size).toString("utf8");
            buf = buf.slice(8 + size);
            const lines = text.split("\n"); partial[stream] = lines.pop();
            for (const l of lines) {
              const sp = l.indexOf(" ");
              const ts = l.slice(0, sp), body = l.slice(sp + 1);
              if (P.st.lastLogTs && ts <= P.st.lastLogTs) continue; // already seen (reconnect overlap)
              P.line(ts, body);
            }
          }
        });
        res.on("end", resolve); res.on("error", resolve); res.on("close", resolve);
      });
    } catch (e) { if (!stopping) cerr("followLogs " + node, e); }
    if (!stopping) await sleep(2000);
  }
}

// ------------------------------------------------------------------ docker events
async function followEvents() {
  while (!stopping) {
    try {
      const filters = encodeURIComponent(JSON.stringify({ label: ["sur25s.kit=1"], type: ["container"] }));
      const res = await dockerReq(`/events?filters=${filters}&since=${Math.floor(Date.now() / 1000) - 1}`, { raw: true, timeoutMs: 0 });
      let buf = "";
      await new Promise((resolve) => {
        res.on("data", (c) => { buf += c.toString("utf8"); let i; while ((i = buf.indexOf("\n")) >= 0) { const l = buf.slice(0, i); buf = buf.slice(i + 1); try { const e = JSON.parse(l); if (/^exec_/.test(e.Action || "")) continue; appendJsonl(dir("docker-events.jsonl"), { t: iso(e.timeNano ? Math.floor(e.timeNano / 1e6) : Date.now()), action: e.Action, name: (e.Actor.Attributes.name || "").replace(PREFIX, ""), exitCode: e.Actor.Attributes.exitCode, signal: e.Actor.Attributes.signal }); } catch (x) {} } });
        res.on("end", resolve); res.on("error", resolve); res.on("close", resolve);
      });
    } catch (e) { if (!stopping) cerr("followEvents", e); }
    if (!stopping) await sleep(3000);
  }
}

// ------------------------------------------------------------------ block recorder
const blocks = []; // {n, ts, seen, hash, miner, tx, gas, round, nv, vs}
const csvPath = dir("blocks.csv");
const CSV_HEAD = "number,timestamp,seen_ms,hash,miner,tx,gas_used,round,validators,vset_id\n";
function loadBlocks() {
  if (!fs.existsSync(csvPath)) { fs.writeFileSync(csvPath, CSV_HEAD); return; }
  const lines = fs.readFileSync(csvPath, "utf8").split("\n").slice(1);
  for (const l of lines) { if (!l) continue; const f = l.split(","); blocks.push({ n: +f[0], ts: +f[1], seen: +f[2], hash: f[3], miner: f[4], tx: +f[5], gas: +f[6], round: +f[7], nv: +f[8], vs: +f[9] }); }
  if (blocks.length) state.lastBlock = Math.max(state.lastBlock, blocks[blocks.length - 1].n);
  state.lastBlock = blocks.length ? blocks[blocks.length - 1].n : 0; // csv is the truth
}
let recorderNode = NODES[0];
async function pickRecorder() {
  for (const n of [recorderNode, ...net.validatorNodes]) { try { await rpc(nodeUrl(n), "eth_blockNumber", [], 4000); recorderNode = n; return n; } catch (e) {} }
  return null;
}
async function recordBlocks() {
  const n = await pickRecorder(); if (!n) return;
  const url = nodeUrl(n);
  const head = Number(BigInt(await rpc(url, "eth_blockNumber")));
  let from = state.lastBlock + 1;
  while (from <= head && !stopping) {
    const to = Math.min(head, from + 99);
    const calls = [];
    for (let b = from; b <= to; b++) { const q = ethers.toQuantity(b); calls.push(["eth_getBlockByNumber", [q, false]], ["qbft_getValidatorsByBlockNumber", [q]]);
    }
    const res = await rpcBatch(url, calls);
    const seen = Date.now(); let out = "";
    for (let i = 0; i <= to - from; i++) {
      const b = res[2 * i], v = res[2 * i + 1];
      if (!b || b.error || !v || v.error) { throw new Error(`block ${from + i}: ${JSON.stringify((b && b.error) || (v && v.error) || "null")}`); }
      let round = 0; try { const d = ethers.decodeRlp(b.extraData); round = Number(BigInt(d[3] && d[3] !== "0x" ? d[3] : "0x0")); } catch (e) {}
      const set = v.map((a) => a.toLowerCase()).sort(); const key = set.join(",");
      if (key !== state.lastVsetKey) { state.vsetId++; state.lastVsetKey = key; appendJsonl(dir("valsets.jsonl"), { block: from + i, id: state.vsetId, validators: set }); }
      const rec = { n: from + i, ts: Number(BigInt(b.timestamp)), seen, hash: b.hash, miner: ethers.getAddress(b.miner), tx: b.transactions.length, gas: Number(BigInt(b.gasUsed)), round, nv: set.length, vs: state.vsetId };
      blocks.push(rec);
      out += `${rec.n},${rec.ts},${rec.seen},${rec.hash},${rec.miner},${rec.tx},${rec.gas},${rec.round},${rec.nv},${rec.vs}\n`;
    }
    fs.appendFileSync(csvPath, out);
    state.lastBlock = to; from = to + 1;
  }
}

// ------------------------------------------------------------------ periodic probes
async function containerInfo(node) {
  try {
    const j = await dockerReq(`/containers/${PREFIX}${node}/json`);
    return { status: j.State.Status, running: j.State.Running, exitCode: j.State.ExitCode, oom: j.State.OOMKilled, restarts: j.RestartCount, startedAt: j.State.StartedAt, finishedAt: j.State.FinishedAt, error: j.State.Error || "" };
  } catch (e) { return { status: "missing", error: String(e.message).slice(0, 80) }; }
}
async function containerStats(node) {
  try {
    const s = await dockerReq(`/containers/${PREFIX}${node}/stats?stream=false`, { timeoutMs: 15000 });
    const cpuD = s.cpu_stats.cpu_usage.total_usage - s.precpu_stats.cpu_usage.total_usage, sysD = s.cpu_stats.system_cpu_usage - s.precpu_stats.system_cpu_usage;
    const cpu = sysD > 0 ? (cpuD / sysD) * (s.cpu_stats.online_cpus || 1) * 100 : null;
    const ms = s.memory_stats || {}; const cache = (ms.stats && (ms.stats.inactive_file ?? ms.stats.cache)) || 0;
    return { memMB: ms.usage ? Math.round((ms.usage - cache) / 1048576) : null, memLimitMB: ms.limit ? Math.round(ms.limit / 1048576) : null, cpuPct: cpu === null ? null : Math.round(cpu * 10) / 10, pids: s.pids_stats && s.pids_stats.current };
  } catch (e) { return null; }
}
async function nodeProbe(node) {
  const url = nodeUrl(node);
  try {
    const [h, p] = await Promise.all([rpc(url, "eth_blockNumber", [], 5000), rpc(url, "net_peerCount", [], 5000)]);
    return { head: Number(BigInt(h)), peers: Number(BigInt(p)) };
  } catch (e) { return { head: null, peers: null }; }
}
async function forkCheck(sampleFrom) {
  const probes = await Promise.all(NODES.map(async (n) => [n, await nodeProbe(n)]));
  const heads = probes.filter(([, p]) => p.head !== null).map(([, p]) => p.head);
  const unreachable = probes.filter(([, p]) => p.head === null).map(([n]) => n);
  if (!heads.length) return { checked: [], mismatches: [], unreachable, note: "no node reachable" };
  const common = Math.min(...heads) - 3;
  const hs = new Set([common, Math.max(1, common - 1)]);
  const lo = Math.max(1, sampleFrom || 1); // a few random heights since the previous check
  for (let i = 0; i < 6 && common > lo; i++) hs.add(lo + Math.floor(Math.random() * (common - lo)));
  const heights = [...hs].filter((h) => h >= 0).sort((a, b) => a - b);
  const byNode = {};
  await Promise.all(NODES.filter((n) => !unreachable.includes(n)).map(async (n) => {
    try { const r = await rpcBatch(nodeUrl(n), heights.map((h) => ["eth_getBlockByNumber", [ethers.toQuantity(h), false]])); byNode[n] = r.map((b) => (b && b.hash) || null); } catch (e) { byNode[n] = null; }
  }));
  const mismatches = [];
  heights.forEach((h, i) => {
    const hashes = {}; for (const [n, arr] of Object.entries(byNode)) if (arr && arr[i]) (hashes[arr[i]] = hashes[arr[i]] || []).push(n);
    if (Object.keys(hashes).length > 1) mismatches.push({ height: h, hashes });
  });
  return { checked: heights, nodesCompared: Object.keys(byNode).length, mismatches, unreachable, heads: Object.fromEntries(probes.map(([n, p]) => [n, p.head])) };
}
async function volumeSizes() {
  try {
    const df = await dockerReq("/system/df?type=volume", { timeoutMs: 60000 });
    const vols = (df.Volumes || []).filter((v) => v.Name.startsWith(PREFIX));
    const out = {}; let tot = 0;
    for (const v of vols) { const mb = v.UsageData && v.UsageData.Size >= 0 ? Math.round(v.UsageData.Size / 1048576) : null; out[v.Name.replace(PREFIX, "").replace(/-data$/, "")] = mb; tot += mb || 0; }
    return { totalMB: tot, perNode: out };
  } catch (e) { return null; }
}
function dirSizeMB(d) { let t = 0; const walk = (p) => { for (const e of fs.readdirSync(p, { withFileTypes: true })) { const f = path.join(p, e.name); try { if (e.isDirectory()) walk(f); else t += fs.statSync(f).size; } catch (x) {} } }; try { walk(d); } catch (e) {} return Math.round(t / 1048576); }

// ------------------------------------------------------------------ rows
const ROWS_CSV = dir("hourly.csv");
const COLS = ["row", "ts_utc", "elapsed_h", "partial", "phase", "head", "blocks", "txs_in_blocks", "blocks_with_tx", "validators_min", "validators_max", "list_changes", "bt_p50", "bt_p95", "bt_p99", "bt_max", "gaps_gt_2_5s", "gaps_ge_10s", "round_change_blocks", "f1_interval", "f1_total", "err_other_interval", "warn_interval", "restarts_total", "oom_total", "containers_not_running", "peers_min", "peers_max", "fork_mismatches", "unreachable_nodes", "mem_mb_max", "cpu_pct_max", "volumes_mb", "run_dir_mb", "host_free_gb", "load_tx_sent", "load_tx_errors", "load_changes", "poll_err", "collector_errors"];
if (!fs.existsSync(ROWS_CSV)) fs.writeFileSync(ROWS_CSV, COLS.join(",") + "\n");
let lastForkCheckBlock = state.lastForkBlock || 0;
let latestProbe = {}; // node -> {head, peers, info}

async function makeRow(k, t0, t1, partial) {
  const inWin = []; // blocks with timestamp in [t0, t1)
  for (let i = Math.max(0, state.rowStartBlockIdx - 5); i < blocks.length; i++) { const b = blocks[i]; if (b.ts * 1000 >= t0 && b.ts * 1000 < t1) inWin.push(i); else if (b.ts * 1000 >= t1) break; }
  if (inWin.length) state.rowStartBlockIdx = inWin[0];
  const deltas = inWin.filter((i) => i > 0).map((i) => blocks[i].ts - blocks[i - 1].ts);
  const sorted = deltas.slice().sort((a, b) => a - b);
  const bl = inWin.map((i) => blocks[i]);
  const vsIds = new Set(bl.map((b) => b.vs));
  let listChanges = 0; for (let j = 0; j < inWin.length; j++) { const i = inWin[j]; if (i > 0 && blocks[i].vs !== blocks[i - 1].vs) listChanges++; }
  const infos = {}, stats = {}, probes = {};
  await Promise.all(NODES.map(async (n) => { infos[n] = await containerInfo(n); stats[n] = await containerStats(n); probes[n] = await nodeProbe(n); }));
  const fork = await forkCheck(lastForkCheckBlock);
  if (fork.heads) { const hs = Object.values(fork.heads).filter((x) => x !== null); if (hs.length) { lastForkCheckBlock = Math.min(...hs) - 3; state.lastForkBlock = lastForkCheckBlock; } }
  const vol = await volumeSizes();
  const load = readJson(dir("load", "stats.json"), {});
  const f1Interval = {}, otherErr = {}, warn = {}, topClasses = {};
  let f1Int = 0, errInt = 0, warnInt = 0;
  for (const n of NODES) {
    const s = state.nodes[n];
    f1Interval[n] = s.f1Interval; f1Int += s.f1Interval;
    const e = Object.entries(s.classesInterval).filter(([c]) => c.startsWith("ERROR|") && !c.includes("F-1 Failed")).reduce((a, [, v]) => a + v, 0); otherErr[n] = e; errInt += e;
    warn[n] = s.warnInterval; warnInt += s.warnInterval;
    for (const [c, v] of Object.entries(s.classesInterval)) if (!c.includes("F-1 Failed")) topClasses[c] = (topClasses[c] || 0) + v;
  }
  const top = Object.entries(topClasses).sort((a, b) => b[1] - a[1]).slice(0, 8);
  const restarts = {}; let restartsTotal = 0, oomTotal = 0, notRunning = 0;
  for (const n of NODES) { const i = infos[n]; restarts[n] = i.restarts ?? null; restartsTotal += i.restarts || 0; if (i.oom) oomTotal++; if (!i.running) notRunning++; }
  const mems = Object.values(stats).filter(Boolean).map((s) => s.memMB || 0), cpus = Object.values(stats).filter(Boolean).map((s) => s.cpuPct || 0);
  const peers = Object.values(probes).filter((p) => p.peers !== null).map((p) => p.peers);
  let free = null; try { const sf = fs.statfsSync(RUN_DIR); free = Math.round((sf.bavail * sf.bsize) / 1073741824 * 10) / 10; } catch (e) {}
  const row = {
    row: k, ts_utc: iso(Math.min(t1, Date.now())), elapsed_h: Math.round(((Math.min(t1, Date.now()) - win.startMs) / 3600000) * 1000) / 1000, partial: !!partial, phase: load.phase || null,
    head: blocks.length ? blocks[blocks.length - 1].n : null, blocks: bl.length, txs_in_blocks: bl.reduce((a, b) => a + b.tx, 0), blocks_with_tx: bl.filter((b) => b.tx > 0).length,
    validators_min: bl.length ? Math.min(...bl.map((b) => b.nv)) : null, validators_max: bl.length ? Math.max(...bl.map((b) => b.nv)) : null, list_changes: listChanges,
    bt_p50: pct(sorted, 50), bt_p95: pct(sorted, 95), bt_p99: pct(sorted, 99), bt_max: sorted.length ? sorted[sorted.length - 1] : null,
    gaps_gt_2_5s: deltas.filter((d) => d > 2.5).length, gaps_ge_10s: deltas.filter((d) => d >= 10).length, round_change_blocks: bl.filter((b) => b.round > 0).length,
    f1_interval: f1Int, f1_total: NODES.reduce((a, n) => a + state.nodes[n].f1Total, 0), err_other_interval: errInt, warn_interval: warnInt,
    restarts_total: restartsTotal, oom_total: oomTotal, containers_not_running: notRunning, peers_min: peers.length ? Math.min(...peers) : null, peers_max: peers.length ? Math.max(...peers) : null,
    fork_mismatches: fork.mismatches.length, unreachable_nodes: fork.unreachable.join("|"), mem_mb_max: mems.length ? Math.max(...mems) : null, cpu_pct_max: cpus.length ? Math.max(...cpus) : null,
    volumes_mb: vol ? vol.totalMB : null, run_dir_mb: dirSizeMB(RUN_DIR), host_free_gb: free,
    load_tx_sent: load.transfers ? load.transfers.sent : null, load_tx_errors: load.transfers ? load.transfers.errors : null,
    load_changes: load.listChanges ? load.listChanges.swap + load.listChanges.selfSuspend + load.listChanges.resume + load.listChanges.activate : null, poll_err: load.poll ? load.poll.err : null, collector_errors: collectorErrors,
  };
  const detail = {
    ...row, intervalStartUtc: iso(t0), intervalEndUtc: iso(t1), f1PerNode: f1Interval, f1TotalPerNode: Object.fromEntries(NODES.map((n) => [n, state.nodes[n].f1Total])), otherErrorsPerNode: otherErr, warnPerNode: warn,
    topClasses: top, restartsPerNode: restarts, containers: infos, docker: stats, peersPerNode: Object.fromEntries(NODES.map((n) => [n, probes[n].peers])), heads: Object.fromEntries(NODES.map((n) => [n, probes[n].head])),
    fork, volumes: vol, validatorSetIdsInInterval: [...vsIds], loadStats: load,
  };
  appendJsonl(dir("hourly.jsonl"), detail);
  fs.appendFileSync(ROWS_CSV, COLS.map((c) => (row[c] === null || row[c] === undefined ? "" : row[c])).join(",") + "\n");
  for (const n of NODES) { const s = state.nodes[n]; s.f1Interval = 0; s.errInterval = 0; s.warnInterval = 0; s.classesInterval = {}; }
  clog(`ROW ${k}${partial ? " (partial)" : ""}: head ${row.head}, blocks ${row.blocks}, bt p50/p95/p99/max ${row.bt_p50}/${row.bt_p95}/${row.bt_p99}/${row.bt_max}, F-1 ${row.f1_interval} (total ${row.f1_total}), list changes ${row.list_changes}, restarts ${row.restarts_total}, fork mismatches ${row.fork_mismatches}`);
  saveState();
}

// ------------------------------------------------------------------ status.txt (one screen)
async function writeStatus() {
  const lines = [];
  const now = Date.now();
  const load = readJson(dir("load", "stats.json"), {});
  const last = blocks[blocks.length - 1];
  const el = win ? (now - win.startMs) / 3600000 : null, tot = win ? (win.endMs - win.startMs) / 3600000 : null;
  lines.push(`SUR soak ${NET}  ${iso()}  ${win ? `elapsed ${el.toFixed(2)} h of ${tot.toFixed(2)} h` : "BOOTSTRAP (soak clock not started)"}`);
  lines.push(`head ${last ? last.n : "?"}  last block age ${last ? Math.round(now / 1000 - last.ts) : "?"} s  validators ${last ? last.nv : "?"}  blocks recorded ${blocks.length}  rows written ${state.rowsDone}  collector errors ${collectorErrors}`);
  lines.push(`phase ${load.phase || "-"}  tx sent ${load.transfers ? load.transfers.sent : "-"} (errors ${load.transfers ? load.transfers.errors : "-"})  list changes ${load.listChanges ? JSON.stringify(load.listChanges) : "-"}  next change ${load.nextChangeAt || "-"}`);
  const f1 = NODES.reduce((a, n) => a + state.nodes[n].f1Total, 0);
  lines.push(`F-1 occurrences so far: ${f1}   (per node: ${NODES.map((n) => n + "=" + state.nodes[n].f1Total).join(" ")})`);
  lines.push("node   state     restarts  head      peers  f1   errors warns  log lines");
  for (const n of NODES) {
    const p = latestProbe[n] || {}, i = p.info || {}, s = state.nodes[n];
    lines.push(`${n.padEnd(6)} ${String(i.status || "?").padEnd(9)} ${String(i.restarts ?? "?").padEnd(9)} ${String(p.head ?? "?").padEnd(9)} ${String(p.peers ?? "?").padEnd(6)} ${String(s.f1Total).padEnd(4)} ${String(s.errTotal).padEnd(6)} ${String(s.warnTotal).padEnd(6)} ${s.logLines}`);
  }
  try { const rows = fs.readFileSync(ROWS_CSV, "utf8").trim().split("\n"); if (rows.length > 1) { const h = rows[0].split(","), r = rows[rows.length - 1].split(","); const o = Object.fromEntries(h.map((c, i) => [c, r[i]])); lines.push(`last row #${o.row} @ ${o.ts_utc}: blocks ${o.blocks}, bt p50/p95/p99/max ${o.bt_p50}/${o.bt_p95}/${o.bt_p99}/${o.bt_max}, gaps>2.5s ${o.gaps_gt_2_5s}, round-change blocks ${o.round_change_blocks}, F-1 ${o.f1_interval}, fork mismatches ${o.fork_mismatches}, mem max ${o.mem_mb_max} MB, run-dir ${o.run_dir_mb} MB, host free ${o.host_free_gb} GB`); } } catch (e) {}
  fs.writeFileSync(dir("status.txt"), lines.join("\n") + "\n");
}
async function probeAll() {
  await Promise.all(NODES.map(async (n) => { const p = await nodeProbe(n); p.info = await containerInfo(n); latestProbe[n] = p; }));
}

// ------------------------------------------------------------------ self test of the log parser (tools/test-parser.sh): feeds a saved Besu log
if (process.env.SOAK_SELFTEST_LOG) {
  const P = parsers[process.env.SOAK_SELFTEST_NODE || NODES[0]];
  let ts = "2026-01-01T00:00:00.000000000Z";
  for (const l of fs.readFileSync(process.env.SOAK_SELFTEST_LOG, "utf8").split("\n")) {
    const m = /^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})\.(\d{3})/.exec(stripAnsi(l));
    if (m) ts = `${m[1]}T${m[2]}.${m[3]}000000Z`;
    P.line(ts, l);
  }
  P.flushCaptures(); P.writer.close(); saveState();
  console.log(JSON.stringify({ selftest: true, f1Total: P.st.f1Total, errTotal: P.st.errTotal, warnTotal: P.st.warnTotal, classes: P.st.classesTotal }, null, 1));
  process.exit(0);
}

// ------------------------------------------------------------------ main
let win = null;
(async () => {
  clog(`collector start: net ${NET}, ${NODES.length} nodes, interval ${INTERVAL_MS / 60000} min, rotate ${ROTATE_BYTES / 1048576} MB x ${KEEP_ROTATED}`);
  loadBlocks();
  clog(`resumed: ${blocks.length} blocks in blocks.csv, last ${state.lastBlock}, rows done ${state.rowsDone}`);
  NODES.forEach((n) => followLogs(n));
  followEvents();
  let lastStatus = 0, lastSave = 0, lastProbe = 0;
  while (!stopping) {
    if (fs.existsSync(stopFile)) stopping = true;
    try { if (!win) win = readJson(dir("meta", "window.json"), null); } catch (e) {}
    try { await recordBlocks(); } catch (e) { cerr("recordBlocks", e); }
    const now = Date.now();
    if (win) {
      while (!stopping && now >= win.startMs + (state.rowsDone + 1) * INTERVAL_MS + 8000) {
        const k = state.rowsDone + 1;
        try { await makeRow(k, win.startMs + (k - 1) * INTERVAL_MS, win.startMs + k * INTERVAL_MS, false); state.rowsDone = k; saveState(); } catch (e) { cerr("makeRow", e); state.rowsDone = k; break; }
      }
      if (now >= win.endMs + 120000) stopping = true;
    }
    if (now - lastProbe > 15000) { lastProbe = now; try { await probeAll(); } catch (e) { cerr("probeAll", e); } }
    if (now - lastStatus > 15000) { lastStatus = now; try { await writeStatus(); } catch (e) { cerr("writeStatus", e); } }
    if (now - lastSave > 30000) { lastSave = now; saveState(); }
    if (!stopping) await sleep(1000);
  }
  clog("stop requested: final drain");
  await sleep(4000);
  try { await recordBlocks(); } catch (e) { cerr("final recordBlocks", e); }
  for (const n of NODES) parsers[n].flushCaptures();
  if (win) {
    const k = state.rowsDone + 1, t0 = win.startMs + (k - 1) * INTERVAL_MS;
    if (Date.now() - t0 > 5000) { try { await makeRow(k, t0, Math.min(Date.now(), win.endMs + 60000) + 1, true); state.rowsDone = k; } catch (e) { cerr("final makeRow", e); } }
  }
  try { await writeStatus(); } catch (e) {}
  saveState();
  for (const n of NODES) parsers[n].writer.close();
  clog("collector done");
  process.exit(0);
})().catch((e) => { console.error("COLLECTOR CRASHED", e); saveState(); process.exit(1); });
process.on("SIGTERM", () => { stopping = true; });
process.on("SIGINT", () => { stopping = true; });
