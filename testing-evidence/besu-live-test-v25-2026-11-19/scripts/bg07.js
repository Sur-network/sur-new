// BG-07 Recovery removal on Net-A (n=7): Verifier records the removal of a validator whose node was shut down; removal from the QBFT set while the chain runs;
// objection; board votes (3 of 5): case 1 upheld (owner6), case 2 cancelled (buyer, reinstated into the set). The 90-day lock and the 7-day expiry
// cannot elapse on Besu: only their refusals before the deadline are checked (NOT-RUN for the elapsed parts).
const { Net, Checks, writeResult, ethers, send, expectRevert, sleep, findEvent, ifaceOf, sameSet, minerSeries, gapsOf, ctl } = require("./lib");

(async () => {
  const net = new Net("A", "n1");
  const reg = net.c("REG"), board = net.c("BOARD");
  const c = new Checks();
  const op = (n) => net.addr(n), own = (i) => net.addr("owner" + i);
  const buyer = net.addr("buyer");
  const R = ifaceOf("REG"), BI = ifaceOf("BOARD");
  const full = Array.from(await reg.getValidators());
  c.ok("start: 7 validators", full.length === 7, full.length);
  const nowTs = async () => Number(BigInt((await net.block("latest")).timestamp));
  const members = Array.from(await board.getBoardMembers());
  c.ok("founding board == owner1..owner5 and has authority (board month == current month)", sameSet(members, [1, 2, 3, 4, 5].map(own)) && (await board.hasBoardAuthority(own(1))) === true, members);

  // ---- negatives of recordRecoveryRemoval
  const ts = await nowTs();
  const neg = {};
  neg.notVerifier = await expectRevert(net, "outsider", "REG", "recordRecoveryRemoval", [own(6), ts - 60, ethers.keccak256("0x01")]);
  neg.emptyHash = await expectRevert(net, "verifier", "REG", "recordRecoveryRemoval", [own(6), ts - 60, ethers.ZeroHash]);
  neg.future = await expectRevert(net, "verifier", "REG", "recordRecoveryRemoval", [own(6), ts + 3600, ethers.keccak256("0x01")]);
  neg.tooOld = await expectRevert(net, "verifier", "REG", "recordRecoveryRemoval", [own(6), ts - 31 * 86400, ethers.keccak256("0x01")]);
  neg.notActive = await expectRevert(net, "verifier", "REG", "recordRecoveryRemoval", [net.addr("cand"), ts - 60, ethers.keccak256("0x01")]);
  for (const [k, v] of Object.entries(neg)) c.ok(`negative: ${k} reverts`, v.reverted, v.reason);

  // ---- case 1: owner6's node is shut down, then the Verifier records the removal
  ctl("stop", "A", "n6");
  await net.waitBlocks(10);
  const metrics = await net.provider.send("qbft_getSignerMetrics", []);
  const evidenceHash = ethers.keccak256(ethers.toUtf8Bytes(JSON.stringify(metrics)));
  const recoveryTs = (await nowTs()) - 120;
  const rec = await send(net, "verifier", "REG", "recordRecoveryRemoval", [own(6), recoveryTs, evidenceHash]);
  const B = rec.block;
  const recEv = findEvent(rec.receipt, R, "RecoveryRemovalRecorded")[0];
  c.ok("RecoveryRemovalRecorded(owner6, recoveryTimestamp, evidenceHash, exitAllowedAt = recoveryTimestamp + 90 days)", !!recEv && Number(recEv.args.exitAllowedAt) === recoveryTs + 90 * 86400 && recEv.args.evidenceHash === evidenceHash, { gasUsed: rec.gasUsed, block: B });
  const v6 = await reg.validators(own(6));
  c.ok("owner6 status RemovedInRecovery (5); permanentlyExited true; membershipEpoch 1; collateral untouched (founder 0)", Number(v6.status) === 5 && (await reg.permanentlyExited(own(6))) && (await reg.membershipEpoch(own(6))) === 1n && v6.lockedStake === 0n);
  const without6 = full.filter((a) => a !== op("op6"));
  c.ok("op6 removed from getValidators() while the chain runs (n=6)", sameSet(Array.from(await reg.getValidators()), without6));
  await net.waitForBlock(B + 16);
  const q = {}; for (const n of [B - 1, B]) q[n] = (await net.qbftValidators(n)).map(ethers.getAddress);
  const ser = await minerSeries(net, B - 5, B + 16);
  c.ok("QBFT set: op6 in at B-1, out at B; blocks keep coming with gaps <= 4 s after removal (the dead node is no longer a proposer)", q[B - 1].includes(op("op6")) && sameSet(q[B], without6) && gapsOf(ser.filter((s) => s.block >= B)).every((g) => g <= 4), { gapsBeforeAndAfter: gapsOf(ser), block: B });
  const info = await reg.recoveryCaseInfo(own(6));
  c.ok("recoveryCaseInfo: state Recorded (1), objection deadline = recordedAt + 72 h", Number(info.state) === 1 && Number((await reg.recoveryRemovals(own(6))).objectionDeadline) === Number(info.recordedAt) + 72 * 3600, { recordedAt: Number(info.recordedAt) });
  const dup = await expectRevert(net, "verifier", "REG", "recordRecoveryRemoval", [own(6), recoveryTs, evidenceHash]);
  c.ok("negative: second record for the same validator reverts", dup.reverted, dup.reason);
  const exitEarly = await expectRevert(net, "owner6", "REG", "requestExit", []);
  c.ok("negative: requestExit while the case is open (before the objection window ended) reverts", exitEarly.reverted, exitEarly.reason);

  // objection
  const obj = await send(net, "owner6", "REG", "objectRecoveryRemoval", []);
  const info2 = await reg.recoveryCaseInfo(own(6));
  c.ok("objectRecoveryRemoval: state Objected (2), 7-day decision window opened", Number(info2.state) === 2 && Number(info2.resolutionDeadline) - Number(BigInt((await net.block(obj.block)).timestamp)) === 7 * 86400);
  const objTwice = await expectRevert(net, "owner6", "REG", "objectRecoveryRemoval", []);
  c.ok("negative: objecting twice reverts", objTwice.reverted, objTwice.reason);
  const expireEarly = await expectRevert(net, "tester", "REG", "expireRecoveryRemoval", [own(6)]);
  c.ok("negative: expireRecoveryRemoval before the 7 days reverts (the expiry itself is NOT-RUN on Besu)", expireEarly.reverted, expireEarly.reason);
  const referEarly = await expectRevert(net, "tester", "BOARD", "referRecoveryRemovalToAssembly", [own(6)]);
  c.ok("negative: referral to the validators refused while >= 3 impartial board members hold authority", referEarly.reverted, referEarly.reason);
  const nonMember = await expectRevert(net, "buyer", "BOARD", "voteRecoveryRemoval", [own(6), true]);
  c.ok("negative: a non-board member cannot vote", nonMember.reverted, nonMember.reason);
  const directResolve = await expectRevert(net, "verifier", "REG", "resolveRecoveryRemoval", [own(6), true]);
  c.ok("negative: resolveRecoveryRemoval only callable by the ValidatorsBoard contract", directResolve.reverted, directResolve.reason);

  // board votes: uphold x3
  const votes = [];
  for (const i of [1, 2, 3]) {
    const v = await send(net, "owner" + i, "BOARD", "voteRecoveryRemoval", [own(6), true]);
    votes.push({ voter: "owner" + i, tx: v.hash, gasUsed: v.gasUsed });
    if (i === 2) c.ok("after 2 uphold votes the case is still Objected", Number((await reg.recoveryCaseInfo(own(6))).state) === 2);
  }
  const lastVote = votes[2];
  const info3 = await reg.recoveryCaseInfo(own(6));
  c.ok("3rd board vote upholds: Registry state Upheld (4); status stays RemovedInRecovery; op6 stays out", Number(info3.state) === 4 && Number((await reg.validators(own(6))).status) === 5 && sameSet(Array.from(await reg.getValidators()), without6));
  const dupVote = await expectRevert(net, "owner4", "BOARD", "voteRecoveryRemoval", [own(6), true]);
  c.ok("negative: a vote after the case is decided reverts", dupVote.reverted, dupVote.reason);
  const exitLock = await expectRevert(net, "owner6", "REG", "requestExit", []);
  c.ok("negative: requestExit after the case, before recoveryTimestamp + 90 days, reverts (90-day lock; the elapsed part is NOT-RUN)", exitLock.reverted && /90 days/.test(exitLock.reason || ""), exitLock.reason);

  // ---- case 2: buyer (seat 7, Active, node n7 running) is removed, objects, the board cancels -> reinstated into the set
  const ts2 = await nowTs();
  const rec2 = await send(net, "verifier", "REG", "recordRecoveryRemoval", [buyer, ts2 - 60, ethers.keccak256(ethers.toUtf8Bytes("evidence case 2"))]);
  c.ok("case 2: buyer removed (n=5)", Number((await reg.validators(buyer)).status) === 5 && sameSet(Array.from(await reg.getValidators()), without6.filter((a) => a !== op("op7"))), { block: rec2.block });
  await send(net, "buyer", "REG", "objectRecoveryRemoval", []);
  const memEpochBefore = await reg.membershipEpoch(buyer);
  for (const i of [1, 2, 3]) await send(net, "owner" + i, "BOARD", "voteRecoveryRemoval", [buyer, false]);
  const B3 = await net.head();
  const info4 = await reg.recoveryCaseInfo(buyer);
  c.ok("3 board votes to cancel: Registry case Cancelled (5)", Number(info4.state) === 5, Number(info4.state));
  const vb = await reg.validators(buyer);
  c.ok("buyer reinstated: Active (2), permanentlyExited cleared, op7 back in getValidators() (n=6)", Number(vb.status) === 2 && !(await reg.permanentlyExited(buyer)) && sameSet(Array.from(await reg.getValidators()), without6.concat([op("op7")])), Array.from(await reg.getValidators()).length);
  await net.waitForBlock(B3 + 20);
  const ser2 = await minerSeries(net, B3 - 8, B3 + 20);
  const first7 = ser2.find((s) => s.block >= B3 && s.miner === op("op7"));
  c.ok("op7 mines again after the cancel; gaps <= 4 s (n=5 in between did not stall)", !!first7 && gapsOf(ser2).every((g) => g <= 4), { firstBlockByOp7: first7 && first7.block, gaps: gapsOf(ser2) });
  c.ok("membershipEpoch of buyer was bumped by the removal (board seat would end), unchanged by reinstatement", (await reg.membershipEpoch(buyer)) >= memEpochBefore);
  const finalSet = Array.from(await reg.getValidators());
  c.ok("end: contract list == QBFT set (6 validators: op1, op2b, op3b, op4, op5, op7)", sameSet(finalSet, (await net.qbftValidators("latest")).map(ethers.getAddress)) && finalSet.length === 6, finalSet);
  writeResult("BG-07", { verdict: c.verdict, summary: `case 1 (owner6, node down) removed at block ${B}, objected, upheld by 3 board votes; case 2 (buyer) removed, objected, cancelled by 3 board votes and reinstated; 90-day lock and 7-day expiry NOT elapsed (NOT-RUN)`, checks: c.items, negatives: neg, evidenceHashSource: "keccak256(JSON of qbft_getSignerMetrics at record time)", case1: { recordTx: rec.hash, block: B, qbftSets: q, series: ser, objectTx: obj.hash, votes }, case2: { recordTx: rec2.hash, cancelBlockApprox: B3, series: ser2 }, notRun: ["collateral lock for 90 days after recovery (elapsed)", "7-day expiry of the case (expireRecoveryRemoval after the deadline)", "referral to the validators (needs < 3 impartial board members)", "exit/withdraw after the lock"] });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
