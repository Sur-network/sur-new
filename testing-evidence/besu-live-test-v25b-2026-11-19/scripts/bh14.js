// BH-14 selfSuspend + clearStaleVotes (Net-A). New in commit e1a5f1f: clearStaleVotes covers SelfSuspended (status 6) with a 30-day delay counted from
// the moment the suspension began (periodStartedAt); the message for a validator that is not suspended is "not currently suspended" (was "not currently demoted").
// The 30-day part is NOT-RUN on Besu (time cannot be advanced): only the refusals before 30 days are checked.
const { Net, Checks, writeResult, ethers, send, expectRevert, sleep, findEvent, ifaceOf, sameSet, minerSeries, gapsOf } = require("./lib");
const ev = (s) => ethers.keccak256(ethers.toUtf8Bytes(s));

(async () => {
  const net = new Net("A", "n1");
  const reg = net.c("REG"), board = net.c("BOARD");
  const c = new Checks();
  const op = (n) => net.addr(n), own = (i) => net.addr("owner" + i);
  const B_ = ifaceOf("BOARD"), R = ifaceOf("REG");
  const v7 = own(7);
  const full = Array.from(await reg.getValidators());
  c.ok("start: 7 validators, owner7 Active (2)", full.length === 7 && Number((await reg.validators(v7)).status) === 2, full.length);
  c.ok("STALE_VOTE_CLEAR_DELAY == 30 days", (await board.STALE_VOTE_CLEAR_DELAY()) === BigInt(30 * 86400));

  // votes that clearStaleVotes would purge (identity needed to vote)
  const idTx = [];
  for (const r of ["owner1", "owner7"]) idTx.push((await send(net, r, "IDENTITY", "registerIdentity", [0, "Test Person " + r])).hash);
  await send(net, "owner7", "BOARD", "voteFor", [own(1)]);
  await send(net, "owner1", "BOARD", "voteFor", [v7]);
  c.ok("votes exist: owner7 -> owner1 given, owner1 -> owner7 received", (await board.getVotesOf(v7)).includes(own(1)) && (await board.getVotersFor(v7)).includes(own(1)));

  // negative 1: Active validator
  const nActive = await expectRevert(net, "tester", "BOARD", "clearStaleVotes", [v7]);
  c.ok("negative: clearStaleVotes on an ACTIVE validator reverts with exactly 'ValidatorsBoard: validator is not currently suspended'", nActive.reverted && nActive.reason === "ValidatorsBoard: validator is not currently suspended", nActive.reason);
  const nProb = await expectRevert(net, "tester", "BOARD", "clearStaleVotes", [net.addr("cand")]);
  c.ok("negative: clearStaleVotes on an address with no validator record reverts with the same message", nProb.reverted && nProb.reason === "ValidatorsBoard: validator is not currently suspended", nProb.reason);

  // board member cannot suspend
  const nBoard = await expectRevert(net, "owner4", "REG", "selfSuspend", []);
  c.ok("negative: a board member (owner4) cannot selfSuspend ('a board member cannot suspend voluntarily')", nBoard.reverted && /board member cannot suspend/.test(nBoard.reason || ""), nBoard.reason);
  const nNot = await expectRevert(net, "outsider", "REG", "selfSuspend", []);
  c.ok("negative: a non-validator cannot selfSuspend", nNot.reverted && /not active/.test(nNot.reason || ""), nNot.reason);

  // selfSuspend of owner7 (node n7 keeps running but leaves the set)
  await net.waitBlocks(2);
  const s = await send(net, "owner7", "REG", "selfSuspend", []);
  const Bk = s.block, tsS = Number(BigInt((await net.block(Bk)).timestamp));
  const without7 = full.filter((a) => a !== op("op7"));
  c.ok("selfSuspend: status SelfSuspended (6), SelfSuspendedEvent emitted, op7 out of getValidators() (n=6)", Number((await reg.validators(v7)).status) === 6 && findEvent(s.receipt, R, "SelfSuspendedEvent").length === 1 && sameSet(Array.from(await reg.getValidators()), without7), { block: Bk, gasUsed: s.gasUsed });
  await net.waitForBlock(Bk + 14);
  const q = {}; for (const n of [Bk - 1, Bk]) q[n] = (await net.qbftValidators(n)).map(ethers.getAddress);
  const ser = await minerSeries(net, Bk - 4, Bk + 14);
  c.ok("QBFT: op7 in at B-1, out at B; op7 never mines afterwards; no halt (gaps <= 4 s)", q[Bk - 1].includes(op("op7")) && sameSet(q[Bk], without7) && !ser.filter((x) => x.block > Bk).some((x) => x.miner === op("op7")) && gapsOf(ser).every((g) => g <= 4), { gaps: gapsOf(ser) });

  // negative 2: SelfSuspended before 30 days
  const info = await reg.getValidatorInfo(v7);
  const nowTs = Number(BigInt((await net.block("latest")).timestamp));
  const nSusp = await expectRevert(net, "tester", "BOARD", "clearStaleVotes", [v7]);
  c.ok("negative: clearStaleVotes on a SelfSuspended validator before 30 days reverts with exactly 'ValidatorsBoard: stale-vote delay not elapsed' (so status 6 is accepted by the status check)", nSusp.reverted && nSusp.reason === "ValidatorsBoard: stale-vote delay not elapsed", { reason: nSusp.reason, status: Number(info.status), periodStartedAt: Number(info.periodStartedAt), suspendedAtBlockTs: tsS, secondsSince: nowTs - Number(info.periodStartedAt), thresholdIs: "periodStartedAt + 30 days = " + (Number(info.periodStartedAt) + 30 * 86400) });
  c.ok("periodStartedAt == the timestamp of the selfSuspend block (the 30 days count from the suspension)", Number(info.periodStartedAt) === tsS, { periodStartedAt: Number(info.periodStartedAt), tsS });
  c.ok("the refused call purged nothing: the votes are still there", (await board.getVotesOf(v7)).includes(own(1)) && (await board.getVotersFor(v7)).includes(own(1)));

  // resume: back to Active
  const rq = await send(net, "owner7", "REG", "requestResume", []);
  const rr = await send(net, "verifier", "REG", "recordResume", [v7, ev("node n7 health check after selfSuspend")]);
  c.ok("requestResume + recordResume: Active (2) again, no probation, op7 back in getValidators() (n=7)", Number((await reg.validators(v7)).status) === 2 && sameSet(Array.from(await reg.getValidators()), full), { block: rr.block });
  const nAfter = await expectRevert(net, "tester", "BOARD", "clearStaleVotes", [v7]);
  c.ok("negative: after the resume clearStaleVotes is again 'not currently suspended'", nAfter.reverted && nAfter.reason === "ValidatorsBoard: validator is not currently suspended", nAfter.reason);
  await net.waitForBlock(rr.block + 20);
  const ser2 = await minerSeries(net, rr.block - 2, rr.block + 20);
  c.ok("op7 (same node n7) mines again; no gap > 4 s", ser2.some((x) => x.block > rr.block && x.miner === op("op7")) && gapsOf(ser2).every((g) => g <= 4), { gaps: gapsOf(ser2) });
  writeResult("BH-14", { verdict: c.verdict, summary: "clearStaleVotes: Active -> 'not currently suspended'; SelfSuspended before 30 days -> 'stale-vote delay not elapsed'; 30-day success NOT-RUN", checks: c.items, txs: { identity: idTx, selfSuspend: s.hash, requestResume: rq.hash, recordResume: rr.hash }, qbftSets: q, series: ser, notRun: ["clearStaleVotes succeeding after 30 days (SelfSuspended) or recoveryPeriod+30 days (Demoted): Besu cannot advance time"] });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
