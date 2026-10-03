// A14 live leg: Besu computes the block-0 stateRoot from the alloc it LOADED. Compare it with the Merkle-Patricia root of the genesis.json alloc
// (computed by v5-mpt.js, validated against live nodes). Equal => the node's loaded state is exactly genesis.json's alloc: no extra account, no extra slot.
// Combined with A14-static-scan.json (genesis.json alloc == independently derived expected alloc) this covers the live baseline networks.
// For networks whose nodes are stopped, ONE node is started briefly (read-only: no peers, no mining, no transactions), queried, and stopped.
// env: NETS (comma list), default = all baseline networks + Net-Fork (fork, informational)
const { ethers, ROOT, fs, rpc, sleep, saveEvidence } = require("./v5-lib");
const { allocStateRoot } = require("./v5-mpt");
const { execSync } = require("child_process");
const NETS = (process.env.NETS || "Net-B,Net-L01,Net-L02,Net-L04,Net-L05,Net-D,Net-F1,Net-F2,Net-F3,Net-F4,Net-F5,Net-F5b,Net-F6,Net-L05a,Net-L05b,Net-D3,Net-E15,Net-E30,Net-E60,Net-A14,Net-Fork").split(",");
const sh = (c) => execSync(c, { encoding: "utf8" }).trim();

async function main() {
  const out = { generatedAt: new Date().toISOString(), method: "block-0 stateRoot reported by a live Besu 26.9.0 node vs MPT root of the genesis.json alloc", results: {} };
  for (const net of NETS) {
    const nodes = JSON.parse(fs.readFileSync(`${ROOT}/nets/${net}/nodes-info.json`, "utf8"));
    const n1 = nodes.find((n) => n.dir === "node1");
    const g = JSON.parse(fs.readFileSync(`${ROOT}/nets/${net}/genesis.json`, "utf8"));
    const computed = allocStateRoot(g.alloc);
    const r = { computedRootOfGenesisAlloc: computed, startedForThisCheck: false };
    let up = true;
    try { await rpc(`http://127.0.0.1:${n1.rpc}`)("eth_blockNumber"); } catch { up = false; }
    if (!up) {
      r.startedForThisCheck = true;
      sh(`bash "${ROOT}/evidence/03-commands/v5-launch-net.sh" ${net} node1`);
      for (let i = 0; i < 60; i++) { await sleep(3000); try { await rpc(`http://127.0.0.1:${n1.rpc}`)("eth_blockNumber"); up = true; break; } catch { /* not yet */ } }
    }
    if (!up) { r.error = "node did not come up within 180 s"; out.results[net] = r; console.log(net, "ERROR", r.error); continue; }
    const b0 = await rpc(`http://127.0.0.1:${n1.rpc}`)("eth_getBlockByNumber", ["0x0", false]);
    r.besuBlock0 = { hash: b0.hash, stateRoot: b0.stateRoot };
    r.match = b0.stateRoot === computed;
    if (r.startedForThisCheck) { try { r.stopped = sh(`bash "${ROOT}/evidence/03-commands/v5-nodectl.sh" stop ${net} node1`); } catch (e) { r.stopError = e.message.slice(0, 120); } }
    out.results[net] = r;
    console.log(net, r.match ? "MATCH" : "DIFFERENT", computed.slice(0, 14) + "…", r.startedForThisCheck ? "(node started+stopped)" : "(already running)");
  }
  out.allMatch = Object.values(out.results).every((x) => x.match);
  saveEvidence("A14-live-stateroot.json", out);
  console.log("ALL MATCH:", out.allMatch);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
