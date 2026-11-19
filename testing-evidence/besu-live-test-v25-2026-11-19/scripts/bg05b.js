// BG-05b Full paid-entry cycle on Net-T (TEST-ONLY genesis overlay of ValidatorsRegistry storage variables: probationPeriod 120 s, exitCooldown 60 s,
// entryWindowSeconds 30 s, recoveryPeriod 60 s; all other parameters and ALL constants are the real ones).
// cand: identity -> requestMembership(opC) -> Probation -> (too early refused) -> Verifier activation after probation -> in the QBFT set with node nC ->
// requestExit -> leaves the set, seat burned -> withdrawStake after the cooldown returns the collateral.
const { Net, Checks, writeResult, ethers, send, expectRevert, sleep, findEvent, ifaceOf, ADDR, S, sameSet, minerSeries, gapsOf, waitSynced, ctl, makeManyFullyVerified } = require("./lib");
const ev = (s) => ethers.keccak256(ethers.toUtf8Bytes(s));

(async () => {
  const net = new Net("T", "n1");
  const reg = net.c("REG"), nft = net.c("NFT");
  const c = new Checks();
  const cand = net.addr("cand"), opC = net.addr("opC"), op1 = net.addr("op1");
  const R = ifaceOf("REG");
  const nowTs = async () => Number(BigInt((await net.block("latest")).timestamp));
  const waitChainTime = async (t) => { for (;;) { if ((await nowTs()) >= t) return; await sleep(500); } };

  c.ok("overlay visible on chain: probationPeriod 120, exitCooldown 60, entryWindowSeconds 30, recoveryPeriod 60", [await reg.probationPeriod(), await reg.exitCooldown(), await reg.entryWindowSeconds(), await reg.recoveryPeriod()].map(Number).join() === "120,60,30,60");
  c.ok("constants are the real ones: MASS_DEMOTION_WINDOW 3600, RECOVERY_COLLATERAL_LOCK 90 days", (await reg.MASS_DEMOTION_WINDOW()) === 3600n && (await reg.RECOVERY_COLLATERAL_LOCK()) === BigInt(90 * 86400));
  const v0 = Array.from(await reg.getValidators());
  c.ok("start: single validator op1 (genesis)", v0.length === 1 && v0[0] === op1);
  const idTxs = await makeManyFullyVerified(net, ["cand"]);
  c.ok("cand fully verified", await net.c("IDENTITY").isFullyVerified(cand));
  ctl("start", "T", "nC");
  const sync = await waitSynced(net, "nC");
  c.ok("node nC running and synced (non-validator)", true, sync);

  const value = (await reg.currentEntryThreshold()) + (await reg.currentMembershipFee());
  const regBal0 = await net.balance(ADDR.REG), candBal0 = await net.balance(cand);
  const entry = await send(net, "cand", "REG", "requestMembership", [opC], { value });
  const entryTs = Number(BigInt((await net.block(entry.block)).timestamp));
  c.ok("requestMembership: Probation, collateral 500,000 in Registry, seat #2 minted", Number((await reg.validators(cand)).status) === 1 && (await net.balance(ADDR.REG)) - regBal0 === S(500000) && (await nft.ownerOf(2)) === cand, { block: entry.block, gasUsed: entry.gasUsed });
  const early = await expectRevert(net, "verifier", "REG", "recordActivation", [cand, ev("too early")]);
  c.ok("negative: recordActivation inside the 120 s probation reverts", early.reverted && /probation/.test(early.reason || ""), early.reason);
  await waitChainTime(entryTs + 121);
  const act = await send(net, "verifier", "REG", "recordActivation", [cand, ev("probation ok, node nC up")]);
  const B = act.block;
  c.ok("recordActivation after the probation period: status Active (2); ValidatorActivated emitted", Number((await reg.validators(cand)).status) === 2 && findEvent(act.receipt, R, "ValidatorActivated").length === 1, { block: B, gasUsed: act.gasUsed, secondsAfterEntry: Number(BigInt((await net.block(B)).timestamp)) - entryTs });
  const both = [op1, opC];
  c.ok("getValidators() == [op1, opC] (operator key of the paid entrant, not its owner key)", sameSet(Array.from(await reg.getValidators()), both) && !(await reg.getValidators()).includes(cand));
  await net.waitForBlock(B + 14);
  const q = {}; for (const n of [B - 1, B]) q[n] = (await net.qbftValidators(n)).map(ethers.getAddress);
  const ser = await minerSeries(net, B - 3, B + 14);
  const first = ser.find((s) => s.block > B && s.miner === opC);
  c.ok("QBFT set grows 1 -> 2 at the activation block; opC mines; blocks continue at 2 s", q[B - 1].length === 1 && sameSet(q[B], both) && !!first && gapsOf(ser).every((g) => g <= 4), { firstBlockByOpC: first && first.block, gaps: gapsOf(ser) });

  // exit
  const exitEarlyW = await expectRevert(net, "cand", "REG", "withdrawStake", []);
  c.ok("negative: withdrawStake while Active reverts", exitEarlyW.reverted, exitEarlyW.reason);
  const ex = await send(net, "cand", "REG", "requestExit", []);
  const exTs = Number(BigInt((await net.block(ex.block)).timestamp));
  const exitEv = findEvent(ex.receipt, R, "ExitRequested")[0];
  c.ok("requestExit: Exiting (4), ExitRequested(cooldownEnd = +60 s), leaves getValidators(), seat burned", Number((await reg.validators(cand)).status) === 4 && Number(exitEv.args.cooldownEnd) === exTs + 60 && sameSet(Array.from(await reg.getValidators()), [op1]) && (await nft.balanceOf(cand)) === 0n, { block: ex.block });
  await net.waitForBlock(ex.block + 8);
  const qe = (await net.qbftValidators(ex.block)).map(ethers.getAddress);
  c.ok("QBFT set back to [op1] from the exit block; chain continues", sameSet(qe, [op1]) && (await net.head()) >= ex.block + 8, qe);
  const wEarly = await expectRevert(net, "cand", "REG", "withdrawStake", []);
  c.ok("negative: withdrawStake inside the 60 s cooldown reverts", wEarly.reverted && /cooldown/.test(wEarly.reason || ""), wEarly.reason);
  await waitChainTime(exTs + 61);
  const balBefore = await net.balance(cand), regBefore = await net.balance(ADDR.REG);
  const w = await send(net, "cand", "REG", "withdrawStake", []);
  const balAfter = await net.balance(cand);
  c.ok("withdrawStake returns the full 500,000 Suren collateral (net of gas); Registry balance -500,000", balAfter - balBefore + w.receipt.gasUsed * w.receipt.gasPrice === S(500000) && regBefore - (await net.balance(ADDR.REG)) === S(500000), { gasUsed: w.gasUsed });
  c.ok("record deleted (None 0); permanentlyExited true; everActivated stays true", Number((await reg.validators(cand)).status) === 0 && (await reg.permanentlyExited(cand)) && (await reg.everActivated(cand)));
  const rejoin = await expectRevert(net, "cand", "REG", "requestMembership", [opC], { value: S(520000) });
  c.ok("negative: the same address can never rejoin (permanent exit) - or cannot afford: " + rejoin.reason, rejoin.reverted, rejoin);
  writeResult("BG-05b", { verdict: c.verdict, summary: "paid entrant cycle on Net-T with short probation/cooldown overlay: entry, activation in the QBFT set, exit, collateral back", checks: c.items, txs: { identity: idTxs, entry: entry.hash, activation: act.hash, exit: ex.hash, withdraw: w.hash }, activationBlock: B, qbftSets: q, series: ser, overlayNote: "ValidatorsRegistry.probationPeriod/exitCooldown/entryWindowSeconds/recoveryPeriod overwritten in genesis storage (TEST-ONLY); BG-05 (Net-A) used the real 7-day values" });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
