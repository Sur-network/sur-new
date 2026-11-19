// BG-13 (extra) Halt and resume in contract mode (Net-A): 3 of the 6 active validators are stopped at once (6 validators need 4) -> chain halts;
// a transaction sent during the halt stays pending; the 3 nodes are started again -> chain resumes with the same contract-defined set; the pending tx is mined.
const { Net, Checks, writeResult, ethers, sleep, ctl, sameSet, minerSeries, gapsOf, decodeExtra, GAS_PRICE } = require("./lib");

(async () => {
  const net = new Net("A", "n1");
  const reg = net.c("REG");
  const c = new Checks();
  const act = ["op1", "op2b", "op3b", "op4", "op5", "op7"].map((n) => net.addr(n));
  const before = Array.from(await reg.getValidators());
  c.ok("start: 6 validators (op1, op2b, op3b, op4, op5, op7)", sameSet(before, act), before.length);
  const h0 = await net.head();
  const tStop = Date.now();
  for (const n of ["n4", "n5", "n7"]) ctl("stop", "A", n);
  await sleep(6000);
  const hStopped = await net.head();
  await sleep(40000);
  const hLater = await net.head();
  c.ok("chain halts with 3 of 6 validators down (head did not advance in 40 s; at most the in-flight block)", hLater - hStopped <= 1, { hAtStop: h0, hAfterStop: hStopped, hAfter40s: hLater });
  c.ok("reads still work during the halt: getValidators() unchanged (6)", sameSet(Array.from(await reg.getValidators()), act));
  // a transaction during the halt
  const w = net.w("tester");
  const nonce = await net.provider.getTransactionCount(w.address, "pending");
  const tx = await w.sendTransaction({ to: net.addr("spendTo"), value: 1n, gasPrice: GAS_PRICE, type: 0, gasLimit: 21000n, nonce });
  await sleep(8000);
  const pend = await net.provider.send("txpool_besuTransactions", []).catch(() => null);
  const rc0 = await net.provider.getTransactionReceipt(tx.hash);
  c.ok("transaction sent during the halt is not mined (no receipt)", rc0 === null, { tx: tx.hash, txpoolEntries: Array.isArray(pend) ? pend.length : "n/a" });
  const tStart = Date.now();
  for (const n of ["n4", "n5", "n7"]) ctl("start", "A", n);
  let resumedAt = null; const hBefore = await net.head();
  for (let i = 0; i < 240; i++) { if ((await net.head()) > hBefore) { resumedAt = Date.now(); break; } await sleep(500); }
  c.ok("chain resumes after the 3 nodes are started (first new block seen)", !!resumedAt, { secondsFromStartCommand: resumedAt ? Math.round((resumedAt - tStart) / 1000) : null });
  const rc = await tx.wait();
  c.ok("the pending transaction is mined after the resume", rc.status === 1, { block: rc.blockNumber, secondsFromStartCommand: Math.round((Date.now() - tStart) / 1000) });
  await net.waitForBlock((await net.head()) + 20);
  const hNow = await net.head();
  const ser = await minerSeries(net, hBefore, hNow);
  const rounds = []; for (let n = hBefore + 1; n <= Math.min(hBefore + 6, hNow); n++) { const b = await net.block(n); rounds.push({ block: n, round: decodeExtra(b.extraData).round }); }
  c.ok("after the resume the contract-defined set is unchanged and equals the QBFT set", sameSet(Array.from(await reg.getValidators()), act) && sameSet((await net.qbftValidators("latest")).map(ethers.getAddress), act));
  const gaps = gapsOf(ser);
  c.ok("block times return to 2 s within the next 20 blocks", gaps.slice(-10).every((g) => g <= 4), gaps.slice(-10));
  const all = await Promise.all(["n1", "n2b", "n3b", "n4", "n5", "n7"].map(async (n) => [n, await net.at(n).head()]));
  c.ok("all six validator nodes agree on the head (within 2)", Math.max(...all.map((x) => x[1])) - Math.min(...all.map((x) => x[1])) <= 2, all);
  writeResult("BG-13", { verdict: c.verdict, summary: "halt with <quorum and resume in QBFT contract mode: set unchanged, pending tx mined", checks: c.items, haltSeconds: Math.round((tStart - tStop) / 1000), firstBlocksAfterResume: ser.slice(0, 8), roundsOfFirstBlocksAfterResume: rounds, gapsAfterResume: gaps });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
