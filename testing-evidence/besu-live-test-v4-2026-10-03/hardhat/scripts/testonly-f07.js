// F07 (optional) — Net-F5: ONE of five validators (node5 = g5_v5) runs a config WITHOUT the reward transition; the other four have X=300 -> 3 SUR.
// Observation only (no transactions are sent): network behaviour at and after X (round change / halt / fork), node5's own view, logs.
// env: AFTER (default 60) blocks past X to wait for.
const { ethers, ROOT, fs, rpc, hex, sleep, observeBlock, saveEvidence } = require("./v5-lib");
const NET = process.env.NET_NAME || "Net-F5", X = 300;
const nodes = JSON.parse(fs.readFileSync(`${ROOT}/nets/${NET}/nodes-info.json`, "utf8"));
const R = (n) => rpc(`http://127.0.0.1:${n.rpc}`);
const safe = async (f) => { try { return await f(); } catch (e) { return `ERR: ${e.message}`; } };
const strip = (s) => s.replace(/\x1b\[[0-9;]*m/g, "");

async function main() {
  const AFTER = Number(process.env.AFTER || 60);
  const out = { NET, X, startedAt: new Date().toISOString(), nodeConfigs: {} };
  for (const n of nodes) out.nodeConfigs[n.dir] = { genesisFile: fs.readFileSync(`${ROOT}/nets/${NET}/${n.dir}/config.toml`, "utf8").match(/genesis-file="([^"]+)"/)[1] };
  // wait for the healthy view to pass X + AFTER
  const healthy = nodes[0];
  const p = new ethers.JsonRpcProvider(`http://127.0.0.1:${healthy.rpc}`);
  for (;;) { const h = await safe(() => p.getBlockNumber()); if (typeof h === "number" && h >= X + AFTER) break; await sleep(5000); }
  out.heights = {}; for (const n of nodes) out.heights[n.dir] = await safe(async () => Number(await R(n)("eth_blockNumber")));
  out.peerCounts = {}; for (const n of nodes) out.peerCounts[n.dir] = await safe(async () => Number(await R(n)("net_peerCount")));
  // block hashes at selected heights on every node
  const sampleHeights = [X - 2, X - 1, X, X + 1, X + 2, X + 10, X + AFTER - 5];
  out.hashes = {};
  for (const h of sampleHeights) { out.hashes[h] = {}; for (const n of nodes) out.hashes[h][n.dir] = await safe(async () => (await R(n)("eth_getBlockByNumber", [hex(h), false]))?.hash || null); }
  out.hashAgreementAmongHealthyFour = {}; for (const h of sampleHeights) out.hashAgreementAmongHealthyFour[h] = new Set(["node1", "node2", "node3", "node4"].map((d) => out.hashes[h][d])).size === 1;
  out.node5AgreesWithHealthy = {}; for (const h of sampleHeights) out.node5AgreesWithHealthy[h] = out.hashes[h]["node5"] === out.hashes[h]["node1"];
  // reward at the boundary as seen by the healthy nodes
  const call = R(healthy);
  out.boundaryHealthyView = [];
  for (let b = X - 2; b <= X + 3; b++) out.boundaryHealthyView.push(await safe(() => observeBlock(p, call, b)));
  // who produced blocks after X (is node5 still proposing?)
  out.minersAfterX = {};
  for (let b = X; b <= X + AFTER - 2; b++) { const blk = await safe(async () => await R(healthy)("eth_getBlockByNumber", [hex(b), false])); if (blk && blk.miner) out.minersAfterX[blk.miner] = (out.minersAfterX[blk.miner] || 0) + 1; }
  out.node5Addr = nodes.find((n) => n.dir === "node5").address;
  out.blockTimesAroundX = [];
  for (let b = X - 3; b <= X + 12; b++) { const blk = await safe(async () => await R(healthy)("eth_getBlockByNumber", [hex(b), false])); if (blk && blk.timestamp) out.blockTimesAroundX.push({ n: b, ts: Number(blk.timestamp), miner: blk.miner }); }
  for (let i = 1; i < out.blockTimesAroundX.length; i++) out.blockTimesAroundX[i].gapSeconds = out.blockTimesAroundX[i].ts - out.blockTimesAroundX[i - 1].ts;
  // node logs: lines mentioning the divergence (grep-like extract from node5 + one healthy node)
  const grep = (node, re, max = 25) => strip(fs.readFileSync(`${ROOT}/logs/${NET}/${node}.log`, "utf8")).split("\n").filter((l) => re.test(l)).slice(0, max).map((l) => l.slice(0, 400));
  out.logExtracts = { node5_problems: grep("node5", /(ERROR|WARN|Invalid|invalid|mismatch|failed|Failed|reject|round|Round)/i), node1_problems: grep("node1", /(ERROR|WARN|Invalid|invalid|mismatch|reject|round change|RoundChange)/i, 15) };
  out.finishedAt = new Date().toISOString();
  console.log(JSON.stringify({ heights: out.heights, node5AgreesWithHealthy: out.node5AgreesWithHealthy, healthyAgree: out.hashAgreementAmongHealthyFour, minersAfterX: out.minersAfterX }, null, 1));
  saveEvidence(`${NET}-F07.json`, out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
