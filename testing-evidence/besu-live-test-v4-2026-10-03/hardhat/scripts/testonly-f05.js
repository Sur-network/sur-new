// F05 — rolling restart to apply a NEW Besu reward transition on a running 5-validator QBFT network (Net-F4).
// Question: is "change genesis file on every node + restart nodes one at a time" accepted by Besu, does the chain keep going (f=1 tolerance),
// and does the reward really change at X'?   NO distribution is performed on this network afterwards (v4 F05).
// env: X_OFFSET (default 300): X' = head at start + X_OFFSET
const { ethers, ROOT, fs, path, rpc, hex, sleep, SUR, ADDR, observeBlock, saveEvidence } = require("./v5-lib");
const { execSync } = require("child_process");

const NET = "Net-F4";
const NETDIR = `${ROOT}/nets/${NET}`;
const nodes = JSON.parse(fs.readFileSync(`${NETDIR}/nodes-info.json`, "utf8"));
const ctl = (action, node) => execSync(`bash "${ROOT}/evidence/03-commands/v5-nodectl.sh" ${action} ${NET} ${node}`, { encoding: "utf8" }).trim();
const launch = (node) => execSync(`bash "${ROOT}/evidence/03-commands/v5-launch-net.sh" ${NET} ${node}`, { encoding: "utf8" }).trim();
const heightOf = async (port) => { try { return Number(await rpc(`http://127.0.0.1:${port}`)("eth_blockNumber")); } catch { return null; } };
const peersOf = async (port) => { try { return Number(await rpc(`http://127.0.0.1:${port}`)("net_peerCount")); } catch { return null; } };
const allHeights = async () => Object.fromEntries(await Promise.all(nodes.map(async (n) => [n.dir, await heightOf(n.rpc)])));
const logTail = (node, from) => { const t = fs.readFileSync(`${ROOT}/logs/${NET}/${node}.log`, "utf8"); return t.slice(from); };

async function main() {
  const X_OFFSET = Number(process.env.X_OFFSET || 300);
  const out = { NET, steps: [], startedAt: new Date().toISOString() };
  const origGenesis = JSON.parse(fs.readFileSync(`${NETDIR}/genesis-original-no-transition.json`, "utf8"));
  const sha = (p) => require("crypto").createHash("sha256").update(fs.readFileSync(p)).digest("hex");
  out.originalGenesisSha256 = sha(`${NETDIR}/genesis-original-no-transition.json`);
  out.originalHasTransitions = !!origGenesis.config.transitions;

  const head0 = Math.max(...Object.values(await allHeights()).filter((x) => x !== null));
  const Xp = head0 + X_OFFSET;
  out.headAtStart = head0; out.XPrime = Xp;
  out.blockZeroHashBefore = {};
  for (const n of nodes) out.blockZeroHashBefore[n.dir] = (await rpc(`http://127.0.0.1:${n.rpc}`)("eth_getBlockByNumber", ["0x0", false])).hash;

  // 1. add the transition to the shared genesis file used by every node's config
  const newGenesis = JSON.parse(JSON.stringify(origGenesis));
  newGenesis.config.transitions = { qbft: [{ block: Xp, blockreward: "3000000000000000000" }] };
  fs.writeFileSync(`${NETDIR}/genesis.json`, JSON.stringify(newGenesis, null, 2));
  out.newGenesisSha256 = sha(`${NETDIR}/genesis.json`);
  out.transitionAdded = newGenesis.config.transitions;
  console.log(`[F05] head=${head0}, X'=${Xp}; genesis.json updated (sha ${out.newGenesisSha256.slice(0, 12)})`);

  // 2. restart nodes ONE AT A TIME (never two down at once)
  for (const n of nodes) {
    const step = { node: n.dir, role: n.role };
    const logPos = fs.statSync(`${ROOT}/logs/${NET}/${n.dir}.log`).size;
    step.heightsBeforeStop = await allHeights();
    step.stop = ctl("stop", n.dir);
    await sleep(10000);
    step.heightsWhileDown = await allHeights();
    fs.appendFileSync(`${ROOT}/logs/${NET}/${n.dir}.log`, `\n===== F05 RESTART MARKER ${new Date().toISOString()} : restarting with genesis.json containing transition at ${Xp} =====\n`);
    const logPos2 = fs.statSync(`${ROOT}/logs/${NET}/${n.dir}.log`).size;
    launch(n.dir);
    // wait for RPC + sync to within 2 blocks of the others
    let ok = false;
    for (let i = 0; i < 90; i++) {
      await sleep(3000);
      const h = await heightOf(n.rpc);
      const others = Math.max(...(await Promise.all(nodes.filter((m) => m.dir !== n.dir).map((m) => heightOf(m.rpc)))).filter((x) => x !== null));
      if (h !== null && others - h <= 2) { ok = true; step.rejoinedAtHeight = h; step.peersAfterRejoin = await peersOf(n.rpc); break; }
    }
    step.rejoinedAndSynced = ok;
    step.heightsAfterRejoin = await allHeights();
    const tail = logTail(n.dir, logPos2);
    step.logSignals = { errorLines: (tail.match(/.*(ERROR|Exception|Invalid|invalid|mismatch).*/g) || []).slice(0, 8).map((s) => s.replace(/\x1b\[[0-9;]*m/g, "").slice(0, 300)) };
    out.steps.push(step);
    console.log(`[F05] ${n.dir}: stopped, restarted, rejoined=${ok} h=${step.rejoinedAtHeight}`);
    if (!ok) { out.aborted = `node ${n.dir} did not rejoin within the wait; stopping the rolling restart to avoid two nodes being down`; break; }
    await sleep(6000);
  }

  // 3. wait until chain passes X'+8, then observe the boundary
  console.log("[F05] waiting for the chain to pass X' ...");
  const p0 = new ethers.JsonRpcProvider(`http://127.0.0.1:${nodes[0].rpc}`);
  for (;;) { const h = await p0.getBlockNumber(); if (h >= Xp + 8) break; await sleep(5000); }
  const call = rpc(`http://127.0.0.1:${nodes[0].rpc}`);
  out.boundary = [];
  for (let b = Xp - 3; b <= Xp + 4; b++) out.boundary.push(await observeBlock(p0, call, b));
  out.finalHeights = await allHeights();
  const refH = Math.min(...Object.values(out.finalHeights).filter((x) => x !== null)) - 1;
  out.hashAgreement = { atBlock: refH, hashes: {} };
  for (const n of nodes) out.hashAgreement.hashes[n.dir] = (await rpc(`http://127.0.0.1:${n.rpc}`)("eth_getBlockByNumber", [hex(refH), false]))?.hash;
  out.hashAgreement.allEqual = new Set(Object.values(out.hashAgreement.hashes)).size === 1;
  out.firstBlockPaying3 = (out.boundary.find((b) => BigInt(b.balanceDelta) === 3000000000000000000n) || {}).n || null;
  out.rewardChangedAtXPrime = out.firstBlockPaying3 === Xp;
  out.peerCounts = {}; for (const n of nodes) out.peerCounts[n.dir] = await peersOf(n.rpc);
  out.finishedAt = new Date().toISOString();
  console.log("[F05] firstBlockPaying3:", out.firstBlockPaying3, "X':", Xp, "hashAgreement:", out.hashAgreement.allEqual, "heights:", JSON.stringify(out.finalHeights));
  saveEvidence("Net-F4-F05.json", out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
