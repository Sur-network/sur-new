// BG-03 setOperator swap of an ACTIVE validator to a new node key (Net-A, n=7).
//  Part A: owner2 -> op2b with the new node n2b already running and synced.
//  Part B: owner3 -> op3b with the new node n3b NOT running (record behaviour), then n3b is started.
const { Net, Checks, writeResult, ethers, send, expectRevert, sleep, sealSigners, findEvent, ifaceOf, ctl, sameSet, minerSeries, gapsOf, waitSynced } = require("./lib");

(async () => {
  const net = new Net("A", "n1");
  const reg = net.c("REG");
  const c = new Checks();
  const op = (n) => net.addr(n), own = (i) => net.addr("owner" + i);
  const before = Array.from(await reg.getValidators());
  c.ok("start: 7 validators (operators of owners 1..7)", before.length === 7 && sameSet(before, [1, 2, 3, 4, 5, 6, 7].map((i) => op("op" + i))), before);

  // ---------------- Part A
  ctl("start", "A", "n2b");
  const sync = await waitSynced(net, "n2b");
  c.ok("n2b (new node) running and synced before the swap", true, sync);
  const neg = {};
  neg.sameOperator = await expectRevert(net, "owner2", "REG", "setOperator", [op("op2")]);
  neg.operatorOfOtherOwner = await expectRevert(net, "owner2", "REG", "setOperator", [op("op4")]);
  neg.ownerKeyOfOther = await expectRevert(net, "owner2", "REG", "setOperator", [own(4)]);
  neg.notAValidator = await expectRevert(net, "outsider", "REG", "setOperator", [op("op2b")]);
  for (const [k, v] of Object.entries(neg)) c.ok(`negative: ${k} reverts`, v.reverted, v.reason);
  const swap = await send(net, "owner2", "REG", "setOperator", [op("op2b")]);
  const B = swap.block;
  const oset = findEvent(swap.receipt, ifaceOf("REG"), "OperatorSet")[0];
  c.ok("OperatorSet(owner2, op2b) emitted; gas used " + swap.gasUsed, oset.args.owner === own(2) && oset.args.operator === op("op2b"));
  c.ok("operatorOf(owner2)==op2b; ownerOfOperator(op2b)==owner2; old op2 stays attached to owner2 forever", (await reg.operatorOf(own(2))) === op("op2b") && (await reg.ownerOfOperator(op("op2b"))) === own(2) && (await reg.ownerOfOperator(op("op2"))) === own(2));
  const afterList = Array.from(await reg.getValidators());
  const expectA = [op("op1"), op("op2b"), op("op3"), op("op4"), op("op5"), op("op6"), op("op7")];
  c.ok("getValidators(): op2 replaced by op2b, owner list unchanged", sameSet(afterList, expectA) && (await reg.getActiveOwners()).length === 7, afterList);
  c.ok("status of owner2 still Active (2)", Number((await reg.validators(own(2))).status) === 2);
  const oldRe = await expectRevert(net, "owner3", "REG", "setOperator", [op("op2")]);
  c.ok("negative: the retired operator key cannot be claimed by another owner", oldRe.reverted, oldRe.reason);
  await net.waitForBlock(B + 20);
  const series = await minerSeries(net, B - 6, B + 20);
  const q = {}; for (const n of [B - 1, B, B + 1]) q[n] = (await net.qbftValidators(n)).map(ethers.getAddress);
  c.ok("QBFT set switches at the swap block (set at B-1 has op2, set at B has op2b)", Array.isArray(q[B - 1]) && q[B - 1].some((a) => a === op("op2")) && sameSet(q[B], expectA), q);
  const after = series.filter((s) => s.block > B);
  const firstNew = after.find((s) => s.miner === op("op2b"));
  const lastOldBefore = series.filter((s) => s.block <= B && s.miner === op("op2")).pop();
  c.ok("op2 never mines after the swap block; op2b mines within the next 20 blocks", !after.some((s) => s.miner === op("op2")) && !!firstNew, { swapBlock: B, firstBlockByOp2b: firstNew && firstNew.block, lastBlockByOp2: lastOldBefore && lastOldBefore.block });
  c.ok("no gap > 4 s around the swap (no halt) while the old node n2 is still running", gapsOf(series).every((g) => g <= 4), gapsOf(series));
  const sealA = []; for (const n of [B + 18, B + 19, B + 20]) sealA.push(await sealSigners(net, n, expectA));
  c.ok("recovered seal signers of later blocks are all in the new operator set (op2 never signs)", sealA.every((s) => s.signers && !s.signers.includes(op("op2"))), sealA.map((s) => s.signers));
  // stop the old node n2: chain unaffected
  ctl("stop", "A", "n2");
  await net.waitBlocks(14);
  const s2 = await minerSeries(net, (await net.head()) - 13, await net.head());
  c.ok("old node n2 stopped: 14 more blocks, no slow round (gaps <= 4 s), old operator was not needed", gapsOf(s2).every((g) => g <= 4), gapsOf(s2));
  const partA = { swapBlock: B, tx: swap.hash, gasUsed: swap.gasUsed, qbftSets: q, firstBlockByNewOperator: firstNew && firstNew.block, lastBlockByOldOperator: lastOldBefore && lastOldBefore.block, series };

  // ---------------- Part B: swap to a node that is NOT running
  await net.waitBlocks(2);
  const hB0 = await net.head();
  const swapB = await send(net, "owner3", "REG", "setOperator", [op("op3b")]);
  const B2 = swapB.block;
  c.ok("owner3 -> op3b accepted by the contract although n3b is not running (the contract cannot know)", sameSet(Array.from(await reg.getValidators()), [op("op1"), op("op2b"), op("op3b"), op("op4"), op("op5"), op("op6"), op("op7")]));
  await net.waitForBlock(B2 + 28);
  const sB = await minerSeries(net, B2 - 2, B2 + 28);
  const gB = gapsOf(sB);
  const slow = gB.filter((g) => g > 4);
  c.ok("n3b absent (6 of 7 live >= quorum 5): chain keeps producing; rounds where op3b is proposer show round-change delays (~12 s)", (await net.head()) >= B2 + 28 && slow.length >= 1, { gaps: gB, slowGaps: slow });
  c.ok("op3 (old key) does not mine after the swap; op3b does not mine while down", !sB.filter((s) => s.block > B2).some((s) => s.miner === op("op3") || s.miner === op("op3b")));
  ctl("start", "A", "n3b");
  const syncB = await waitSynced(net, "n3b", 3);
  const hStart = await net.head();
  await net.waitForBlock(hStart + 40);
  const sB2 = await minerSeries(net, hStart, hStart + 40);
  const firstB = sB2.find((s) => s.miner === op("op3b"));
  c.ok("n3b started later: synced and mines blocks as op3b", !!firstB, { syncedAtHead: syncB.head, firstBlockByOp3b: firstB && firstB.block });
  c.ok("after n3b joined: gaps back to ~2 s", gapsOf(sB2.filter((s) => s.block >= (firstB ? firstB.block : 0))).every((g) => g <= 4), gapsOf(sB2));
  const partB = { swapBlock: B2, tx: swapB.hash, gapsWhileNodeDown: gB, slowGaps: slow, seriesWhileDown: sB, n3bStartedAtHead: hStart, firstBlockByOp3b: firstB && firstB.block };

  const finalList = Array.from(await reg.getValidators());
  c.ok("end: validator list = op1, op2b, op3b, op4, op5, op6, op7 and equals the QBFT set", sameSet(finalList, [op("op1"), op("op2b"), op("op3b"), op("op4"), op("op5"), op("op6"), op("op7")]) && sameSet((await net.qbftValidators("latest")).map(ethers.getAddress), finalList), finalList);
  writeResult("BG-03", { verdict: c.verdict, summary: "swap with the new node running: clean cut-over at the swap block; swap to a node that is down: no halt at n=7, 12 s round changes while down", checks: c.items, negatives: neg, partA, partB });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
