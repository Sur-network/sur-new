// Bootstrap (runs once, in a container, before the soak clock starts): waits for the nodes, then brings the validator list from the
// genesis state (owner1/op1 Active) to V validators through the REAL Registry flow, exactly as round 1 did:
//   owner_i.setOperator(op_i)   (owner is in Probation, immediate)
//   verifier.recordActivation(owner_i, hash)   (founders skip the probation wait)
// plus: the entrant (owner8) sets its operator now (activation happens later, by loadgen), and 4 load accounts register an identity.
// Writes <RUN_DIR>/load/bootstrap.json. Exit code 0 = ready.
"use strict";
const { ethers, txCall, view, addrOf, loadNet } = require("./chain");
const { rpc, nodeUrl, sleep, log, writeJsonAtomic, ensureDir, path, RUN_DIR } = require("./common");

const NET = process.env.NET || "n7";
const net = loadNet(NET);
const V = net.validators;
const url = nodeUrl("n1");
const allNodes = [...net.validatorNodes, ...net.extraNodes];
const head = async (n) => Number(BigInt(await rpc(nodeUrl(n), "eth_blockNumber")));

async function waitAllUp(timeoutS = 300) {
  const t0 = Date.now();
  for (;;) {
    const bad = [];
    for (const n of allNodes) { try { await head(n); } catch (e) { bad.push(n); } }
    if (!bad.length) return;
    if (Date.now() - t0 > timeoutS * 1000) throw new Error("nodes not reachable: " + bad.join(","));
    await sleep(2000);
  }
}
async function waitSynced(tol = 2, timeoutS = 600) {
  const t0 = Date.now();
  for (;;) {
    const h1 = await head("n1"); const lag = [];
    for (const n of allNodes) { const h = await head(n); if (h1 - h > tol) lag.push(`${n}:${h}`); }
    if (h1 >= 2 && !lag.length) return h1;
    if (Date.now() - t0 > timeoutS * 1000) throw new Error("nodes not synced: " + lag.join(","));
    await sleep(2000);
  }
}
async function qbftSet() { return (await rpc(url, "qbft_getValidatorsByBlockNumber", ["latest"])).map((a) => ethers.getAddress(a)); }

(async () => {
  ensureDir(path.join(RUN_DIR, "load"));
  const out = { net: NET, startedAt: new Date().toISOString(), steps: [] };
  log("bootstrap", `net ${NET}: ${V} validators wanted; waiting for ${allNodes.length} nodes`);
  await waitAllUp();
  out.headWhenSynced = await waitSynced();
  log("bootstrap", "all nodes up and synced at head " + out.headWhenSynced);
  const chainId = net.chainId;
  const verifier = "verifier";
  for (let i = 2; i <= V; i++) {
    const owner = "owner" + i, op = "op" + i;
    const st = Number((await view(url, "REG", "validators", [addrOf(owner)]))[0]);
    if (st === 2) { out.steps.push({ owner, note: "already Active" }); continue; }
    if (st !== 1) throw new Error(`${owner} has status ${st}, expected Probation(1)`);
    const cur = (await view(url, "REG", "operatorOf", [addrOf(owner)]))[0];
    if (cur.toLowerCase() !== addrOf(op).toLowerCase()) {
      const r = await txCall(url, chainId, owner, "REG", "setOperator", [addrOf(op)]);
      out.steps.push({ owner, fn: "setOperator", block: r.block });
    }
    const r2 = await txCall(url, chainId, verifier, "REG", "recordActivation", [addrOf(owner), ethers.keccak256(ethers.toUtf8Bytes("soak-bootstrap-" + owner))]);
    out.steps.push({ owner, fn: "recordActivation", block: r2.block });
    // wait until the QBFT set has i members, then 3 more blocks so the new node has taken part in consensus
    const t0 = Date.now();
    for (;;) { const s = await qbftSet(); if (s.length === i) break; if (Date.now() - t0 > 120000) throw new Error("QBFT set did not grow to " + i); await sleep(1000); }
    const h = await head("n1");
    const t1 = Date.now();
    while ((await head("n1")) < h + 3) { if (Date.now() - t1 > 120000) throw new Error("no blocks after activation of " + owner); await sleep(500); }
    log("bootstrap", `${owner} Active (activation block ${r2.block}); validators now ${i}`);
  }
  // entrant: operator set now, activation later by loadgen
  const ent = net.entrantOwner;
  const entCur = (await view(url, "REG", "operatorOf", [addrOf(ent)]))[0];
  if (entCur.toLowerCase() !== addrOf(net.entrantOp).toLowerCase()) {
    const r = await txCall(url, chainId, ent, "REG", "setOperator", [addrOf(net.entrantOp)]);
    out.steps.push({ owner: ent, fn: "setOperator", block: r.block });
  }
  // identities of lg1..lg4 (state-changing oracle calls are exercised by loadgen)
  for (let i = 1; i <= 4; i++) {
    const role = "lg" + i;
    try { const r = await txCall(url, chainId, role, "IDENTITY", "registerIdentity", [0, "Soak Load " + i], { gasLimit: 400000n }); out.steps.push({ role, fn: "registerIdentity", block: r.block }); }
    catch (e) { out.steps.push({ role, fn: "registerIdentity", error: String(e.message).slice(0, 120) }); }
  }
  const set = await qbftSet();
  const regList = (await view(url, "REG", "getValidators"))[0].map((a) => ethers.getAddress(a));
  if (set.length !== V || regList.length !== V) throw new Error(`validator set size: qbft ${set.length}, contract ${regList.length}, wanted ${V}`);
  out.finishedAt = new Date().toISOString();
  out.head = await head("n1");
  out.validatorOperators = regList;
  writeJsonAtomic(path.join(RUN_DIR, "load", "bootstrap.json"), out);
  log("bootstrap", `done at head ${out.head}: ${V} validators active`);
  process.exit(0);
})().catch((e) => { console.error("BOOTSTRAP FAILED:", e); process.exit(1); });
