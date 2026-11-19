// BH-02 founders activated (setOperator + Verifier recordActivation) up to n=4, then n=7 in ONE block (as BG-02/BG-12), with the new board rule:
// after each activation hasBoardAuthority becomes true for that board founder; a Probation founder (seat holder) is refused when proposing or voting before
// activation and accepted after; with 3 activated board members a 3-of-5 board action (proposeSetEntryCollateral +10%) executes on the live chain.
const { Net, Checks, writeResult, ethers, send, sendNoWait, expectRevert, sleep, sealSigners, findEvent, ifaceOf, ctl, sameSet, ADDR } = require("./lib");
const ev = (s) => ethers.keccak256(ethers.toUtf8Bytes(s));
(async () => {
  const net = new Net("A", "n1");
  const reg = net.c("REG"), board = net.c("BOARD");
  const stages = [];
  const c = new Checks();
  const op = (i) => net.addr("op" + i), own = (i) => net.addr("owner" + i);
  const BI = ifaceOf("BOARD");
  const NEWCOL = ethers.parseEther("550000"); // +10 % of 500,000 (the maximum single step)

  async function observe(label, txBlock, expectedOps, extra = {}) {
    await net.waitForBlock(txBlock + 6);
    const contractNow = Array.from(await reg.getValidators());
    const qbft = {};
    for (const n of [txBlock - 1, txBlock, txBlock + 1, txBlock + 2, txBlock + 3]) { try { qbft[n] = (await net.qbftValidators(n)).map(ethers.getAddress); } catch (e) { qbft[n] = "ERR " + e.message.slice(0, 80); } }
    let firstBlock = null;
    for (const n of [txBlock, txBlock + 1, txBlock + 2, txBlock + 3]) if (Array.isArray(qbft[n]) && sameSet(qbft[n], expectedOps)) { firstBlock = n; break; }
    const miners = {}; const ts = [];
    for (let n = txBlock + 1; n <= txBlock + 6; n++) { const b = await net.block(n); miners[n] = ethers.getAddress(b.miner); ts.push(Number(BigInt(b.timestamp))); }
    const gaps = ts.slice(1).map((t, i) => t - ts[i]);
    const o = { label, txBlock, contractList: contractNow, qbftSetsByBlock: qbft, firstBlockWithExpectedSet: firstBlock, minersTxBlockPlus1to6: miners, blockTimestampGaps: gaps, ...extra };
    stages.push(o);
    return o;
  }
  const authOf = async (i) => board.hasBoardAuthority(own(i));

  const heads = {};
  for (const n of ["n1", "n2", "n3", "n4", "n5", "n6", "n7"]) heads[n] = await net.at(n).head();
  c.ok("all 7 founder nodes running and in sync before the first activation", Math.max(...Object.values(heads)) - Math.min(...Object.values(heads)) <= 2, heads);
  c.ok("start: owner1 has board authority, owners 2..5 hold a seat without authority", (await authOf(1)) && !(await authOf(2)) && !(await authOf(3)) && !(await authOf(4)) && !(await authOf(5)) && (await board.getBoardSize()) === 5n);

  const active = [op(1)];
  const boardLog = [];
  let actionId = null;
  const colBefore = await reg.entryCollateral(), feeBefore = await reg.currentMembershipFee();
  c.ok("entryCollateral is 500,000 Suren before the board action", colBefore === ethers.parseEther("500000"), colBefore);

  for (const i of [2, 3, 4]) {
    const st0 = Number((await reg.validators(own(i))).status);
    c.ok(`owner${i} in Probation before`, st0 === 1, st0);
    const r1 = await send(net, "owner" + i, "REG", "setOperator", [op(i)]);
    c.ok(`owner${i}.setOperator(op${i}) does not change the validator list yet`, sameSet(Array.from(await reg.getValidators()), active), { opSetBlock: r1.block });
    // ---- Probation founder (seat holder): refused
    c.ok(`owner${i}: hasBoardAuthority == false before activation (Probation, operator set)`, (await authOf(i)) === false);
    const nProp = await expectRevert(net, "owner" + i, "BOARD", "proposeSetEntryCollateral", [NEWCOL]);
    c.ok(`negative: Probation founder owner${i} cannot propose (before activation)`, nProp.reverted && /no board authority/.test(nProp.reason || ""), nProp.reason);
    if (actionId !== null) {
      const nVote = await expectRevert(net, "owner" + i, "BOARD", "voteAction", [actionId]);
      c.ok(`negative: Probation founder owner${i} cannot vote on the open action ${actionId} (before activation)`, nVote.reverted && /no board authority/.test(nVote.reason || ""), nVote.reason);
    }
    const r2 = await send(net, "verifier", "REG", "recordActivation", [own(i), ev("activation owner" + i)]);
    active.push(op(i));
    c.ok(`owner${i}: hasBoardAuthority == true right after recordActivation`, (await authOf(i)) === true, { activationBlock: r2.block });
    c.ok(`board unchanged by the activation: getBoardSize() == 5`, (await board.getBoardSize()) === 5n);
    const o = await observe(`activate owner${i} (n=${active.length})`, r2.block, active, { setOperatorTx: r1.hash, activationTx: r2.hash });
    c.ok(`n=${active.length}: contract list == ${active.length} operator keys and equals the QBFT set`, sameSet(o.contractList, active) && o.firstBlockWithExpectedSet !== null, { firstBlockWithExpectedSet: o.firstBlockWithExpectedSet, activationBlock: r2.block });
    c.ok(`n=${active.length}: blocks keep being produced at ~2s`, o.blockTimestampGaps.every((g) => g >= 1 && g <= 4), o.blockTimestampGaps);
    c.ok(`n=${active.length}: getActiveOwners() returns owner keys, getValidators() operator keys`, (await reg.getActiveOwners()).length === active.length && (await reg.getActiveOwners()).includes(own(i)) && !o.contractList.includes(own(i)));

    if (i === 2) {
      // owner2 (now activated) proposes; owner1 votes: 2 of 3, not executed (only 2 activated members)
      const pr = await send(net, "owner2", "BOARD", "proposeSetEntryCollateral", [NEWCOL]);
      const pe = findEvent(pr.receipt, BI, "ActionProposed")[0];
      actionId = Number(pe.args.id);
      const a1 = await board.actions(actionId);
      c.ok("after activation owner2's proposeSetEntryCollateral(550,000) is ACCEPTED (ActionProposed emitted, amount 550,000)", pe.args.amount === NEWCOL && pe.args.proposer === own(2), { actionId, atype: Number(pe.args.atype), tx: pr.hash });
      c.ok("action state: votes 1, requiredVotes 3, not executed", Number(a1.votes) === 1 && Number(a1.requiredVotes) === 3 && a1.executed === false, { votes: Number(a1.votes), requiredVotes: Number(a1.requiredVotes) });
      const v1 = await send(net, "owner1", "BOARD", "voteAction", [actionId]);
      const a2 = await board.actions(actionId);
      c.ok("owner1 votes: 2 of 3, NOT executed (only two board members are activated)", Number(a2.votes) === 2 && a2.executed === false && (await reg.entryCollateral()) === colBefore, { tx: v1.hash });
      boardLog.push({ proposeTx: pr.hash, owner1VoteTx: v1.hash, actionId });
    }
    if (i === 3) {
      const v3 = await send(net, "owner3", "BOARD", "voteAction", [actionId]);
      const ex = findEvent(v3.receipt, BI, "RegistryEconomicParamSet");
      const a3 = await board.actions(actionId);
      c.ok("owner3 (3rd activated board member) votes: 3 of 3 -> action EXECUTED on the live chain (RegistryEconomicParamSet emitted)", a3.executed === true && Number(a3.votes) === 3 && ex.length === 1 && ex[0].args.newValue === NEWCOL, { block: v3.block, gasUsed: v3.gasUsed, tx: v3.hash });
      const colAfter = await reg.entryCollateral(), feeAfter = await reg.currentMembershipFee();
      c.ok("Registry.entryCollateral == 550,000 Suren (+10%), membership fee follows (4% of 550,000 = 22,000)", colAfter === NEWCOL && feeAfter === ethers.parseEther("22000"), { colAfter, feeAfter, feeBefore });
      const again = await expectRevert(net, "owner1", "BOARD", "voteAction", [actionId]);
      c.ok("negative: voting on the executed action reverts", again.reverted, again.reason);
      boardLog.push({ owner3VoteTx: v3.hash, executedBlock: v3.block });
    }
  }
  await net.waitBlocks(24);
  const h4 = await net.head();
  const hist4 = {}; for (let n = h4 - 23; n <= h4; n++) { const m = ethers.getAddress((await net.block(n)).miner); hist4[m] = (hist4[m] || 0) + 1; }
  c.ok("n=4: the last 24 blocks were mined by all four OPERATOR keys and by no owner key", Object.keys(hist4).length === 4 && Object.keys(hist4).every((m) => active.includes(m)), hist4);
  const seal4 = []; for (const n of [h4 - 1, h4 - 2, h4 - 3]) seal4.push(await sealSigners(net, n, active));
  c.ok("n=4: committed-seal signers recovered from the header (>=3 = quorum, all operator keys)", seal4.every((s) => s.signers && s.signers.length >= 3), seal4.map((s) => ({ block: s.block, miner: s.miner, signers: s.signers })));

  // f=1 tolerance at n=4
  const hStop = await net.head(); const tStop = Date.now();
  ctl("stop", "A", "n4");
  await net.waitBlocks(14);
  const hAfter = await net.head();
  const gaps = []; let prev = null;
  for (let n = hStop + 1; n <= hAfter; n++) { const b = await net.block(n); const t = Number(BigInt(b.timestamp)); if (prev !== null) gaps.push(t - prev); prev = t; }
  c.ok("n=4, node n4 stopped (f=1): chain keeps producing blocks", hAfter >= hStop + 14, { hStop, hAfter, seconds: Math.round((Date.now() - tStop) / 1000) });
  stages.push({ label: "n=4 with n4 stopped", headAtStop: hStop, headAfter: hAfter, blockTimestampGaps: gaps });
  ctl("start", "A", "n4");
  await sleep(15000);
  const hN4 = await net.at("n4").head(), hN1 = await net.head();
  c.ok("n4 restarted and caught up (head within 3 blocks of n1)", Math.abs(hN1 - hN4) <= 3, { hN1, hN4 });

  // n = 4 -> 7 in ONE block
  for (const i of [5, 6, 7]) {
    await send(net, "owner" + i, "REG", "setOperator", [op(i)]);
    if (i === 5) { const n5 = await expectRevert(net, "owner5", "BOARD", "proposeSetMembershipFeeBps", [450]); c.ok("negative: Probation founder owner5 cannot propose (before activation)", n5.reverted && /no board authority/.test(n5.reason || ""), n5.reason); }
  }
  c.ok("before the 3 activations: owner5 hasBoardAuthority false (Probation board seat), owner6/7 false (no board seat)", !(await authOf(5)) && !(await authOf(6)) && !(await authOf(7)));
  const txs = [];
  for (const i of [5, 6, 7]) txs.push(await sendNoWait(net, "verifier", "REG", "recordActivation", [own(i), ev("activation owner" + i)]));
  const rcs = []; for (const t of txs) rcs.push(await t.wait());
  const blocks = rcs.map((r) => r.blockNumber);
  const sameBlock = blocks.every((b) => b === blocks[0]);
  c.ok("three recordActivation txs mined in the SAME block (BG-12 style)", sameBlock, blocks);
  const all7 = [1, 2, 3, 4, 5, 6, 7].map(op);
  const o7 = await observe("activate owners 5,6,7 (n 4 -> 7)", Math.max(...blocks), all7, { txs: txs.map((t) => t.hash), blocks });
  c.ok("n=7: contract list == QBFT set == 7 operator keys from the activation block on", sameSet(o7.contractList, all7) && o7.firstBlockWithExpectedSet !== null && sameSet((await net.qbftValidators("latest")).map(ethers.getAddress), all7), { firstBlockWithExpectedSet: o7.firstBlockWithExpectedSet });
  c.ok("blocks continue after the +3 change (gaps <= 4 s in the window)", o7.blockTimestampGaps.every((g) => g >= 1 && g <= 4), o7.blockTimestampGaps);
  c.ok("owner5 hasBoardAuthority true after activation; owners 1..5 all true; owner6/7 false (not board members, getBoardSize still 5)", (await Promise.all([1, 2, 3, 4, 5].map(authOf))).every((x) => x) && !(await authOf(6)) && !(await authOf(7)) && (await board.getBoardSize()) === 5n);
  const p5 = await send(net, "owner5", "BOARD", "proposeSetMembershipFeeBps", [450]);
  const a5 = await board.actions(Number(findEvent(p5.receipt, BI, "ActionProposed")[0].args.id));
  c.ok("owner5 (activated) can now propose (proposeSetMembershipFeeBps(450) accepted; left open, 1 of 3 votes)", Number(a5.votes) === 1 && !a5.executed, { tx: p5.hash });
  await net.waitBlocks(30);
  const h7 = await net.head();
  const hist7 = {}; for (let n = h7 - 27; n <= h7; n++) { const m = ethers.getAddress((await net.block(n)).miner); hist7[m] = (hist7[m] || 0) + 1; }
  c.ok("n=7: the last 28 blocks were mined by the seven OPERATOR keys only", Object.keys(hist7).every((m) => all7.includes(m)) && Object.keys(hist7).length >= 6, hist7);
  const seal7 = []; for (const n of [h7 - 1, h7 - 2, h7 - 3, h7 - 4]) seal7.push(await sealSigners(net, n, all7));
  c.ok("n=7: committed seals recovered, >=5 distinct operator signers (quorum 5 of 7)", seal7.every((s) => s.signers && new Set(s.signers).size >= 5), seal7.map((s) => ({ block: s.block, miner: s.miner, sealCount: s.sealCount, signers: s.signers })));
  const metrics = await net.provider.send("qbft_getSignerMetrics", []);
  writeResult("BH-02", { verdict: c.verdict, summary: "founders 2..7 joined (1 -> 2 -> 3 -> 4 -> 7); board authority follows the activation; Probation founders refused before, accepted after; 3-of-5 board action executed (entryCollateral 500,000 -> 550,000)", checks: c.items, stages, boardLog, hist4, hist7, signerMetrics: metrics });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
