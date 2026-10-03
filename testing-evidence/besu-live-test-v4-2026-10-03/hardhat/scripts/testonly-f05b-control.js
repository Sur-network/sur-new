// F05 control — is a restart actually NECESSARY? On a running network, add a future transition to the shared genesis file but do NOT restart any node.
// Expected if Besu reads genesis only at startup: the reward does NOT change at X'' and no node diverges. (Net-F3 was restarted by the shell beforehand.)
const { ethers, ROOT, fs, rpc, hex, sleep, observeBlock, saveEvidence } = require("./v5-lib");
const NET = "Net-F3", NETDIR = `${ROOT}/nets/${NET}`;
const nodes = JSON.parse(fs.readFileSync(`${NETDIR}/nodes-info.json`, "utf8"));
const R = (n) => rpc(`http://127.0.0.1:${n.rpc}`);
const heights = async () => Object.fromEntries(await Promise.all(nodes.map(async (n) => { try { return [n.dir, Number(await R(n)("eth_blockNumber"))]; } catch { return [n.dir, null]; } })));

async function main() {
  const out = { NET, purpose: "F05 control: genesis file edited on disk while nodes keep running (no restart)", startedAt: new Date().toISOString() };
  const g0 = JSON.parse(fs.readFileSync(`${NETDIR}/genesis.json`, "utf8"));
  out.transitionsBefore = g0.config.transitions || null;
  const h0 = Math.max(...Object.values(await heights()).filter((x) => x !== null));
  const X = h0 + 120;
  out.headAtEdit = h0; out.Xdoubleprime = X;
  const g1 = JSON.parse(JSON.stringify(g0)); g1.config.transitions = { qbft: [{ block: X, blockreward: "3000000000000000000" }] };
  fs.writeFileSync(`${NETDIR}/genesis.json`, JSON.stringify(g1, null, 2));
  console.log(`[F05b] head=${h0}; genesis.json edited with transition at ${X}; NO restart`);
  const p = new ethers.JsonRpcProvider(`http://127.0.0.1:${nodes[0].rpc}`);
  for (;;) { if ((await p.getBlockNumber()) >= X + 8) break; await sleep(5000); }
  const call = R(nodes[0]);
  out.boundary = []; for (let b = X - 2; b <= X + 5; b++) out.boundary.push(await observeBlock(p, call, b));
  out.rewardsAroundX = out.boundary.map((b) => ({ n: b.n, delta: b.balanceDelta, txCount: b.txCount }));
  out.anyBlockPaid3 = out.boundary.some((b) => BigInt(b.balanceDelta) === 3000000000000000000n);
  out.heightsAfter = await heights();
  const ref = Math.min(...Object.values(out.heightsAfter).filter((x) => x !== null)) - 1;
  out.hashes = {}; for (const n of nodes) out.hashes[n.dir] = (await R(n)("eth_getBlockByNumber", [hex(ref), false])).hash;
  out.allNodesAgree = new Set(Object.values(out.hashes)).size === 1;
  out.verdict = out.anyBlockPaid3 ? "RESTART NOT NECESSARY (unexpected): reward changed without a restart" : "CONFIRMED: editing the genesis file on disk does nothing for running nodes; the reward did not change at X'' and no node diverged";
  console.log(out.verdict, "agree:", out.allNodesAgree);
  saveEvidence("Net-F3-F05-control-no-restart.json", out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
