// BH-06 part B (Net-T, TEST-ONLY genesis overlay: probationPeriod 120 s, exitCooldown 60 s, entryWindowSeconds 30 s, recoveryPeriod 60 s; all constants real).
// Paid entrant `cand` (collateral 500,000 Suren, operator opC, node nC) shows what part A (founder, collateral 0) cannot:
//  1. a PROBATION seat is sold (buyerP): the record, collateral and operator move; the Verifier activates it WITHOUT acceptSeatTransfer (old rule: refused);
//  2. an ACTIVE seat WITH collateral is sold (buyerP -> buyerQ): the set and order are unchanged, nC never leaves the QBFT set, collateral moves with the seat;
//  3. the new owner exits and withdraws the 500,000 (the collateral really moved).
const { Net, Checks, writeResult, ethers, send, expectRevert, sleep, findEvent, ifaceOf, ADDR, S, sameSet, minerSeries, gapsOf, waitSynced, ctl, makeManyFullyVerified } = require("./lib");
const { execSync } = require("child_process");
const ev = (s) => ethers.keccak256(ethers.toUtf8Bytes(s));
const startedAt = (c) => execSync(`docker inspect -f "{{.State.StartedAt}}" ${c}`).toString().trim();

(async () => {
  const net = new Net("T", "n1");
  const reg = net.c("REG"), nft = net.c("NFT");
  const c = new Checks();
  const cand = net.addr("cand"), buyerP = net.addr("buyerP"), buyerQ = net.addr("buyerQ"), opC = net.addr("opC"), op1 = net.addr("op1");
  const R = ifaceOf("REG");
  const nowTs = async () => Number(BigInt((await net.block("latest")).timestamp));
  const waitChainTime = async (t) => { for (;;) { if ((await nowTs()) >= t) return; await sleep(500); } };

  c.ok("overlay visible on chain: probationPeriod 120, exitCooldown 60, entryWindowSeconds 30, recoveryPeriod 60", [await reg.probationPeriod(), await reg.exitCooldown(), await reg.entryWindowSeconds(), await reg.recoveryPeriod()].map(Number).join() === "120,60,30,60");
  const v0 = Array.from(await reg.getValidators());
  c.ok("start: single validator op1 (genesis)", v0.length === 1 && v0[0] === op1);
  const idTxs = await makeManyFullyVerified(net, ["cand", "buyerP", "buyerQ"]);
  c.ok("cand, buyerP and buyerQ fully verified", (await Promise.all(["cand", "buyerP", "buyerQ"].map((r) => net.c("IDENTITY").isFullyVerified(net.addr(r))))).every((x) => x));
  ctl("start", "T", "nC");
  const sync = await waitSynced(net, "nC");
  c.ok("node nC running and synced (non-validator)", true, sync);

  // ---- paid entry
  const value = (await reg.currentEntryThreshold()) + (await reg.currentMembershipFee());
  const entry = await send(net, "cand", "REG", "requestMembership", [opC], { value });
  const entryTs = Number(BigInt((await net.block(entry.block)).timestamp));
  const regBalEntry = await net.balance(ADDR.REG);
  const seatId = 2n;
  c.ok("requestMembership: Probation (1), collateral 500,000 locked, seat #2 owned by cand, operator opC", Number((await reg.validators(cand)).status) === 1 && (await reg.validators(cand)).lockedStake === S(500000) && (await nft.ownerOf(seatId)) === cand && (await reg.operatorOf(cand)) === opC, { block: entry.block });

  // ---- 1. Probation seat sold
  const neg = {};
  neg.toUnverified = await expectRevert(net, "cand", "NFT", "transferFrom", [cand, net.addr("outsider"), seatId]);
  neg.toSeatHolder = await expectRevert(net, "cand", "NFT", "transferFrom", [cand, net.addr("owner1"), seatId]);
  neg.toOperatorKey = await expectRevert(net, "cand", "NFT", "transferFrom", [cand, op1, seatId]);
  neg.notOwner = await expectRevert(net, "buyerP", "NFT", "transferFrom", [cand, buyerP, seatId]);
  for (const [k, v] of Object.entries(neg)) c.ok(`negative: ${k} reverts`, v.reverted, v.reason);
  const infoP0 = await reg.validators(cand);
  const t1 = await send(net, "cand", "NFT", "transferFrom", [cand, buyerP, seatId]);
  const st1 = findEvent(t1.receipt, R, "SeatTransferred")[0];
  const vP = await reg.validators(buyerP);
  c.ok("Probation seat sold: SeatTransferred(statusAfter = Probation 1); record, collateral (500,000), isPaidEntrant, periodStartedAt and operator opC moved to buyerP; cand record deleted", Number(st1.args.statusAfter) === 1 && Number(vP.status) === 1 && vP.lockedStake === S(500000) && vP.isPaidEntrant === true && vP.periodStartedAt === infoP0.periodStartedAt && (await reg.operatorOf(buyerP)) === opC && (await reg.ownerOfOperator(opC)) === buyerP && Number((await reg.validators(cand)).status) === 0 && (await reg.permanentlyExited(cand)), { block: t1.block, gasUsed: t1.gasUsed });
  c.ok("Registry balance unchanged by the sale (collateral stays in the Registry, now belongs to buyerP's record); seatTransferPending(buyerP) true", (await net.balance(ADDR.REG)) === regBalEntry && (await reg.seatTransferPending(buyerP)) === true);
  c.ok("getValidators() still [op1] (Probation is not in the set)", sameSet(Array.from(await reg.getValidators()), [op1]));
  const early = await expectRevert(net, "verifier", "REG", "recordActivation", [buyerP, ev("too early")]);
  c.ok("negative: recordActivation inside the 120 s probation still reverts (probation is not reset by the sale)", early.reverted && /probation/.test(early.reason || ""), early.reason);
  await waitChainTime(entryTs + 121);
  // the buyer has NOT accepted the agreement
  c.ok("before activation: buyerP has NOT called acceptSeatTransfer (seatTransferPending true)", (await reg.seatTransferPending(buyerP)) === true);
  const act = await send(net, "verifier", "REG", "recordActivation", [buyerP, ev("probation ok, node nC up, seat bought")]);
  const Bact = act.block;
  c.ok("recordActivation succeeds WITHOUT acceptSeatTransfer (old rule refused with 'seat transfer not accepted'): buyerP Active (2), still seatTransferPending", Number((await reg.validators(buyerP)).status) === 2 && (await reg.seatTransferPending(buyerP)) === true && findEvent(act.receipt, R, "ValidatorActivated").length === 1, { block: Bact, gasUsed: act.gasUsed });
  const both = [op1, opC];
  c.ok("getValidators() == [op1, opC]", sameSet(Array.from(await reg.getValidators()), both));
  await net.waitForBlock(Bact + 14);
  const qa = {}; for (const n of [Bact - 1, Bact]) qa[n] = (await net.qbftValidators(n)).map(ethers.getAddress);
  const serA = await minerSeries(net, Bact - 3, Bact + 14);
  const firstA = serA.find((s) => s.block > Bact && s.miner === opC);
  c.ok("QBFT set grows 1 -> 2 at the activation block; opC (node nC) mines; blocks continue at 2 s", qa[Bact - 1].length === 1 && sameSet(qa[Bact], both) && !!firstA && gapsOf(serA).every((g) => g <= 4), { firstBlockByOpC: firstA && firstA.block, gaps: gapsOf(serA) });

  // ---- 2. Active seat WITH collateral sold (buyerP -> buyerQ)
  const listBefore = Array.from(await reg.getValidators()), ownersBefore = Array.from(await reg.getActiveOwners());
  const N0 = await reg.statusNonce();
  const infoP1 = await reg.validators(buyerP);
  const regBal1 = await net.balance(ADDR.REG);
  const nCStart0 = startedAt("sur25b-t-nC");
  await net.waitBlocks(2);
  const t2 = await send(net, "buyerP", "NFT", "transferFrom", [buyerP, buyerQ, seatId]);
  const B = t2.block;
  const st2 = findEvent(t2.receipt, R, "SeatTransferred")[0];
  const N1 = await reg.statusNonce();
  const vQ = await reg.validators(buyerQ);
  c.ok("Active seat sold: SeatTransferred(statusAfter = Active 2); validators(buyerQ) Active (2) with lockedStake 500,000 and isPaidEntrant; buyerP record deleted", Number(st2.args.statusAfter) === 2 && Number(vQ.status) === 2 && vQ.lockedStake === S(500000) && vQ.isPaidEntrant === true && vQ.periodStartedAt === infoP1.periodStartedAt && Number((await reg.validators(buyerP)).status) === 0, { block: B, gasUsed: t2.gasUsed });
  c.ok("Registry balance unchanged by the sale (collateral moved with the record, nothing paid out)", (await net.balance(ADDR.REG)) === regBal1);
  const listAfter = Array.from(await reg.getValidators()), ownersAfter = Array.from(await reg.getActiveOwners());
  const idx = ownersBefore.indexOf(buyerP);
  c.ok("getValidators() IDENTICAL (same keys, same order); getActiveOwners(): buyerQ at buyerP's index " + idx, JSON.stringify(listAfter) === JSON.stringify(listBefore) && ownersAfter[idx] === buyerQ && ownersAfter.length === ownersBefore.length && !ownersAfter.includes(buyerP), { listBefore, listAfter, ownersBefore, ownersAfter });
  c.ok("operator key moved: operatorOf(buyerQ)==opC, ownerOfOperator(opC)==buyerQ; seller permanentlyExited, membershipEpoch 1; seatTransferPending(buyerQ) true", (await reg.operatorOf(buyerQ)) === opC && (await reg.ownerOfOperator(opC)) === buyerQ && (await reg.permanentlyExited(buyerP)) && (await reg.membershipEpoch(buyerP)) === 1n && (await reg.seatTransferPending(buyerQ)) === true);
  c.ok("buyerQ is a new voter: wasActiveAt(buyerQ, N0) false, true at N1; seller true at N0, false at N1; statusNonce +2", !(await reg.wasActiveAt(buyerQ, N0)) && (await reg.wasActiveAt(buyerQ, N1)) && (await reg.wasActiveAt(buyerP, N0)) && !(await reg.wasActiveAt(buyerP, N1)) && N1 === N0 + 2n, { N0, N1 });
  await net.waitForBlock(B + 20);
  const q = {}; for (const n of [B - 1, B, B + 1]) q[n] = (await net.qbftValidators(n)).map(ethers.getAddress);
  const serB = await minerSeries(net, B - 10, B + 20);
  const gapsB = gapsOf(serB);
  c.ok("QBFT set at B-1, B, B+1 == [op1, opC] (opC never leaves)", sameSet(q[B - 1], both) && sameSet(q[B], both) && sameSet(q[B + 1], both), q);
  const nCmined = serB.filter((s) => s.block > B && s.miner === opC).length;
  c.ok("opC keeps mining after the sale (" + nCmined + " blocks in B+1..B+20); no gap above the block period: max gap " + Math.max(...gapsB) + " s", nCmined >= 1 && Math.max(...gapsB) <= 2, gapsB);
  const nCStart1 = startedAt("sur25b-t-nC");
  c.ok("node nC container NOT restarted (same StartedAt)", nCStart0 === nCStart1, { nCStart0, nCStart1 });
  // stale flag on the seller: informational
  const staleSellerPending = await reg.seatTransferPending(buyerP);
  c.ok("INFO: seatTransferPending(seller buyerP) after selling = " + staleSellerPending + " (the flag is not cleared on the seller; seller has no record, so it has no effect)", true, { staleSellerPending });
  const accQ = await send(net, "buyerQ", "REG", "acceptSeatTransfer", []);
  c.ok("buyerQ acceptSeatTransfer: pending false, list unchanged", !(await reg.seatTransferPending(buyerQ)) && JSON.stringify(Array.from(await reg.getValidators())) === JSON.stringify(listBefore), { block: accQ.block });

  // ---- 3. the collateral really moved: buyerQ exits and withdraws
  const exitS = await expectRevert(net, "buyerP", "REG", "requestExit", []);
  c.ok("negative: the seller (buyerP) cannot requestExit (no record)", exitS.reverted, exitS.reason);
  const ex = await send(net, "buyerQ", "REG", "requestExit", []);
  const exTs = Number(BigInt((await net.block(ex.block)).timestamp));
  c.ok("buyerQ requestExit: Exiting (4), leaves getValidators() ([op1]), seat burned", Number((await reg.validators(buyerQ)).status) === 4 && sameSet(Array.from(await reg.getValidators()), [op1]) && (await nft.balanceOf(buyerQ)) === 0n, { block: ex.block });
  await net.waitForBlock(ex.block + 6);
  await waitChainTime(exTs + 61);
  const balBefore = await net.balance(buyerQ), regBefore = await net.balance(ADDR.REG);
  const w = await send(net, "buyerQ", "REG", "withdrawStake", []);
  const balAfter = await net.balance(buyerQ);
  c.ok("withdrawStake returns the full 500,000 Suren to buyerQ (net of gas); Registry balance -500,000: the collateral moved with the seat", balAfter - balBefore + w.receipt.gasUsed * w.receipt.gasPrice === S(500000) && regBefore - (await net.balance(ADDR.REG)) === S(500000), { gasUsed: w.gasUsed });
  writeResult("BH-06B", { verdict: c.verdict, summary: `paid-entrant seat (collateral 500,000): Probation seat sold and activated without acceptSeatTransfer (block ${Bact}); Active seat sold at block ${B} with set/order unchanged; new owner exited and withdrew the collateral`, checks: c.items, negatives: neg, txs: { identity: idTxs, entry: entry.hash, saleProbation: t1.hash, activation: act.hash, saleActive: t2.hash, accept: accQ.hash, exit: ex.hash, withdraw: w.hash }, activationBlock: Bact, saleBlock: B, listBefore, listAfter, ownersBefore, ownersAfter, qbftSets: { activation: qa, sale: q }, seriesActivation: serA, seriesSale: serB, gapsSale: gapsB, nCStartedAt: { before: nCStart0, after: nCStart1 }, overlayNote: "ValidatorsRegistry.probationPeriod/exitCooldown/entryWindowSeconds/recoveryPeriod overwritten in genesis storage (TEST-ONLY)" });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
