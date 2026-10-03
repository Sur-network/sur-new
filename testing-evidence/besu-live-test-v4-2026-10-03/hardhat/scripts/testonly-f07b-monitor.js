// F07 re-run monitor (Net-F5b): node5 runs WITHOUT the -Xmx512m cap (JVM/Besu default heap, reported by Besu at start-up as ~7.94 GB), nodes 1-4 keep the cap.
// Samples process liveness, memory, height and peers of node5 every 15 s from X-60 s to X+AFTER blocks, then records whether OutOfMemoryError / termination occurred.
const { ROOT, fs, rpc, sleep, saveEvidence } = require("./v5-lib");
const { execSync } = require("child_process");
const NET = "Net-F5b", X = 300, AFTER = Number(process.env.AFTER || 240);
const nodes = JSON.parse(fs.readFileSync(`${ROOT}/nets/${NET}/nodes-info.json`, "utf8"));
const n1 = nodes.find((n) => n.dir === "node1"), n5 = nodes.find((n) => n.dir === "node5");
const strip = (s) => s.replace(/\x1b\[[0-9;]*m/g, "");
const safe = async (f) => { try { return await f(); } catch (e) { return null; } };
function memOf(port) {
  try {
    const ps = `$c=Get-NetTCPConnection -LocalPort ${port} -State Listen -ErrorAction SilentlyContinue; if($c){$p=Get-Process -Id $c.OwningProcess; \\"$($p.Id),$([int]($p.WorkingSet64/1MB)),$([int]($p.PrivateMemorySize64/1MB))\\"}`;
    const o = execSync(`powershell -NoProfile -Command "${ps}"`, { encoding: "utf8" }).trim();
    if (!o) return null; const [pid, ws, priv] = o.split(","); return { pid: Number(pid), workingSetMB: Number(ws), privateMB: Number(priv) };
  } catch { return null; }
}
async function main() {
  const out = { NET, purpose: "F07 re-run: node5 without heap cap", startedAt: new Date().toISOString(), samples: [] };
  out.node5HeapNote = (strip(fs.readFileSync(`${ROOT}/logs/${NET}/node5.log`, "utf8")).match(/Maximum heap size: [0-9.]+ GB/) || ["(not found in log)"])[0];
  out.node1HeapNote = (strip(fs.readFileSync(`${ROOT}/logs/${NET}/node1.log`, "utf8")).match(/Maximum heap size: [0-9.]+ [GM]B/) || ["(not found)"])[0];
  let firstInvalidAt = null, deadSince = null;
  for (;;) {
    const h1 = await safe(async () => Number(await rpc(`http://127.0.0.1:${n1.rpc}`)("eth_blockNumber")));
    if (h1 !== null && h1 >= X - 20) {
      const h5 = await safe(async () => Number(await rpc(`http://127.0.0.1:${n5.rpc}`)("eth_blockNumber")));
      const peers5 = await safe(async () => Number(await rpc(`http://127.0.0.1:${n5.rpc}`)("net_peerCount")));
      const m = memOf(n5.rpc);
      const s = { t: new Date().toISOString(), head_node1: h1, head_node5: h5, peers_node5: peers5, node5Process: m };
      out.samples.push(s);
      console.log(JSON.stringify(s));
      if (!firstInvalidAt && /Invalid block 300/.test(fs.readFileSync(`${ROOT}/logs/${NET}/node5.log`, "utf8"))) firstInvalidAt = s.t;
      if (!m) { deadSince = deadSince || s.t; if (Date.now() - Date.parse(deadSince) > 60000) break; } else deadSince = null;
      if (h1 >= X + AFTER) break;
    }
    await sleep(15000);
  }
  const log = strip(fs.readFileSync(`${ROOT}/logs/${NET}/node5.log`, "utf8")).split("\n");
  const pick = (re, max) => log.filter((l) => re.test(l)).slice(0, max).map((l) => l.replace(/\r/g, "").slice(0, 400));
  out.node5Log = { invalidBlock300: pick(/Invalid block 300|stateroot mismatch/, 3), outOfMemory: pick(/OutOfMemoryError|Terminating due to/, 3), roundOrPeerLines: pick(/BREACH_OF_PROTOCOL|Waiting for 5 peers/, 2) };
  out.firstInvalidBlock300Seen = firstInvalidAt;
  const last = out.samples[out.samples.length - 1] || {};
  out.node5ProcessAliveAtEnd = !!last.node5Process;
  out.peakWorkingSetMB = Math.max(0, ...out.samples.map((s) => (s.node5Process ? s.node5Process.workingSetMB : 0)));
  out.peakPrivateMB = Math.max(0, ...out.samples.map((s) => (s.node5Process ? s.node5Process.privateMB : 0)));
  out.outOfMemoryErrorOccurred = out.node5Log.outOfMemory.length > 0;
  out.finishedAt = new Date().toISOString();
  console.log("OOM occurred:", out.outOfMemoryErrorOccurred, "alive at end:", out.node5ProcessAliveAtEnd, "peak WS MB:", out.peakWorkingSetMB);
  saveEvidence("Net-F5b-F07b-monitor.json", out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
