// BG-04 selfSuspend / requestResume / recordResume on Net-A: validator leaves and re-enters the QBFT set; chain keeps producing blocks.
const { Net, Checks, writeResult, ethers, send, expectRevert, sleep, findEvent, ifaceOf, sameSet, minerSeries, gapsOf } = require("./lib");
const ev = (s) => ethers.keccak256(ethers.toUtf8Bytes(s));

(async () => {
  const net = new Net("A", "n1");
  const reg = net.c("REG");
  const c = new Checks();
  const op = (n) => net.addr(n), own = (i) => net.addr("owner" + i);
  const full = Array.from(await reg.getValidators());
  c.ok("start: 7 validators", full.length === 7, full);
  const without6 = full.filter((a) => a !== op("op6"));

  const neg = {};
  neg.boardMember = await expectRevert(net, "owner1", "REG", "selfSuspend", []);
  neg.notActive = await expectRevert(net, "cand", "REG", "selfSuspend", []);
  neg.resumeNotSuspended = await expectRevert(net, "owner6", "REG", "requestResume", []);
  neg.verifierResumeActive = await expectRevert(net, "verifier", "REG", "recordResume", [own(6), ev("x")]);
  for (const [k, v] of Object.entries(neg)) c.ok(`negative: ${k} reverts`, v.reverted, v.reason);

  const s = await send(net, "owner6", "REG", "selfSuspend", []);
  const B = s.block;
  c.ok("SelfSuspendedEvent emitted", findEvent(s.receipt, ifaceOf("REG"), "SelfSuspendedEvent").length === 1, { gasUsed: s.gasUsed });
  c.ok("owner6 status SelfSuspended (6); getValidators() drops op6 at once; getActiveOwners drops owner6", Number((await reg.validators(own(6))).status) === 6 && sameSet(Array.from(await reg.getValidators()), without6) && !(await reg.getActiveOwners()).includes(own(6)));
  c.ok("isValidator(owner6) == false; collateral untouched (0 for a founder)", !(await reg.isValidator(own(6))));
  await net.waitForBlock(B + 20);
  const q = {}; for (const n of [B - 1, B, B + 1]) q[n] = (await net.qbftValidators(n)).map(ethers.getAddress);
  c.ok("QBFT set at B-1 has op6, at B it does not (n=6)", q[B - 1].includes(op("op6")) && sameSet(q[B], without6), q);
  const ser = await minerSeries(net, B - 4, B + 20);
  c.ok("op6 never mines after the suspension block; blocks keep coming (gaps <= 4 s)", !ser.filter((x) => x.block > B).some((x) => x.miner === op("op6")) && gapsOf(ser).every((g) => g <= 4), gapsOf(ser));
  c.ok("node n6 keeps running as a non-validator (in sync)", Math.abs((await net.head()) - (await net.at("n6").head())) <= 2);

  const recEarly = await expectRevert(net, "verifier", "REG", "recordResume", [own(6), ev("no request")]);
  c.ok("negative: recordResume before requestResume reverts", recEarly.reverted && /no resume request/.test(recEarly.reason || ""), recEarly.reason);
  const rq = await send(net, "owner6", "REG", "requestResume", []);
  c.ok("requestResume: resumeRequested(owner6) == true; still out of the set", (await reg.resumeRequested(own(6))) === true && sameSet(Array.from(await reg.getValidators()), without6));
  const notVer = await expectRevert(net, "owner6", "REG", "recordResume", [own(6), ev("self")]);
  c.ok("negative: the owner cannot resume itself (only the Verifier)", notVer.reverted, notVer.reason);
  const rr = await send(net, "verifier", "REG", "recordResume", [own(6), ev("node health check ok")]);
  const B2 = rr.block;
  const decisionEv = findEvent(rr.receipt, ifaceOf("REG"), "ResumeRecorded")[0], actEv = findEvent(rr.receipt, ifaceOf("REG"), "ValidatorActivated")[0];
  c.ok("ResumeRecorded + ValidatorActivated events; status Active (2) again with NO probation", !!decisionEv && !!actEv && Number((await reg.validators(own(6))).status) === 2, { gasUsed: rr.gasUsed });
  c.ok("op6 back in getValidators() (n=7)", sameSet(Array.from(await reg.getValidators()), full));
  await net.waitForBlock(B2 + 24);
  const ser2 = await minerSeries(net, B2 - 2, B2 + 24);
  const first = ser2.find((x) => x.block > B2 && x.miner === op("op6"));
  c.ok("op6 mines again (no restart of the node needed); gaps <= 4 s", !!first && gapsOf(ser2).every((g) => g <= 4), { firstBlockByOp6: first && first.block, resumeBlock: B2 });
  const dec = await reg.getValidatorInfo(own(6)).catch(() => null);
  writeResult("BG-04", { verdict: c.verdict, summary: `selfSuspend at block ${B}, out of the QBFT set from block ${B}; recordResume at block ${B2}, mines again from block ${first && first.block}`, checks: c.items, negatives: neg, suspendTx: s.hash, requestResumeTx: rq.hash, recordResumeTx: rr.hash, qbftSets: q, seriesDuringSuspension: ser, seriesAfterResume: ser2 });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
