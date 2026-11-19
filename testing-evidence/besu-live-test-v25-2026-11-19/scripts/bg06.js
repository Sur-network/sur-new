// BG-06 Seat NFT transfer on a live chain (Net-A): owner7's seat #7 -> buyer (fully verified). The validator record moves, the seat is suspended until
// the buyer accepts the agreement and the Verifier records the resume. tokenURI readable.
const { Net, Checks, writeResult, ethers, send, expectRevert, sleep, findEvent, ifaceOf, sameSet, minerSeries, gapsOf, ADDR } = require("./lib");
const ev = (s) => ethers.keccak256(ethers.toUtf8Bytes(s));

(async () => {
  const net = new Net("A", "n1");
  const reg = net.c("REG"), nft = net.c("NFT");
  const c = new Checks();
  const op = (n) => net.addr(n), own = (i) => net.addr("owner" + i);
  const seller = own(7), buyer = net.addr("buyer");
  const full = Array.from(await reg.getValidators());
  c.ok("start: 7 validators, owner7 Active and owns seat 7, buyer owns no seat", full.length === 7 && (await nft.ownerOf(7)) === seller && (await nft.balanceOf(buyer)) === 0n && Number((await reg.validators(seller)).status) === 2);
  const without7 = full.filter((a) => a !== op("op7"));
  const infoBefore = await reg.validators(seller);

  const neg = {};
  neg.toUnverified = await expectRevert(net, "owner4", "NFT", "transferFrom", [own(4), net.addr("tester"), 4]);
  neg.toSeatHolder = await expectRevert(net, "owner4", "NFT", "transferFrom", [own(4), own(1), 4]);
  neg.notOwner = await expectRevert(net, "buyer", "NFT", "transferFrom", [seller, buyer, 7]);
  neg.toOperatorKey = await expectRevert(net, "owner4", "NFT", "transferFrom", [own(4), op("op4"), 4]);
  for (const [k, v] of Object.entries(neg)) c.ok(`negative: ${k} reverts`, v.reverted, v.reason);
  c.ok("the refused transfer of seat 4 did not change anything (owner4 still Active, owns seat 4)", Number((await reg.validators(own(4))).status) === 2 && (await nft.ownerOf(4)) === own(4));

  const t = await send(net, "owner7", "NFT", "transferFrom", [seller, buyer, 7]);
  const B = t.block;
  const trEv = findEvent(t.receipt, ifaceOf("NFT"), "Transfer")[0], stEv = findEvent(t.receipt, ifaceOf("REG"), "SeatTransferred")[0];
  c.ok("Transfer(owner7 -> buyer, 7) and SeatTransferred(statusAfter = SelfSuspended 6) emitted", trEv.args.to === buyer && Number(stEv.args.statusAfter) === 6, { gasUsed: t.gasUsed, block: B });
  c.ok("ownerOf(7)==buyer, seatOf(buyer)==7, balanceOf seller 0", (await nft.ownerOf(7)) === buyer && (await nft.seatOf(buyer)) === 7n && (await nft.balanceOf(seller)) === 0n);
  const vb = await reg.validators(buyer), vs = await reg.validators(seller);
  c.ok("validator record moved: buyer SelfSuspended (6), seller record deleted (None 0), periodStartedAt reset", Number(vb.status) === 6 && Number(vs.status) === 0 && vb.isPaidEntrant === infoBefore.isPaidEntrant, { buyerStatus: Number(vb.status) });
  c.ok("operator key moved with the seat: operatorOf(buyer)==op7, ownerOfOperator(op7)==buyer, seller has no operator", (await reg.operatorOf(buyer)) === op("op7") && (await reg.ownerOfOperator(op("op7"))) === buyer && (await reg.operatorOf(seller)) === ethers.ZeroAddress);
  c.ok("isFounder + everActivated + activationSeq moved to the buyer", (await reg.isFounder(buyer)) && !(await reg.isFounder(seller)) && (await reg.everActivated(buyer)) && (await reg.activationSeq(buyer)) > 0n);
  c.ok("seller treated as exited: permanentlyExited(owner7) == true, membershipEpoch +1", (await reg.permanentlyExited(seller)) === true && (await reg.membershipEpoch(seller)) === 1n);
  c.ok("seatTransferPending(buyer) == true with a 3-day informational deadline", (await reg.seatTransferPending(buyer)) && Number(await reg.seatAcceptDeadline(buyer)) - Number(BigInt((await net.block(B)).timestamp)) === 3 * 86400);
  c.ok("op7 left getValidators() at once (n=6); owner list has no seller and no buyer", sameSet(Array.from(await reg.getValidators()), without7) && !(await reg.getActiveOwners()).includes(buyer) && !(await reg.getActiveOwners()).includes(seller));
  await net.waitForBlock(B + 16);
  const q = {}; for (const n of [B - 1, B]) q[n] = (await net.qbftValidators(n)).map(ethers.getAddress);
  const ser = await minerSeries(net, B - 3, B + 16);
  c.ok("QBFT: op7 in the set at B-1, out at B; op7 never mines afterwards; no halt", q[B - 1].includes(op("op7")) && !q[B].includes(op("op7")) && !ser.filter((x) => x.block > B).some((x) => x.miner === op("op7")) && gapsOf(ser).every((g) => g <= 4), { gaps: gapsOf(ser) });
  c.ok("tokenURI(7) readable", (await nft.tokenURI(7)).endsWith("/7"), await nft.tokenURI(7));

  const n1 = await expectRevert(net, "buyer", "REG", "requestResume", []);
  c.ok("negative: requestResume before accepting the agreement reverts", n1.reverted && /accept the seat transfer/.test(n1.reason || ""), n1.reason);
  const n2 = await expectRevert(net, "verifier", "REG", "recordResume", [buyer, ev("x")]);
  c.ok("negative: recordResume before request/accept reverts", n2.reverted, n2.reason);
  const n3 = await expectRevert(net, "verifier", "REG", "recordActivation", [buyer, ev("x")]);
  c.ok("negative: recordActivation cannot be used (not in Probation)", n3.reverted, n3.reason);
  const n4 = await expectRevert(net, "outsider", "REG", "acceptSeatTransfer", []);
  c.ok("negative: acceptSeatTransfer by someone without a pending transfer reverts", n4.reverted, n4.reason);
  const ac = await send(net, "buyer", "REG", "acceptSeatTransfer", []);
  c.ok("acceptSeatTransfer: pending cleared, SeatTransferAccepted emitted; still not in the set", !(await reg.seatTransferPending(buyer)) && findEvent(ac.receipt, ifaceOf("REG"), "SeatTransferAccepted").length === 1 && (await reg.getValidators()).length === 6);
  const rq = await send(net, "buyer", "REG", "requestResume", []);
  const rr = await send(net, "verifier", "REG", "recordResume", [buyer, ev("node n7 health check after seat transfer")]);
  const B2 = rr.block;
  c.ok("recordResume: buyer Active (2) again, op7 back in getValidators() (n=7), owner list has buyer", Number((await reg.validators(buyer)).status) === 2 && sameSet(Array.from(await reg.getValidators()), full) && (await reg.getActiveOwners()).includes(buyer), { resumeBlock: B2 });
  await net.waitForBlock(B2 + 20);
  const ser2 = await minerSeries(net, B2 - 2, B2 + 20);
  const first = ser2.find((x) => x.block > B2 && x.miner === op("op7"));
  c.ok("op7 (the same node n7, never restarted) mines again for the buyer; gaps <= 4 s", !!first && gapsOf(ser2).every((g) => g <= 4), { firstBlockByOp7: first && first.block });
  const again = await expectRevert(net, "owner7", "NFT", "transferFrom", [seller, buyer, 7]);
  c.ok("negative: seller can no longer transfer (not owner)", again.reverted, again.reason);
  writeResult("BG-06", { verdict: c.verdict, summary: `seat 7 moved owner7 -> buyer at block ${B}; suspended; accepted + resumed at block ${B2}; op7 mines again from ${first && first.block}`, checks: c.items, negatives: neg, txs: { transfer: t.hash, accept: ac.hash, requestResume: rq.hash, recordResume: rr.hash }, qbftSets: q, seriesAfterTransfer: ser, seriesAfterResume: ser2 });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
