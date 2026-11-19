// BG-05 Paying entry on a live chain (Net-A): identity via IdentityRegistry + identityOracle, requestMembership(operator) with 500,000 + 4% fee,
// collateral stays in the Registry, fee reaches the Distributor (pendingMembershipFees), seat NFT minted. Probation->activation: only the "too early" refusal here
// (7-day probation cannot elapse on Besu); the full cycle is BG-05b on Net-T (genesis overlay of probationPeriod).
const { Net, Checks, writeResult, ethers, send, expectRevert, S, findEvent, ifaceOf, ADDR, makeManyFullyVerified, GAS_PRICE } = require("./lib");
const ev = (s) => ethers.keccak256(ethers.toUtf8Bytes(s));

(async () => {
  const net = new Net("A", "n1");
  const c = new Checks();
  const reg = net.c("REG"), id = net.c("IDENTITY"), nft = net.c("NFT"), dist = net.c("DIST");
  const cand = net.addr("cand"), opC = net.addr("opC"), buyer = net.addr("buyer");

  // ---- identity
  c.ok("before: cand not fully verified", !(await id.isFullyVerified(cand)));
  const idTxs = await makeManyFullyVerified(net, ["cand", "buyer"]);
  const vs = await id.getVerificationStatus(cand);
  c.ok("cand registered + phone/telegram/bale/email/kyc verified", Array.from(vs).every((x) => x === true) && (await id.isFullyVerified(cand)), Array.from(vs));
  c.ok("buyer fully verified too", await id.isFullyVerified(buyer));
  c.ok("outsider still not fully verified", !(await id.isFullyVerified(net.addr("outsider"))));
  const noOracle = await expectRevert(net, "outsider", "IDENTITY", "setPhoneVerified", [cand, false]);
  c.ok("negative: only the identity oracle sets flags", noOracle.reverted, noOracle.reason);

  const collateral = await reg.currentEntryThreshold(), fee = await reg.currentMembershipFee();
  c.ok("currentEntryThreshold == 500,000 Suren, fee (4%) == 20,000 Suren", collateral === S(500000) && fee === S(20000), { collateral, fee });
  const value = collateral + fee;

  // ---- negatives
  const neg = {};
  neg.unverified = await expectRevert(net, "outsider", "REG", "requestMembership", [net.addr("op3b")], { value });
  neg.wrongAmount = await expectRevert(net, "cand", "REG", "requestMembership", [opC], { value: collateral });
  neg.operatorOfOther = await expectRevert(net, "cand", "REG", "requestMembership", [net.addr("op1")], { value });
  neg.zeroOperator = await expectRevert(net, "cand", "REG", "requestMembership", [ethers.ZeroAddress], { value });
  for (const [k, v] of Object.entries(neg)) c.ok(`negative: ${k} reverts`, v.reverted, v.reason);

  // ---- positive
  const nowHead = await net.head();
  const snap = { regBal: await net.balance(ADDR.REG), distPending: await dist.pendingMembershipFees(), candBal: await net.balance(cand), minted: await nft.totalMinted(), paid: await reg.paidValidatorCount() };
  const r = await send(net, "cand", "REG", "requestMembership", [opC], { value });
  const B = r.block;
  const rcIface = ifaceOf("REG");
  const mr = findEvent(r.receipt, rcIface, "MembershipRequested")[0];
  const oset = findEvent(r.receipt, rcIface, "OperatorSet")[0];
  const fe = findEvent(r.receipt, ifaceOf("DIST"), "MembershipFeeReceived")[0];
  const tr = findEvent(r.receipt, ifaceOf("NFT"), "Transfer")[0];
  c.ok("events: MembershipRequested(collateral 500k, fee 20k), OperatorSet(cand, opC), MembershipFeeReceived, ERC-721 Transfer(0 -> cand)", !!mr && mr.args.collateralAmount === collateral && mr.args.feeAmount === fee && oset.args.operator === opC && fe.args.amount === fee && tr.args.from === ethers.ZeroAddress && tr.args.to === cand, { gasUsed: r.gasUsed, block: B });
  const regBalDelta = (await net.balance(ADDR.REG)) - snap.regBal;
  c.ok("collateral stays in the Registry: Registry balance +500,000 Suren exactly", regBalDelta === collateral, regBalDelta);
  const pendingDelta = (await dist.pendingMembershipFees()) - snap.distPending;
  c.ok("Distributor.pendingMembershipFees +20,000 Suren", pendingDelta === fee, pendingDelta);
  // Distributor balance at B vs B-1 (within the node's state window): fee + block reward + fees of the txs in block B
  const blk = await net.provider.send("eth_getBlockByNumber", [ethers.toQuantity(B), true]);
  let feesInB = 0n; for (const t of blk.transactions) { const rc = await net.provider.getTransactionReceipt(t.hash); feesInB += rc.gasUsed * BigInt(t.gasPrice); }
  const dB = await net.balance(ADDR.DIST, ethers.toQuantity(B)), dB1 = await net.balance(ADDR.DIST, ethers.toQuantity(B - 1));
  const reward = 2n * 10n ** 18n;
  c.ok("Distributor balance rose by fee + blockreward(2) + tx fees of that block (exact)", dB - dB1 === fee + reward + feesInB, { delta: (dB - dB1).toString(), expected: (fee + reward + feesInB).toString(), txsInBlock: blk.transactions.length });
  const candDelta = snap.candBal - (await net.balance(cand));
  c.ok("cand paid exactly 520,000 Suren + gas", candDelta === value + r.receipt.gasUsed * r.receipt.gasPrice, candDelta);
  const v = await reg.validators(cand);
  c.ok("validators[cand]: Probation (1), lockedStake 500,000, isPaidEntrant, periodStartedAt == block timestamp", Number(v.status) === 1 && v.lockedStake === collateral && v.isPaidEntrant === true && Number(v.periodStartedAt) === Number(BigInt(blk.timestamp)), { periodStartedAt: Number(v.periodStartedAt) });
  c.ok("paidValidatorCount +1", (await reg.paidValidatorCount()) - snap.paid === 1n);
  c.ok("operatorOf(cand)==opC, ownerOfOperator(opC)==cand, opC not in getValidators()", (await reg.operatorOf(cand)) === opC && (await reg.ownerOfOperator(opC)) === cand && !(await reg.getValidators()).includes(opC));
  const seat = await nft.seatOf(cand);
  c.ok("seat NFT minted: totalMinted +1, ownerOf(seat)==cand, balanceOf==1", (await nft.totalMinted()) - snap.minted === 1n && (await nft.ownerOf(seat)) === cand && (await nft.balanceOf(cand)) === 1n, { seat: seat.toString() });
  c.ok("tokenURI(seat) readable on chain", (await nft.tokenURI(seat)).endsWith("/" + seat), await nft.tokenURI(seat));
  const again = await expectRevert(net, "cand", "REG", "requestMembership", [opC], { value });
  c.ok("negative: second requestMembership by the same address reverts (already registered)", again.reverted, again.reason);
  // rate limit: buyer (verified, funded 600k by BG-09) tries a second paid entry in the same 7-day window
  const buyerBal = await net.balance(buyer);
  c.ok("buyer holds >= 520,000 Suren (funded by the DAO Spend of BG-09)", buyerBal >= value, buyerBal);
  const rate = await expectRevert(net, "buyer", "REG", "requestMembership", [net.addr("op3b")], { value });
  c.ok("negative: second paid entry in the same window reverts (maxEntriesPerWindow=1, 7 days)", rate.reverted && /rate limit/.test(rate.reason || ""), rate.reason);
  const early = await expectRevert(net, "verifier", "REG", "recordActivation", [cand, ev("too early")]);
  c.ok("negative: recordActivation before the 7-day probation elapsed reverts (probation not elapsed)", early.reverted && /probation/.test(early.reason || ""), early.reason);
  const op0 = await expectRevert(net, "outsider", "REG", "recordActivation", [cand, ev("x")]);
  c.ok("negative: recordActivation from a non-verifier reverts", op0.reverted, op0.reason);
  const ownerCall = await expectRevert(net, "cand", "REG", "setOperator", [opC]);
  c.ok("negative: setOperator to the same operator reverts", ownerCall.reverted, ownerCall.reason);

  writeResult("BG-05", { verdict: c.verdict, summary: `cand entered on Net-A at block ${B}: collateral 500,000 in Registry, 20,000 fee to Distributor, seat #${seat} minted; Probation; activation refused before 7 days`, checks: c.items, entryTx: r.hash, entryBlock: B, gasUsed: r.gasUsed, identityTxs: idTxs, negatives: neg, notRunHere: "probation -> activation after the probation period: BG-05b on Net-T (probationPeriod overlaid to 120 s)" });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
