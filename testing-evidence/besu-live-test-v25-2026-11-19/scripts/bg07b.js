// BG-07b: repeat of BG-07 "case 2" (removal -> objection -> board cancels -> reinstated into the QBFT set) with a CORRECTED expectation.
// Reason: in bg07.js the check "buyer reinstated ..." compared the list with without6.concat([op7]) although `without6` already contained op7
// (script bug, see DEVIATIONS.md); the chain state itself was what the later checks of that run show. Here the expected lists are explicit.
const { Net, Checks, writeResult, ethers, send, expectRevert, findEvent, ifaceOf, sameSet, minerSeries, gapsOf } = require("./lib");

(async () => {
  const net = new Net("A", "n1");
  const reg = net.c("REG");
  const c = new Checks();
  const op = (n) => net.addr(n), buyer = net.addr("buyer");
  const R = ifaceOf("REG");
  const before = Array.from(await reg.getValidators());
  const expectedBefore = ["op1", "op2b", "op3b", "op4", "op5", "op7"].map(op);
  c.ok("start: 6 validators = op1, op2b, op3b, op4, op5, op7 (op6 removed in BG-07 case 1)", sameSet(before, expectedBefore), before);
  const expectedWithout7 = ["op1", "op2b", "op3b", "op4", "op5"].map(op);
  const ts = Number(BigInt((await net.block("latest")).timestamp));
  const rec = await send(net, "verifier", "REG", "recordRecoveryRemoval", [buyer, ts - 60, ethers.keccak256(ethers.toUtf8Bytes("evidence case 2b"))]);
  c.ok("buyer removed: status RemovedInRecovery (5), list = 5 operators without op7", Number((await reg.validators(buyer)).status) === 5 && sameSet(Array.from(await reg.getValidators()), expectedWithout7), { block: rec.block });
  await net.waitForBlock(rec.block + 6);
  const q = (await net.qbftValidators(rec.block)).map(ethers.getAddress);
  c.ok("QBFT set at the removal block == the 5 operators (n=5, f=1, quorum 4)", sameSet(q, expectedWithout7), q);
  await send(net, "buyer", "REG", "objectRecoveryRemoval", []);
  let last;
  for (const i of [1, 2, 3]) last = await send(net, "owner" + i, "BOARD", "voteRecoveryRemoval", [buyer, false]);
  const B = last.block;
  c.ok("3 board votes to cancel -> Registry case Cancelled (5); RecoveryRemovalCancelled(expired=false) emitted", Number((await reg.recoveryCaseInfo(buyer)).state) === 5 && findEvent(last.receipt, R, "RecoveryRemovalCancelled").length === 1 && findEvent(last.receipt, R, "RecoveryRemovalCancelled")[0].args.expired === false, { block: B });
  const vb = await reg.validators(buyer);
  const after = Array.from(await reg.getValidators());
  c.ok("buyer Active (2), permanentlyExited cleared, op7 back: list == the 6 operators incl. op7", Number(vb.status) === 2 && !(await reg.permanentlyExited(buyer)) && sameSet(after, expectedBefore), after);
  await net.waitForBlock(B + 20);
  const q2 = (await net.qbftValidators(B)).map(ethers.getAddress);
  const ser = await minerSeries(net, B - 8, B + 20);
  const first7 = ser.find((s) => s.block > B && s.miner === op("op7"));
  c.ok("QBFT set at the cancel block == 6 operators; op7 mines again; no gap > 4 s", sameSet(q2, expectedBefore) && !!first7 && gapsOf(ser).every((g) => g <= 4), { firstBlockByOp7: first7 && first7.block });
  writeResult("BG-07b", { verdict: c.verdict, summary: "case 2 repeated with the corrected expectation: removal, objection, board cancel, reinstatement", checks: c.items, removalTx: rec.hash, cancelBlock: B });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
