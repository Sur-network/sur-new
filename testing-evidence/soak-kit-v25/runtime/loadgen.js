// Load generator (runs in a container for the whole soak). Everything it does is logged to <RUN_DIR>/load/events.jsonl and summarised
// in <RUN_DIR>/load/stats.json.
//
//   * PHASES (cycled until the end; PHASE_PLAN = "name:minutes:txPerSec:changeEveryMin[:burstEveryMin],..."):
//       txPerSec        steady plain value transfers from 8 test accounts (0 = none: empty blocks)
//       changeEveryMin  one validator-list change every N minutes (jittered +-30 %); 0 = no list changes in this phase
//       burstEveryMin   a burst of BURST_SIZE transfers at once every N minutes (0 = none)
//   * LIST CHANGES (rotating): swap = owner(V-1) proposeOperator + Verifier.confirmOperatorReady, alternating between its two running
//     nodes; suspend = owner(V) selfSuspend; resume = requestResume + Verifier.recordResume; one-off entrant activation
//     (Verifier.recordActivation of owner8, node x2) at ENTRANT_AT_FRAC of the run, during a change phase.
//   * STATE-CHANGING CONTRACT CALLS without list change: IdentityRegistry oracle flag toggles every IDENTITY_TOGGLE_SEC while txPerSec>0.
//   * getValidators() eth_call poller at POLL_HZ (dashboard mimic), rotating over all nodes.
"use strict";
const { ethers, txCall, sendRaw, view, addrOf, loadNet, wallet, GAS_PRICE } = require("./chain");
const { rpc, nodeUrl, sleep, log, readJson, writeJsonAtomic, appendJsonl, ensureDir, path, fs, RUN_DIR, iso } = require("./common");

const NET = process.env.NET || "n7";
const net = loadNet(NET);
const V = net.validators;
const chainId = net.chainId;
const PLAN_STR = process.env.PHASE_PLAN || "idle:30:0:0,transfers:60:0.5:0,changes:60:0.5:15,heavy:30:5:0:5,changes-heavy:30:5:10:5";
const POLL_HZ = Number(process.env.POLL_HZ ?? 1);
const BURST_SIZE = Number(process.env.BURST_SIZE || 60);
const IDENTITY_TOGGLE_SEC = Number(process.env.IDENTITY_TOGGLE_SEC || 20);
const VERIFY_DELAY_SEC = Number(process.env.VERIFIER_CHECK_DELAY_SEC || 8);
const ENTRANT_AT_FRAC = Number(process.env.ENTRANT_AT_FRAC ?? 0.4);
const JITTER = 0.3;
const phases = PLAN_STR.split(",").map((s) => { const p = s.split(":"); return { name: p[0], ms: Number(p[1]) * 60000, tps: Number(p[2]), changeEveryMs: Number(p[3] || 0) * 60000, burstEveryMs: Number(p[4] || 0) * 60000 }; });
const CYCLE_MS = phases.reduce((a, p) => a + p.ms, 0);
const allNodes = [...net.validatorNodes, ...net.extraNodes];
const evFile = path.join(RUN_DIR, "load", "events.jsonl");
const statsFile = path.join(RUN_DIR, "load", "stats.json");
const stopFile = path.join(RUN_DIR, "STOP");

const stats = {
  startedAt: iso(), phase: null, transfers: { sent: 0, errors: 0, resyncs: 0, bursts: 0 }, errorsByClass: {},
  identityToggles: { ok: 0, err: 0 }, listChanges: { swap: 0, selfSuspend: 0, resume: 0, activate: 0, failed: 0, skipped: 0 },
  poll: { ok: 0, err: 0, maxMs: 0, recent: [] }, lastChange: null, nextChangeAt: null,
};
const ev = (type, extra = {}) => appendJsonl(evFile, { t: iso(), ms: Date.now(), type, phase: stats.phase, ...extra });
const errClass = (e) => String((e && e.message) || e).replace(/0x[0-9a-fA-F]+/g, "0x..").replace(/\d+/g, "#").slice(0, 80);
const bump = (m, k) => { m[k] = (m[k] || 0) + 1; };

