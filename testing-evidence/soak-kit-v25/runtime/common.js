// Shared helpers for the container-side scripts (bootstrap.js, loadgen.js, collector.js, analyze.js). Node 22 only, plus the vendored ethers.
"use strict";
const fs = require("fs");
const path = require("path");
const http = require("http");

const RUN_DIR = process.env.RUN_DIR || "/run-data";
const KIT = process.env.KIT_DIR || "/kit";
const PREFIX = process.env.SOAK_PREFIX || "sur25s-";
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const nowMs = () => Date.now();
const iso = (ms = Date.now()) => new Date(ms).toISOString();
const log = (tag, ...a) => console.log(`${iso()} [${tag}]`, ...a);

function readJson(p, dflt) { try { return JSON.parse(fs.readFileSync(p, "utf8")); } catch (e) { return dflt; } }
function writeJsonAtomic(p, obj) { const t = p + ".tmp"; fs.writeFileSync(t, JSON.stringify(obj, (k, v) => (typeof v === "bigint" ? v.toString() : v), 1)); fs.renameSync(t, p); }
function appendJsonl(p, obj) { fs.appendFileSync(p, JSON.stringify(obj, (k, v) => (typeof v === "bigint" ? v.toString() : v)) + "\n"); }
function ensureDir(d) { fs.mkdirSync(d, { recursive: true }); }

const keys = readJson(path.join(KIT, "TEST-KEYS-DO-NOT-REUSE.json"), {});
const abis = readJson(path.join(KIT, "runtime", "abi.json"), {});

// -------- JSON-RPC over HTTP (global fetch, with a timeout)
async function rpc(url, method, params = [], timeoutMs = 15000) {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), timeoutMs);
  try {
    const res = await fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }), signal: ac.signal });
    const j = await res.json();
    if (j.error) { const e = new Error(`${method}: ${j.error.message}`); e.rpcError = j.error; throw e; }
    return j.result;
  } finally { clearTimeout(t); }
}
async function rpcBatch(url, calls, timeoutMs = 20000) { // calls: [[method, params], ...] -> results (errors become {error})
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), timeoutMs);
  try {
    const body = calls.map((c, i) => ({ jsonrpc: "2.0", id: i + 1, method: c[0], params: c[1] || [] }));
    const res = await fetch(url, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body), signal: ac.signal });
    const j = await res.json();
    const out = new Array(calls.length);
    for (const r of j) out[r.id - 1] = r.error ? { error: r.error } : r.result;
    return out;
  } finally { clearTimeout(t); }
}
const nodeUrl = (name) => `http://${PREFIX}${name}:8545`;

// -------- Docker Engine API over the unix socket (collector only)
function dockerReq(pathAndQuery, { method = "GET", timeoutMs = 20000, raw = false } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request({ socketPath: "/var/run/docker.sock", path: pathAndQuery, method, timeout: timeoutMs }, (res) => {
      if (raw) return resolve(res);
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => {
        const body = Buffer.concat(chunks).toString("utf8");
        if (res.statusCode >= 400) return reject(new Error(`docker ${res.statusCode} ${pathAndQuery}: ${body.slice(0, 200)}`));
        try { resolve(body ? JSON.parse(body) : {}); } catch (e) { resolve(body); }
      });
    });
    req.on("timeout", () => req.destroy(new Error("docker api timeout " + pathAndQuery)));
    req.on("error", reject);
    req.end();
  });
}

const stripAnsi = (s) => s.replace(/\x1b\[[0-9;]*m/g, "");
const pct = (sorted, p) => (sorted.length ? sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1))] : null);

module.exports = { fs, path, RUN_DIR, KIT, PREFIX, sleep, nowMs, iso, log, readJson, writeJsonAtomic, appendJsonl, ensureDir, keys, abis, rpc, rpcBatch, nodeUrl, dockerReq, stripAnsi, pct };
