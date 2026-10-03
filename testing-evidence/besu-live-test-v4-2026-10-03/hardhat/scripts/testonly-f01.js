// F01 — exact reward boundary on a COORDINATED network (Besu transition at X=300 to 3 SUR + contract history [(300, 3e18)], TEST-ONLY-SEED).
// Read-only: measures the real per-block reward around X two independent ways (empty-block balance delta; trace_block reward entries)
// and compares with the contract's rewardRateAt(). Run BEFORE any transaction is sent to the network (so every block is empty).
// env: NET_NAME (e.g. Net-F1), NET_RPC (e.g. http://127.0.0.1:8801), X (default 300)
const { ethers, ADDR, DIST_ABI, rpc, observeBlock, saveEvidence, SUR } = require("./v5-lib");

async function main() {
  const NET = process.env.NET_NAME, URL = process.env.NET_RPC, X = Number(process.env.X || 300);
  const provider = new ethers.JsonRpcProvider(URL);
  const call = rpc(URL);
  const dist = new ethers.Contract(ADDR.DISTRIBUTOR, DIST_ABI, provider);
  const head = await provider.getBlockNumber();
  const out = { NET, X, headAtStart: head, preconditions: {} };

  out.preconditions.epochCount = (await dist.epochCount()).toString();
  out.preconditions.lastSettledBlock = (await dist.lastSettledBlock()).toString();
  out.preconditions.rewardRateChangeCount = (await dist.rewardRateChangeCount()).toString();
  out.preconditions.history = [];
  for (let i = 0; i < Number(out.preconditions.rewardRateChangeCount); i++) { const [s, r] = await dist.rewardRateChange(i); out.preconditions.history.push({ startBlock: s.toString(), ratePerBlock: r.toString() }); }
  out.preconditions.transitionsInGenesis = JSON.parse(require("fs").readFileSync(`${require("./v5-lib").ROOT}/nets/${NET}/genesis.json`, "utf8")).config.transitions;
  // no transactions may have been sent by this tooling before F01 (all blocks should be empty)
  console.log("preconditions:", JSON.stringify(out.preconditions));

  const lo = Math.max(1, X - 5), hi = Math.min(head, X + 5);
  out.blocks = [];
  for (let n = lo; n <= hi; n++) {
    const o = await observeBlock(provider, call, n);
    o.contractRewardRateAt = (await dist.rewardRateAt(n)).toString();
    out.blocks.push(o);
    console.log(n, "txs:", o.txCount, "balDelta:", SUR(o.balanceDelta), "trace:", JSON.stringify(o.traceRewards), o.traceError ? "traceErr:" + o.traceError : "", "contract rate:", SUR(o.contractRewardRateAt));
  }
  // extra samples far from X (state still queryable within Bonsai's ~512-block window)
  out.samples = [];
  for (const n of [Math.max(1, X - 100), Math.min(head, X + 40)]) {
    if (n >= 1 && n <= head) { const o = await observeBlock(provider, call, n); o.contractRewardRateAt = (await dist.rewardRateAt(n)).toString(); out.samples.push(o); }
  }
  // verdict
  const firstThree = out.blocks.find((b) => BigInt(b.balanceDelta) === 3000000000000000000n);
  const lastTwo = [...out.blocks].reverse().find((b) => BigInt(b.balanceDelta) === 2000000000000000000n);
  const contractFirstThree = out.blocks.find((b) => BigInt(b.contractRewardRateAt) === 3000000000000000000n);
  out.verdict = {
    allWindowBlocksEmpty: out.blocks.every((b) => b.txCount === 0),
    besuFirstBlockPaying3: firstThree ? firstThree.n : null,
    besuLastBlockPaying2: lastTwo ? lastTwo.n : null,
    contractFirstBlockApplying3: contractFirstThree ? contractFirstThree.n : null,
    coordinated: !!firstThree && !!contractFirstThree && firstThree.n === contractFirstThree.n && lastTwo && lastTwo.n === firstThree.n - 1,
    traceBlockReturnedRewardEntries: out.blocks.some((b) => b.traceRewards && b.traceRewards.length > 0),
    traceBlockErrors: out.blocks.filter((b) => b.traceError).map((b) => ({ n: b.n, err: b.traceError })).slice(0, 3),
  };
  console.log("VERDICT:", JSON.stringify(out.verdict));
  saveEvidence(`${NET}-F01.json`, out);
}
main().catch((e) => { console.error(e); process.exitCode = 1; });