// ---------------------------------------------------------------- transfers
const POOL = Array.from({ length: 64 }, (_, i) => ethers.getAddress("0x" + ethers.keccak256(ethers.toUtf8Bytes("soak-recipient-" + i)).slice(26)));
const senders = Array.from({ length: 8 }, (_, i) => ({ role: "lg" + (i + 1), nonce: null, node: allNodes[i % allNodes.length], busy: false }));
let rr = 0;
async function resyncNonce(s) { s.nonce = Number(BigInt(await rpc(nodeUrl(s.node), "eth_getTransactionCount", [addrOf(s.role), "pending"]))); stats.transfers.resyncs++; }
async function sendTransfer(s) {
  if (s.nonce === null) await resyncNonce(s);
  const to = POOL[(Math.random() * POOL.length) | 0];
  const nonce = s.nonce++;
  try {
    await sendRaw(nodeUrl(s.node), chainId, s.role, to, "0x", { value: 1n, gasLimit: 21000n, nonce });
    stats.transfers.sent++;
  } catch (e) {
    stats.transfers.errors++; bump(stats.errorsByClass, errClass(e));
    s.nonce = null; // resync on next use
    // if that node is unreachable, move this sender to another node
    if (/fetch failed|abort|ECONN/i.test(String(e.message))) s.node = allNodes[(Math.random() * allNodes.length) | 0];
  }
}
function fireTransfers(n) { // n transfers spread over the senders (round robin); in-flight guard per sender via sequential chaining
  for (let i = 0; i < n; i++) {
    const s = senders[rr++ % senders.length];
    if ((s.pending || 0) > 60) { stats.transfers.errors++; bump(stats.errorsByClass, "dropped: sender backlog"); continue; } // node not answering
    s.pending = (s.pending || 0) + 1;
    s.chain = (s.chain || Promise.resolve()).then(() => sendTransfer(s)).finally(() => { s.pending--; });
  }
}

// ---------------------------------------------------------------- Registry operations (sequential)
const ST = { None: 0, Probation: 1, Active: 2, Demoted: 3, Exiting: 4, RemovedInRecovery: 5, SelfSuspended: 6 };
const rpcNode = () => nodeUrl(net.validatorNodes[0]);
async function status(owner) { return Number((await view(rpcNode(), "REG", "validators", [addrOf(owner)]))[0]); }
async function headOf(n) { return Number(BigInt(await rpc(nodeUrl(n), "eth_blockNumber"))); }
let evCounter = 0;
const evidence = (what) => ethers.keccak256(ethers.toUtf8Bytes(`soak-${what}-${Date.now()}-${evCounter++}`));
async function qbftLen() { try { return (await rpc(rpcNode(), "qbft_getValidatorsByBlockNumber", ["latest"])).length; } catch (e) { return null; } }

async function opSwap() {
  const owner = net.swapOwner, [opA, opB] = net.swapOps;
  if ((await status(owner)) !== ST.Active) { stats.listChanges.skipped++; ev("skip", { op: "swap", reason: "owner not Active" }); return; }
  const cur = (await view(rpcNode(), "REG", "operatorOf", [addrOf(owner)]))[0].toLowerCase();
  const target = cur === addrOf(opA).toLowerCase() ? opB : opA;
  const targetNode = net.swapNodes[target];
  const hn = await headOf(targetNode), h1 = await headOf(net.validatorNodes[0]);
  if (h1 - hn > 3) { stats.listChanges.skipped++; ev("skip", { op: "swap", reason: `target node ${targetNode} lags ${h1 - hn} blocks` }); return; }
  const pending = (await view(rpcNode(), "REG", "pendingOperator", [addrOf(owner)]))[0];
  if (pending !== ethers.ZeroAddress) await txCall(rpcNode(), chainId, owner, "REG", "cancelOperatorChange", []);
  const p = await txCall(rpcNode(), chainId, owner, "REG", "proposeOperator", [addrOf(target)]);
  await sleep(VERIFY_DELAY_SEC * 1000); // the Verifier's health check of the new node, simulated by a pause after the node-lag check above
  const c = await txCall(rpcNode(), chainId, "verifier", "REG", "confirmOperatorReady", [addrOf(owner), evidence("swap")]);
  stats.listChanges.swap++;
  stats.lastChange = { type: "swap", block: c.block, at: iso() };
  ev("listChange", { op: "swap", block: c.block, proposeBlock: p.block, owner, from: cur, to: addrOf(target), node: targetNode, validatorsAfter: await qbftLen() });
}
async function opSuspend() {
  const owner = net.suspendOwner;
  if ((await status(owner)) !== ST.Active) { stats.listChanges.skipped++; ev("skip", { op: "suspend", reason: "owner not Active" }); return; }
  const r = await txCall(rpcNode(), chainId, owner, "REG", "selfSuspend", []);
  stats.listChanges.selfSuspend++; stats.lastChange = { type: "selfSuspend", block: r.block, at: iso() };
  ev("listChange", { op: "selfSuspend", block: r.block, owner, validatorsAfter: await qbftLen() });
}
async function opResume(why = "rotation") {
  const owner = net.suspendOwner;
  if ((await status(owner)) !== ST.SelfSuspended) { stats.listChanges.skipped++; ev("skip", { op: "resume", reason: "owner not SelfSuspended" }); return; }
  await txCall(rpcNode(), chainId, owner, "REG", "requestResume", []);
  const r = await txCall(rpcNode(), chainId, "verifier", "REG", "recordResume", [addrOf(owner), evidence("resume")]);
  stats.listChanges.resume++; stats.lastChange = { type: "recordResume", block: r.block, at: iso() };
  ev("listChange", { op: "recordResume", why, block: r.block, owner, validatorsAfter: await qbftLen() });
}
async function opActivate() {
  const owner = net.entrantOwner;
  const st = await status(owner);
  if (st !== ST.Probation) { entrantDone = true; ev("skip", { op: "activate", reason: "entrant status " + st }); return; }
  const hn = await headOf(net.entrantNode), h1 = await headOf(net.validatorNodes[0]);
  if (h1 - hn > 3) { stats.listChanges.skipped++; ev("skip", { op: "activate", reason: `entrant node lags ${h1 - hn}` }); return; }
  const r = await txCall(rpcNode(), chainId, "verifier", "REG", "recordActivation", [addrOf(owner), evidence("activate")]);
  entrantDone = true;
  stats.listChanges.activate++; stats.lastChange = { type: "recordActivation", block: r.block, at: iso() };
  ev("listChange", { op: "recordActivation", block: r.block, owner, validatorsAfter: await qbftLen() });
}
let entrantDone = ENTRANT_AT_FRAC <= 0, entrantNextTry = 0, phaseResumeNext = 0;
let opBusy = false;
async function runOp(name, fn) {
  opBusy = true;
  try { await fn(); } catch (e) { stats.listChanges.failed++; ev("opError", { op: name, error: String(e.message).slice(0, 200) }); log("loadgen", `op ${name} failed: ${e.message}`); }
  finally { opBusy = false; }
}
const ROT = ["swap", "suspend", "resume"];
let rot = 0;
async function nextRotationOp() {
  const suspended = (await status(net.suspendOwner)) === ST.SelfSuspended;
  for (let k = 0; k < 3; k++) {
    const op = ROT[rot++ % 3];
    if (op === "resume" && !suspended) continue;
    if (op === "suspend" && suspended) continue;
    return op;
  }
  return "swap";
}

