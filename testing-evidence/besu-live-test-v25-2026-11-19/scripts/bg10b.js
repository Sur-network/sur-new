// BG-10b ValidatorLottery cancel path on Net-L2: CEO commits but never reveals; the 250-block reveal window (about 8.3 minutes at 2 s blocks)
// passes; reveal reverts, anyone cancels, every buyer pulls a full refund.
const { Net, Checks, writeResult, ethers, send, expectRevert, sleep, S, findEvent, ifaceOf, ADDR } = require("./lib");
const { startLotteryViaDao, makeManyFullyVerified } = require("./lib-lottery");

(async () => {
  const net = new Net("L2", "n1");
  const c = new Checks();
  const t0 = Date.now();
  const lot = net.c("LOTTERY");
  const timeline = {};
  const stamp = async (k) => { timeline[k] = { wallClockUTC: new Date().toISOString(), block: await net.head() }; };
  await stamp("start");
  const roles = ["lot1", "lot2", "lot3"];
  await makeManyFullyVerified(net, roles);
  const price = S(10);
  const st = await startLotteryViaDao(net, price, 2, 90);
  c.ok("StartLottery executed with 3 of 5 votes", st.statusAfterThree === 1 && st.votesAfterThree === 3, st);
  for (const r of roles) await send(net, r, "LOTTERY", "buyTicket", [], { value: price });
  const balBuyers = {}; for (const r of roles) balBuyers[r] = await net.balance(net.addr(r));
  const secret = ethers.hexlify(ethers.randomBytes(32));
  await send(net, "ceo", "LOTTERY", "commitSecret", [ethers.keccak256(secret)]);
  await stamp("committed");
  for (;;) { const b = await net.block("latest"); if (Number(BigInt(b.timestamp)) >= st.closeTime) break; await sleep(500); }
  const cl = await send(net, "tester", "LOTTERY", "closeLottery", []);
  const target = Number(findEvent(cl.receipt, ifaceOf("LOTTERY"), "LotteryClosed")[0].args.targetBlock);
  await stamp("closed");
  const cancelEarly = await expectRevert(net, "tester", "LOTTERY", "cancelLottery", []);
  c.ok("negative: cancelLottery inside the window reverts", cancelEarly.reverted, cancelEarly.reason);
  const dr = await expectRevert(net, "tester", "LOTTERY", "drawBatch", [1]);
  c.ok("negative: drawBatch while Closed reverts", dr.reverted, dr.reason);
  // wait for the window to end: block > target + 250
  const lastOk = target + 250;
  await net.waitForBlock(lastOk); // still inside the window at block lastOk (reveal in block lastOk is allowed)
  const stillOpen = await net.c("LOTTERY").reveal.staticCall(secret, { from: net.addr("ceo") }).then(() => "eth_call at head==target+250 would pass (window still open)").catch((e) => "reverted: " + (e.reason || e.shortMessage));
  await net.waitForBlock(lastOk + 1);
  const late = await expectRevert(net, "ceo", "LOTTERY", "reveal", [secret]);
  c.ok("reveal after the window reverts (CEO did not reveal in time)", late.reverted, late.reason);
  const cancelAfter = await send(net, "tester", "LOTTERY", "cancelLottery", []);
  const L = await lot.getLottery(1);
  c.ok("lottery Cancelled (phase 5)", Number(L.phase) === 5, Number(L.phase));
  const evs = findEvent(cancelAfter.receipt, ifaceOf("LOTTERY"), "LotteryCancelled");
  c.ok("LotteryCancelled event emitted", evs.length === 1, evs[0] && evs[0].args.reason);
  await stamp("cancelled");
  const refunds = [];
  for (const r of roles) {
    const before = await net.balance(net.addr(r));
    const x = await send(net, r, "LOTTERY", "claimRefund", [1]);
    const after = await net.balance(net.addr(r));
    const gasCost = x.receipt.gasUsed * x.receipt.gasPrice;
    refunds.push({ r, netChange: (after - before + gasCost).toString(), gasCost: gasCost.toString() });
    c.ok(`${r} refund == ticket price (excluding gas)`, after - before + gasCost === price, { net: (after - before + gasCost).toString() });
  }
  const twice = await expectRevert(net, "lot1", "LOTTERY", "claimRefund", [1]);
  c.ok("negative: second refund claim reverts", twice.reverted, twice.reason);
  c.ok("lottery contract balance 0 after all refunds", (await net.balance(ADDR.LOTTERY)) === 0n);
  const wallSeconds = Math.round((Date.now() - t0) / 1000);
  writeResult("BG-10b", { verdict: c.verdict, summary: `cancel path: close block ${cl.block}, target ${target}, cancel block ${cancelAfter.block} (window = ${cancelAfter.block - target} blocks after target)`, checks: c.items, timeline, wallSeconds, target, cancelBlock: cancelAfter.block, revealEvalAtTargetPlus250: stillOpen, refunds });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
