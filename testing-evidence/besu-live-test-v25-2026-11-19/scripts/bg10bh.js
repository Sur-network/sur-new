// BG-10-BH: blockhash behaviour on Besu QBFT (Net-S). Probe contract (hand-assembled runtime, LOG0 with [blockhash(calldata n), block.number]) called in transactions
// for offsets around the 256-block horizon. (The probe part of bg10.js crashed on a nonce clash, see DEVIATIONS.md; this is its corrected re-run.)
const { Net, Checks, writeResult, ethers, GAS_PRICE, sleep } = require("./lib");

(async () => {
  const net = new Net("S", "n1");
  const c = new Checks();
  const tester = net.w("tester");
  const probeRuntime = "600035406000524360205260406000a000";
  const probeInit = "601180600b6000396000f3" + probeRuntime;
  const startNonce = await net.provider.getTransactionCount(tester.address, "pending");
  const dep = await tester.sendTransaction({ data: "0x" + probeInit, gasPrice: GAS_PRICE, type: 0, gasLimit: 200000n, nonce: startNonce });
  const depRc = await dep.wait();
  const probe = depRc.contractAddress;
  c.ok("probe contract created on Besu; runtime code as assembled", (await net.provider.getCode(probe)) === "0x" + probeRuntime, { probe, deployBlock: depRc.blockNumber });
  if ((await net.head()) < 320) await net.waitForBlock(320);
  const base = (await net.head()) + 3;
  const sent = [];
  let nonce = startNonce + 1;
  for (let off = 250; off <= 262; off++) {
    const n = base - off;
    const tx = await tester.sendTransaction({ to: probe, data: ethers.zeroPadValue(ethers.toBeHex(n), 32), gasPrice: GAS_PRICE, type: 0, gasLimit: 100000n, nonce: nonce++ });
    sent.push({ n, tx });
  }
  // a future block number and a very old one
  const fut = await tester.sendTransaction({ to: probe, data: ethers.zeroPadValue(ethers.toBeHex((await net.head()) + 500), 32), gasPrice: GAS_PRICE, type: 0, gasLimit: 100000n, nonce: nonce++ });
  const old = await tester.sendTransaction({ to: probe, data: ethers.zeroPadValue(ethers.toBeHex(1), 32), gasPrice: GAS_PRICE, type: 0, gasLimit: 100000n, nonce: nonce++ });
  const rows = [];
  for (const { n, tx } of sent) {
    const rc = await tx.wait();
    const bh = ethers.dataSlice(rc.logs[0].data, 0, 32), exec = Number(BigInt(ethers.dataSlice(rc.logs[0].data, 32, 64)));
    const real = (await net.block(n)).hash;
    rows.push({ queriedBlock: n, executedInBlock: exec, offset: exec - n, blockhashReturned: bh, realHash: real, equalsReal: bh === real, isZero: BigInt(bh) === 0n });
  }
  const futRc = await fut.wait(), oldRc = await old.wait();
  const futBh = ethers.dataSlice(futRc.logs[0].data, 0, 32), oldBh = ethers.dataSlice(oldRc.logs[0].data, 0, 32);
  const inWindow = rows.filter((r) => r.offset >= 1 && r.offset <= 256), expired = rows.filter((r) => r.offset > 256), cur = rows.filter((r) => r.offset <= 0);
  c.ok("every probe tx ran and logged", rows.length === 13, rows.map((r) => [r.offset, r.equalsReal, r.isZero]));
  c.ok("blockhash(n) inside a transaction == eth_getBlockByNumber(n).hash for 1 <= offset <= 256 (offsets seen: " + inWindow.map((r) => r.offset).join(",") + ")", inWindow.length > 0 && inWindow.every((r) => r.equalsReal));
  c.ok("blockhash(n) == 0 for offset >= 257 (offsets seen: " + expired.map((r) => r.offset).join(",") + ")", expired.length > 0 && expired.every((r) => r.isZero));
  c.ok("the 256/257 boundary was straddled (an offset of exactly 256 returned the real hash, 257 returned 0)", rows.some((r) => r.offset === 256 && r.equalsReal) && rows.some((r) => r.offset === 257 && r.isZero), rows.map((r) => [r.offset, r.equalsReal ? "hash" : r.isZero ? "zero" : "OTHER"]));
  c.ok("blockhash(current/future block) == 0 in a transaction", BigInt(futBh) === 0n && cur.every((r) => r.isZero), { futureReturned: futBh, currentOrFutureRows: cur.length });
  c.ok("blockhash(1) (very old block) == 0", BigInt(oldBh) === 0n, oldBh);
  const blk = await net.block("latest");
  c.ok("QBFT block header mixHash is the constant 'Istanbul/BFT fault tolerance' marker (not random) - why the lottery avoids prevrandao", blk.mixHash === "0x63746963616c2062797a616e74696e65206661756c7420746f6c6572616e6365", blk.mixHash);
  writeResult("BG-10-BH", { verdict: c.verdict, summary: "blockhash horizon on Besu QBFT is the standard EVM one: real hash for offsets 1..256, zero beyond and for the current/future block", checks: c.items, probe, rows, futureReturned: futBh, oldReturned: oldBh, mixHashSample: blk.mixHash });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