// ---------------------------------------------------------------- identity toggles (contract calls that change state, no list change)
let toggle = true, idBusy = false;
async function identityToggle() {
  if (idBusy) return; idBusy = true;
  try {
    const who = addrOf("lg" + (1 + Math.floor(Math.random() * 4)));
    await txCall(nodeUrl(allNodes[(Math.random() * allNodes.length) | 0]), chainId, "identityOracle", "IDENTITY", Math.random() < 0.5 ? "setPhoneVerified" : "setTelegramVerified", [who, toggle], { gasLimit: 300000n });
    toggle = !toggle; stats.identityToggles.ok++;
  } catch (e) { stats.identityToggles.err++; bump(stats.errorsByClass, "identity: " + errClass(e)); }
  finally { idBusy = false; }
}

// ---------------------------------------------------------------- getValidators() poller
let pollIdx = 0;
async function pollOnce() {
  const n = allNodes[pollIdx++ % allNodes.length];
  const t0 = process.hrtime.bigint();
  try {
    await view(nodeUrl(n), "REG", "getValidators");
    const ms = Number(process.hrtime.bigint() - t0) / 1e6;
    stats.poll.ok++; stats.poll.maxMs = Math.max(stats.poll.maxMs, ms);
    stats.poll.recent.push(ms); if (stats.poll.recent.length > 600) stats.poll.recent.shift();
  } catch (e) { stats.poll.err++; bump(stats.errorsByClass, "poll: " + errClass(e)); }
}

