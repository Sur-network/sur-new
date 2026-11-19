// BH-06 part A: seat NFT transfer of an ACTIVE seat on a live chain (Net-A, n=7), new rule of commit e1a5f1f: the seat STAYS Active, the buyer takes the same
// place in the active set with the same operator key, the node never leaves the QBFT set; acceptSeatTransfer is only a record.
// Seller owner6 (founder, collateral 0, node n6 keeps running) -> buyer. (Paid-entrant collateral and the Probation seat are in part B, Net-T.)
const { Net, Checks, writeResult, ethers, send, expectRevert, sleep, findEvent, ifaceOf, sameSet, minerSeries, gapsOf, ADDR, makeManyFullyVerified } = require("./lib");
const { execSync } = require("child_process");
const ev = (s) => ethers.keccak256(ethers.toUtf8Bytes(s));
const startedAt = (c) => execSync(`docker inspect -f "{{.State.StartedAt}}" ${c}`).toString().trim();

(async () => {
  const net = new Net("A", "n1");
  const reg = net.c("REG"), nft = net.c("NFT");
  const c = new Checks();
  const op = (n) => net.addr(n), own = (i) => net.addr("owner" + i);
  const seller = own(6), buyer = net.addr("buyer");
  const R = ifaceOf("REG");

  // identity for the buyer
  const idTxs = await makeManyFullyVerified(net, ["buyer"]);
  c.ok("buyer fully verified; outsider and tester are not", (await net.c("IDENTITY").isFullyVerified(buyer)) && !(await net.c("IDENTITY").isFullyVerified(net.addr("outsider"))) && !(await net.c("IDENTITY").isFullyVerified(net.addr("tester"))));

  const listBefore = Array.from(await reg.getValidators());
  const ownersBefore = Array.from(await reg.getActiveOwners());
  const idx = ownersBefore.indexOf(seller);
  c.ok("start: 7 validators, owner6 Active at index " + idx + " of the active set, owns seat 6; buyer owns no seat", listBefore.length === 7 && idx >= 0 && listBefore[idx] === op("op6") && (await nft.ownerOf(6)) === seller && (await nft.balanceOf(buyer)) === 0n && Number((await reg.validators(seller)).status) === 2, { listBefore, ownersBefore });
  const infoBefore = await reg.validators(seller);
  const actSeqBefore = await reg.activationSeq(seller);
  const N0 = await reg.statusNonce();
  const n6Start0 = startedAt("sur25b-a-n6");

  // a Registry parameter proposal created BEFORE the transfer (owner1; needs 4 of 7; stays open)
  const pp1 = await send(net, "owner1", "REG", "proposeParameterChange", [4, 1000]); // ParamKey.SlashBps = 4
  const pp1Id = Number(findEvent(pp1.receipt, R, "ParameterChangeProposed")[0].args.id);

  // negatives (refused in the Registry hook, nothing changes)
  const neg = {};
  neg.toUnverified = await expectRevert(net, "owner4", "NFT", "transferFrom", [own(4), net.addr("tester"), 4]);
  neg.toSeatHolder = await expectRevert(net, "owner4", "NFT", "transferFrom", [own(4), own(1), 4]);
  neg.notOwner = await expectRevert(net, "buyer", "NFT", "transferFrom", [seller, buyer, 6]);
  neg.toOperatorKey = await expectRevert(net, "owner4", "NFT", "transferFrom", [own(4), op("op4"), 4]);
  for (const [k, v] of Object.entries(neg)) c.ok(`negative: ${k} reverts`, v.reverted, v.reason);
  c.ok("the refused transfers of seat 4 did not change anything (owner4 still Active, owns seat 4, list unchanged)", Number((await reg.validators(own(4))).status) === 2 && (await nft.ownerOf(4)) === own(4) && JSON.stringify(Array.from(await reg.getValidators())) === JSON.stringify(listBefore));

  // ---------------- the transfer
  await net.waitBlocks(2);
  const t = await send(net, "owner6", "NFT", "transferFrom", [seller, buyer, 6]);
  const B = t.block;
  const trEv = findEvent(t.receipt, ifaceOf("NFT"), "Transfer")[0], stEv = findEvent(t.receipt, R, "SeatTransferred")[0];
  c.ok("Transfer(owner6 -> buyer, 6) and SeatTransferred(statusAfter = Active 2) emitted", trEv.args.to === buyer && Number(stEv.args.statusAfter) === 2, { gasUsed: t.gasUsed, block: B });
  const N1 = await reg.statusNonce();
  c.ok("ownerOf(6)==buyer, seatOf(buyer)==6, seller balance 0", (await nft.ownerOf(6)) === buyer && (await nft.seatOf(buyer)) === 6n && (await nft.balanceOf(seller)) === 0n);
  const vb = await reg.validators(buyer), vs = await reg.validators(seller);
  c.ok("validators(buyer): Active (2) with the seller's collateral/period data (lockedStake equal, isPaidEntrant equal); seller record deleted (None 0)", Number(vb.status) === 2 && vb.lockedStake === infoBefore.lockedStake && vb.isPaidEntrant === infoBefore.isPaidEntrant && vb.periodStartedAt === infoBefore.periodStartedAt && Number(vs.status) === 0, { buyerStatus: Number(vb.status), lockedStake: vb.lockedStake });
  c.ok("operator key moved with the seat: operatorOf(buyer)==op6, ownerOfOperator(op6)==buyer, seller has no operator", (await reg.operatorOf(buyer)) === op("op6") && (await reg.ownerOfOperator(op("op6"))) === buyer && (await reg.operatorOf(seller)) === ethers.ZeroAddress);
  c.ok("isFounder + everActivated + activationSeq moved to the buyer", (await reg.isFounder(buyer)) && !(await reg.isFounder(seller)) && (await reg.everActivated(buyer)) && (await reg.activationSeq(buyer)) === actSeqBefore);
  c.ok("seller treated as exited: permanentlyExited(owner6) true, membershipEpoch 1", (await reg.permanentlyExited(seller)) === true && (await reg.membershipEpoch(seller)) === 1n);
  const listAfter = Array.from(await reg.getValidators()), ownersAfter = Array.from(await reg.getActiveOwners());
  c.ok("getValidators() is IDENTICAL (same 7 operator keys, same order): op6 at the same position " + idx, JSON.stringify(listAfter) === JSON.stringify(listBefore) && listAfter[idx] === op("op6"), { listBefore, listAfter });
  c.ok("getActiveOwners(): the buyer takes the seller's index, all other owners unchanged", ownersAfter[idx] === buyer && ownersAfter.filter((_, i) => i !== idx).every((a, i) => a === ownersBefore.filter((_, j) => j !== idx)[i]) && ownersAfter.length === 7 && !ownersAfter.includes(seller), { ownersBefore, ownersAfter });
  c.ok("isValidator(buyer) true, isValidator(seller) false", (await reg.isValidator(buyer)) === true && (await reg.isValidator(seller)) === false);
  c.ok("seatTransferPending(buyer) == true with a 3-day informational deadline", (await reg.seatTransferPending(buyer)) === true && Number(await reg.seatAcceptDeadline(buyer)) - Number(BigInt((await net.block(B)).timestamp)) === 3 * 86400);
  c.ok("statusNonce +2 (seller checkpoint false, buyer checkpoint true)", N1 === N0 + 2n,{ N0, N1 });
  c.ok("buyer is a NEW voter: wasActiveAt(buyer, N0) false, wasActiveAt(buyer, N1) true; seller: wasActiveAt(seller, N0) true, wasActiveAt(seller, N1) false", !(await reg.wasActiveAt(buyer, N0)) && (await reg.wasActiveAt(buyer, N1)) && (await reg.wasActiveAt(seller, N0)) && !(await reg.wasActiveAt(seller, N1)), { N0, N1 });
  // voting eligibility on real proposals
  const vOld = await expectRevert(net, "buyer", "REG", "voteParameterChange", [pp1Id]);
  c.ok("buyer cannot vote on the Registry proposal created BEFORE the transfer ('not Active when this proposal was created')", vOld.reverted && /not Active when this proposal was created/.test(vOld.reason || ""), vOld.reason);
  const pp2 = await send(net, "owner1", "REG", "proposeParameterChange", [4, 1001]);
  const pp2Id = Number(findEvent(pp2.receipt, R, "ParameterChangeProposed")[0].args.id);
  const vNew = await send(net, "buyer", "REG", "voteParameterChange", [pp2Id]);
  const pr2 = await reg.paramProposals(pp2Id);
  c.ok("buyer CAN vote on a proposal created after the transfer (2 votes of " + pr2.requiredVotes + ")", Number(pr2.votes) === 2 && !pr2.executed, { tx: vNew.hash });
  const vSeller = await expectRevert(net, "owner6", "REG", "voteParameterChange", [pp2Id]);
  c.ok("the seller can no longer vote (not an active validator)", vSeller.reverted, vSeller.reason);

  await net.waitForBlock(B + 20);
  const q = {}; for (const n of [B - 1, B, B + 1]) q[n] = (await net.qbftValidators(n)).map(ethers.getAddress);
  const ser = await minerSeries(net, B - 10, B + 20);
  const gaps = gapsOf(ser);
  c.ok("QBFT set at B-1, B and B+1 is the same 7 operator keys (op6 never leaves)", sameSet(q[B - 1], listBefore) && sameSet(q[B], listBefore) && sameSet(q[B + 1], listBefore), q);
  c.ok("QBFT set at the latest block == getValidators() (7 operator keys, op6 included)", sameSet((await net.qbftValidators("latest")).map(ethers.getAddress), listBefore));
  const firstOp6After = ser.find((s) => s.block > B && s.miner === op("op6"));
  const op6Count = ser.filter((s) => s.block > B && s.miner === op("op6")).length;
  c.ok("op6 keeps mining after the transfer (first block " + (firstOp6After && firstOp6After.block) + ", " + op6Count + " blocks in B+1..B+20)", !!firstOp6After && op6Count >= 1, { op6Count });
  c.ok("no gap above the block period (2 s) in blocks B-10..B+20 (31 blocks, 30 gaps): max gap " + Math.max(...gaps) + " s", Math.max(...gaps) <= 2, gaps);
  const n6Start1 = startedAt("sur25b-a-n6");
  c.ok("node n6 container was NOT restarted (same StartedAt)", n6Start0 === n6Start1, { n6Start0, n6Start1 });
  c.ok("tokenURI(6) readable", (await nft.tokenURI(6)).endsWith("/6"), await nft.tokenURI(6));

  // the buyer needs no Verifier step: resume / activation paths are not needed and not available
  const n1 = await expectRevert(net, "buyer", "REG", "requestResume", []);
  c.ok("negative: requestResume reverts (the seat is not suspended)", n1.reverted && /not self-suspended/.test(n1.reason || ""), n1.reason);
  const n3 = await expectRevert(net, "verifier", "REG", "recordActivation", [buyer, ev("x")]);
  c.ok("negative: recordActivation reverts (the seat is not in Probation)", n3.reverted, n3.reason);
  const n4 = await expectRevert(net, "outsider", "REG", "acceptSeatTransfer", []);
  c.ok("negative: acceptSeatTransfer by someone without a pending transfer reverts", n4.reverted, n4.reason);
  // acceptance is only a record
  const ac = await send(net, "buyer", "REG", "acceptSeatTransfer", []);
  c.ok("acceptSeatTransfer: seatTransferPending false, SeatTransferAccepted emitted", !(await reg.seatTransferPending(buyer)) && findEvent(ac.receipt, R, "SeatTransferAccepted").length === 1, { block: ac.block });
  c.ok("acceptance changed nothing else: getValidators() still identical, buyer still Active", JSON.stringify(Array.from(await reg.getValidators())) === JSON.stringify(listBefore) && Number((await reg.validators(buyer)).status) === 2);
  const ac2 = await expectRevert(net, "buyer", "REG", "acceptSeatTransfer", []);
  c.ok("negative: second acceptSeatTransfer reverts", ac2.reverted, ac2.reason);
  const again = await expectRevert(net, "owner6", "NFT", "transferFrom", [seller, buyer, 6]);
  c.ok("negative: seller can no longer transfer (not owner)", again.reverted, again.reason);
  await net.waitBlocks(6);
  const ser2 = await minerSeries(net, (await net.head()) - 10, await net.head());
  c.ok("after the acceptance blocks keep coming at 2 s", Math.max(...gapsOf(ser2)) <= 2, gapsOf(ser2));
  writeResult("BH-06A", { verdict: c.verdict, summary: `Active seat 6 moved owner6 -> buyer at block ${B}; set and order unchanged, op6 mines on, buyer is a new voter, acceptance is a record`, checks: c.items, negatives: neg, txs: { transfer: t.hash, accept: ac.hash, identity: idTxs, pp1: pp1.hash, pp2: pp2.hash, buyerVote: vNew.hash }, indexInActiveSet: idx, listBefore, listAfter, ownersBefore, ownersAfter, statusNonce: { N0: N0.toString(), N1: N1.toString() }, qbftSets: q, seriesAroundTransfer: ser, gaps, n6StartedAt: { before: n6Start0, after: n6Start1 } });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
