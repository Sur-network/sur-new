// BH-07b Recovery removal with board votes on the live chain after the new board rule (Net-A, n=7, all five board founders activated).
// Case 1: owner7's node n7 is shut down, the Verifier records the removal, owner7 objects, 3 board votes uphold (owners 1,2,3).
// Case 2: the buyer (owner of seat 6, operator op6, node n6 running) is removed, objects, 3 board votes cancel (owners 1,2,3), reinstated.
// The 90-day lock and the 7-day expiry cannot elapse on Besu: NOT-RUN (only the refusals before the deadline are checked).
const { Net, Checks, writeResult, ethers, send, expectRevert, sleep, findEvent, ifaceOf, sameSet, minerSeries, gapsOf, ctl } = require("./lib");

(async () => {
  const net = new Net("A", "n1");
  const reg = net.c("REG"), board = net.c("BOARD");
  const c = new Checks();
  const op = (n) => net.addr(n), own = (i) => net.addr("owner" + i);
  const buyer = net.addr("buyer");
  const R = ifaceOf("REG");
  const full = Array.from(await reg.getValidators());
  c.ok("start: 7 validators incl. op6 (owned by the buyer) and op7", full.length === 7 && full.includes(op("op6")) && full.includes(op("op7")) && (await reg.ownerOfOperator(op("op6"))) === buyer, full);
  const nowTs = async () => Number(BigInt((await net.block("latest")).timestamp));
  const members = Array.from(await board.getBoardMembers());
  const auths = await Promise.all([1, 2, 3, 4, 5].map((i) => board.hasBoardAuthority(own(i))));
  c.ok("board == owner1..owner5 and all five have authority (all activated)", sameSet(members, [1, 2, 3, 4, 5].map(own)) && auths.every((x) => x), { members, auths });

  const ts = await nowTs();
  const neg = {};
  neg.notVerifier = await expectRevert(net, "outsider", "REG", "recordRecoveryRemoval", [own(7), ts - 60, ethers.keccak256("0x01")]);
  neg.emptyHash = await expectRevert(net, "verifier", "REG", "recordRecoveryRemoval", [own(7), ts - 60, ethers.ZeroHash]);
  neg.future = await expectRevert(net, "verifier", "REG", "recordRecoveryRemoval", [own(7), ts + 3600, ethers.keccak256("0x01")]);
  neg.tooOld = await expectRevert(net, "verifier", "REG", "recordRecoveryRemoval", [own(7), ts - 31 * 86400, ethers.keccak256("0x01")]);
  neg.notActive = await expectRevert(net, "verifier", "REG", "recordRecoveryRemoval", [net.addr("cand"), ts - 60, ethers.keccak256("0x01")]);
  for (const [k, v] of Object.entries(neg)) c.ok(`negative: ${k} reverts`, v.reverted, v.reason);

  // ---- case 1
  ctl("stop", "A", "n7");
  await net.waitBlocks(10);
  const metrics = await net.provider.send("qbft_getSignerMetrics", []);
  const evidenceHash = ethers.keccak256(ethers.toUtf8Bytes(JSON.stringify(metrics)));
  const recoveryTs = (await nowTs()) - 120;
  const rec = await send(net, "verifier", "REG", "recordRecoveryRemoval", [own(7), recoveryTs, evidenceHash]);
  const B = rec.block;
  const recEv = findEvent(rec.receipt, R, "RecoveryRemovalRecorded")[0];
  c.ok("RecoveryRemovalRecorded(owner7, recoveryTimestamp, evidenceHash, exitAllowedAt = recoveryTimestamp + 90 days)", !!recEv && Number(recEv.args.exitAllowedAt) === recoveryTs + 90 * 86400 && recEv.args.evidenceHash === evidenceHash, { gasUsed: rec.gasUsed, block: B });
  const v7 = await reg.validators(own(7));
  c.ok("owner7 status RemovedInRecovery (5); permanentlyExited true; membershipEpoch 1; collateral untouched (founder 0)", Number(v7.status) === 5 && (await reg.permanentlyExited(own(7))) && (await reg.membershipEpoch(own(7))) === 1n && v7.lockedStake === 0n);
  const without7 = full.filter((a) => a !== op("op7"));
  c.ok("op7 removed from getValidators() while the chain runs (n=6)", sameSet(Array.from(await reg.getValidators()), without7));
  await net.waitForBlock(B + 16);
  const q = {}; for (const n of [B - 1, B]) q[n] = (await net.qbftValidators(n)).map(ethers.getAddress);
  const ser = await minerSeries(net, B - 5, B + 16);
  c.ok("QBFT set: op7 in at B-1, out at B; blocks keep coming with gaps <= 4 s after the removal", q[B - 1].includes(op("op7")) && sameSet(q[B], without7) && gapsOf(ser.filter((s) => s.block >= B)).every((g) => g <= 4), { gapsBeforeAndAfter: gapsOf(ser), block: B });
  const info = await reg.recoveryCaseInfo(own(7));
  c.ok("recoveryCaseInfo: state Recorded (1), objection deadline = recordedAt + 72 h", Number(info.state) === 1 && Number((await reg.recoveryRemovals(own(7))).objectionDeadline) === Number(info.recordedAt) + 72 * 3600, { recordedAt: Number(info.recordedAt) });
  const dup = await expectRevert(net, "verifier", "REG", "recordRecoveryRemoval", [own(7), recoveryTs, evidenceHash]);
  c.ok("negative: second record for the same validator reverts", dup.reverted, dup.reason);
  const exitEarly = await expectRevert(net, "owner7", "REG", "requestExit", []);
  c.ok("negative: requestExit while the case is open reverts", exitEarly.reverted, exitEarly.reason);
  // a board vote before the objection: no open board case yet
  const voteEarly = await expectRevert(net, "owner1", "BOARD", "voteRecoveryRemoval", [own(7), true]);
  c.ok("negative: a board vote before the objection reverts ('no open board case')", voteEarly.reverted && /no open board case/.test(voteEarly.reason || ""), voteEarly.reason);

  const obj = await send(net, "owner7", "REG", "objectRecoveryRemoval", []);
  const info2 = await reg.recoveryCaseInfo(own(7));
  c.ok("objectRecoveryRemoval: state Objected (2), 7-day decision window opened", Number(info2.state) === 2 && Number(info2.resolutionDeadline) - Number(BigInt((await net.block(obj.block)).timestamp)) === 7 * 86400);
  const objTwice = await expectRevert(net, "owner7", "REG", "objectRecoveryRemoval", []);
  c.ok("negative: objecting twice reverts", objTwice.reverted, objTwice.reason);
  const expireEarly = await expectRevert(net, "tester", "REG", "expireRecoveryRemoval", [own(7)]);
  c.ok("negative: expireRecoveryRemoval before the 7 days reverts (the expiry itself is NOT-RUN)", expireEarly.reverted, expireEarly.reason);
  const referEarly = await expectRevert(net, "tester", "BOARD", "referRecoveryRemovalToAssembly", [own(7)]);
  c.ok("negative: referral to the validators refused while >= 3 impartial board members can act (five can)", referEarly.reverted && /enough impartial board members/.test(referEarly.reason || ""), referEarly.reason);
  const nonMember = await expectRevert(net, "buyer", "BOARD", "voteRecoveryRemoval", [own(7), true]);
  c.ok("negative: a non-board member cannot vote", nonMember.reverted, nonMember.reason);
  const subjectVote = await expectRevert(net, "owner7", "BOARD", "voteRecoveryRemoval", [own(7), false]);
  c.ok("negative: the subject (owner7) cannot vote", subjectVote.reverted, subjectVote.reason);
  const directResolve = await expectRevert(net, "verifier", "REG", "resolveRecoveryRemoval", [own(7), true]);
  c.ok("negative: resolveRecoveryRemoval only callable by the ValidatorsBoard contract", directResolve.reverted, directResolve.reason);

  const votes = [];
  for (const i of [1, 2, 3]) {
    const v = await send(net, "owner" + i, "BOARD", "voteRecoveryRemoval", [own(7), true]);
    const ev = findEvent(v.receipt, ifaceOf("BOARD"), "RecoveryRemovalVote")[0];
    votes.push({ voter: "owner" + i, tx: v.hash, gasUsed: v.gasUsed, upholdVotes: Number(ev.args.upholdVotes) });
    if (i === 2) c.ok("after 2 uphold votes the case is still Objected (2)", Number((await reg.recoveryCaseInfo(own(7))).state) === 2);
  }
  const info3 = await reg.recoveryCaseInfo(own(7));
  c.ok("3rd board vote upholds: Registry state Upheld (4); status stays RemovedInRecovery; op7 stays out", Number(info3.state) === 4 && Number((await reg.validators(own(7))).status) === 5 && sameSet(Array.from(await reg.getValidators()), without7), { votes });
  const dupVote = await expectRevert(net, "owner4", "BOARD", "voteRecoveryRemoval", [own(7), true]);
  c.ok("negative: a vote after the case is decided reverts", dupVote.reverted, dupVote.reason);
  const exitLock = await expectRevert(net, "owner7", "REG", "requestExit", []);
  c.ok("negative: requestExit after the case, before recoveryTimestamp + 90 days, reverts (90-day lock; the elapsed part is NOT-RUN)", exitLock.reverted && /90 days/.test(exitLock.reason || ""), exitLock.reason);

  // ---- case 2: the buyer (op6, node n6 running) is removed, objects, the board cancels
  const ts2 = await nowTs();
  const rec2 = await send(net, "verifier", "REG", "recordRecoveryRemoval", [buyer, ts2 - 60, ethers.keccak256(ethers.toUtf8Bytes("evidence case 2"))]);
  const without67 = without7.filter((a) => a !== op("op6"));
  c.ok("case 2: buyer removed: status RemovedInRecovery (5), list = 5 operators (op6 and op7 out)", Number((await reg.validators(buyer)).status) === 5 && sameSet(Array.from(await reg.getValidators()), without67), { block: rec2.block });
  await net.waitForBlock(rec2.block + 6);
  const q2 = (await net.qbftValidators(rec2.block)).map(ethers.getAddress);
  c.ok("QBFT set at the case-2 removal block == the 5 operators (n=5, quorum 4)", sameSet(q2, without67), q2);
  await send(net, "buyer", "REG", "objectRecoveryRemoval", []);
  const mem0 = await reg.membershipEpoch(buyer);
  let last; const votes2 = [];
  for (const i of [1, 2, 3]) { last = await send(net, "owner" + i, "BOARD", "voteRecoveryRemoval", [buyer, false]); votes2.push({ voter: "owner" + i, tx: last.hash }); }
  const B3 = last.block;
  c.ok("3 board votes to cancel -> Registry case Cancelled (5); RecoveryRemovalCancelled(expired=false) emitted", Number((await reg.recoveryCaseInfo(buyer)).state) === 5 && findEvent(last.receipt, R, "RecoveryRemovalCancelled").length === 1 && findEvent(last.receipt, R, "RecoveryRemovalCancelled")[0].args.expired === false, { block: B3 });
  const vb = await reg.validators(buyer);
  const after = Array.from(await reg.getValidators());
  const expectedFinal = without7.concat([]); // 6 operators: op7 stays out, op6 is back
  c.ok("buyer reinstated: Active (2), permanentlyExited cleared, op6 back: list == the 6 operators (op7 still out)", Number(vb.status) === 2 && !(await reg.permanentlyExited(buyer)) && sameSet(after, expectedFinal), after);
  await net.waitForBlock(B3 + 20);
  const q3 = (await net.qbftValidators(B3)).map(ethers.getAddress);
  const ser2 = await minerSeries(net, B3 - 8, B3 + 20);
  const first6 = ser2.find((s) => s.block > B3 && s.miner === op("op6"));
  c.ok("QBFT set at the cancel block == 6 operators; op6 mines again; no gap > 4 s (n=5 in between did not stall)", sameSet(q3, expectedFinal) && !!first6 && gapsOf(ser2).every((g) => g <= 4), { firstBlockByOp6: first6 && first6.block, gaps: gapsOf(ser2) });
  c.ok("membershipEpoch of buyer unchanged by the removal/reinstatement of a non-board seat (>= before)", (await reg.membershipEpoch(buyer)) >= mem0);
  c.ok("board unchanged by the cases: getBoardSize() == 5, all five still have authority", (await board.getBoardSize()) === 5n && (await Promise.all([1, 2, 3, 4, 5].map((i) => board.hasBoardAuthority(own(i))))).every((x) => x));
  const finalSet = Array.from(await reg.getValidators());
  c.ok("end: contract list == QBFT set (6 validators)", sameSet(finalSet, (await net.qbftValidators("latest")).map(ethers.getAddress)) && finalSet.length === 6, finalSet);
  writeResult("BH-07b", { verdict: c.verdict, summary: `case 1 (owner7, node down) removed at block ${B}, objected, upheld by 3 board votes; case 2 (buyer, op6) removed, objected, cancelled by 3 board votes and reinstated at block ${B3}; 90-day lock and 7-day expiry NOT elapsed (NOT-RUN)`, checks: c.items, negatives: neg, evidenceHashSource: "keccak256(JSON of qbft_getSignerMetrics at record time)", case1: { recordTx: rec.hash, block: B, qbftSets: q, series: ser, objectTx: obj.hash, votes }, case2: { recordTx: rec2.hash, cancelBlock: B3, votes: votes2, series: ser2 }, notRun: ["collateral lock for 90 days after recovery (elapsed)", "7-day expiry of the case (expireRecoveryRemoval after the deadline)", "referral to the validators (needs < 3 impartial board members able to act)", "exit/withdraw after the lock"] });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