// ---------------------------------------------------------------- main loop
function phaseAt(elapsedMs) {
  let pos = elapsedMs % CYCLE_MS;
  for (const p of phases) { if (pos < p.ms) return { ...p, cycle: Math.floor(elapsedMs / CYCLE_MS) }; pos -= p.ms; }
  return { ...phases[phases.length - 1], cycle: 0 };
}
(async () => {
  ensureDir(path.join(RUN_DIR, "load"));
  const win = readJson(path.join(RUN_DIR, "meta", "window.json"));
  if (!win) { console.error("no meta/window.json"); process.exit(1); }
  const { startMs, endMs } = win;
  log("loadgen", `window ${iso(startMs)} .. ${iso(endMs)}; plan ${PLAN_STR} (cycle ${CYCLE_MS / 60000} min); poll ${POLL_HZ} Hz; entrant at ${ENTRANT_AT_FRAC}`);
  ev("loadgen-start", { plan: PLAN_STR, pollHz: POLL_HZ, burstSize: BURST_SIZE, entrantAtFrac: ENTRANT_AT_FRAC, windowStart: iso(startMs), windowEnd: iso(endMs) });
  let last = Date.now(), credit = 0, curKey = null, nextChangeAt = 0, nextBurstAt = 0, lastToggle = 0, lastPoll = 0, lastFlush = 0;
  if (POLL_HZ <= 0) ev("note", { poller: "disabled" });
  for (;;) {
    const now = Date.now();
    if (fs.existsSync(stopFile) || now >= endMs) break;
    const dt = now - last; last = now;
    const elapsed = now - startMs;
    const ph = elapsed < 0 ? { name: "pre", ms: 0, tps: 0, changeEveryMs: 0, burstEveryMs: 0, cycle: 0 } : phaseAt(elapsed);
    const key = ph.name + "#" + ph.cycle;
    if (key !== curKey) {
      curKey = key; stats.phase = ph.name;
      ev("phase", { name: ph.name, cycle: ph.cycle, tps: ph.tps, changeEveryMin: ph.changeEveryMs / 60000, burstEveryMin: ph.burstEveryMs / 60000 });
      nextChangeAt = ph.changeEveryMs ? now + ph.changeEveryMs * (0.3 + Math.random() * 0.4) : 0; // first change comes earlier
      nextBurstAt = ph.burstEveryMs ? now + 30000 : 0;
    }
    // transfers
    if (ph.tps > 0) { credit += (ph.tps * dt) / 1000; const k = Math.floor(credit); if (k > 0) { credit -= k; fireTransfers(k); } } else credit = 0;
    if (ph.burstEveryMs && now >= nextBurstAt) { fireTransfers(BURST_SIZE); stats.transfers.bursts++; ev("burst", { size: BURST_SIZE }); nextBurstAt = now + ph.burstEveryMs; }
    // identity toggles
    if (ph.tps > 0 && now - lastToggle >= IDENTITY_TOGGLE_SEC * 1000) { lastToggle = now; identityToggle(); }
    // list changes
    if (!opBusy) {
      if (ph.changeEveryMs > 0) {
        const entrantDue = !entrantDone && ENTRANT_AT_FRAC > 0 && elapsed >= ENTRANT_AT_FRAC * (endMs - startMs);
        if (entrantDue && now >= entrantNextTry) { entrantNextTry = now + 60000; runOp("activate", opActivate); nextChangeAt = now + ph.changeEveryMs * (0.7 + Math.random() * 0.6); }
        else if (!entrantDue && now >= nextChangeAt) {
          nextChangeAt = now + ph.changeEveryMs * (1 - JITTER + Math.random() * 2 * JITTER);
          runOp("rotation", async () => { const op = await nextRotationOp(); if (op === "swap") await opSwap(); else if (op === "suspend") await opSuspend(); else await opResume(); });
        }
      } else if (elapsed > 0 && now >= phaseResumeNext) {
        phaseResumeNext = now + 15000;
        // no list changes in this phase: do not leave the suspend-owner suspended (keeps the quiet phase at full strength)
        runOp("phase-resume", async () => { if ((await status(net.suspendOwner)) === ST.SelfSuspended) await opResume("phase-boundary"); });
      }
    }
    stats.nextChangeAt = nextChangeAt ? iso(nextChangeAt) : null;
    // poller
    if (POLL_HZ > 0 && now - lastPoll >= 1000 / POLL_HZ) { lastPoll = now; pollOnce(); }
    if (now - lastFlush >= 5000) {
      lastFlush = now;
      const r = stats.poll.recent.slice().sort((a, b) => a - b);
      writeJsonAtomic(statsFile, { ...stats, updatedAt: iso(), elapsedMin: Math.round(elapsed / 600) / 100, poll: { ok: stats.poll.ok, err: stats.poll.err, maxMs: Math.round(stats.poll.maxMs), p50Ms: r.length ? Math.round(r[(r.length * 0.5) | 0]) : null, p99Ms: r.length ? Math.round(r[Math.min(r.length - 1, (r.length * 0.99) | 0)]) : null } });
    }
    await sleep(100);
  }
  ev("loadgen-stop", { reason: fs.existsSync(stopFile) ? "STOP file" : "window end", stats: { ...stats, poll: { ok: stats.poll.ok, err: stats.poll.err } } });
  const r = stats.poll.recent.slice().sort((a, b) => a - b);
  writeJsonAtomic(statsFile, { ...stats, updatedAt: iso(), final: true, poll: { ok: stats.poll.ok, err: stats.poll.err, maxMs: Math.round(stats.poll.maxMs), p50Ms: r.length ? Math.round(r[(r.length * 0.5) | 0]) : null } });
  await sleep(2000);
  process.exit(0);
})().catch((e) => { console.error("LOADGEN CRASHED:", e); ev("loadgen-crash", { error: String(e.stack || e).slice(0, 500) }); process.exit(1); });
