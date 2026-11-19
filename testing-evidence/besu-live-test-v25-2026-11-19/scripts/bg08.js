// BG-08 BlockRewardDistributor.distributeRewards on a live chain.
//   SUR25_BG08_NET=A : Net-A, genesis blockreward 2 Suren = approved rate -> actual == approved (control: all-ways split incl. the membership fee of BG-05)
//   SUR25_BG08_NET=S : Net-S, genesis blockreward 3 Suren > approved 2 -> actual > approved: the excess is burned at once, RewardExcessBurned emitted
// Independent accounting: per-block miners (eth_getBlockByNumber) mapped to owners, fees summed from receipts, Distributor balance equation checked BEFORE the call,
// every payout recomputed in BigInt and compared with events and balance deltas of the settling block.
const { Net, Checks, writeResult, ethers, send, expectRevert, sleep, findEvent, ifaceOf, ADDR, S, GAS_PRICE, abiOf } = require("./lib");
const KEY = process.env.SUR25_BG08_NET || "A";
const ID = KEY === "A" ? "BG-08a" : "BG-08b";
const POST_TX = process.env.SUR25_BG08_TX || ""; // post-hoc mode: the distribution tx is already mined (first run crashed after the call, see DEVIATIONS.md); only the after-call checks are run

(async () => {
  const net = new Net(KEY, "n1");
  const c = new Checks();
  const dist = net.c("DIST"), reg = net.c("REG");
  const BI = ifaceOf("DIST");
  const REWARD = BigInt(KEY === "A" ? "2000000000000000000" : "3000000000000000000");
  const APPROVED_RATE = 2n * 10n ** 18n;
  const bps = 10000n;

  // ---- negatives (eth_call level; each one also mined with status 0 -> its fee is part of the later accounting)
  const head0 = await net.head();
  const ownersAll = []; // filled below
  // block range and attribution
  let H0 = await net.head();
  let postRc = null, N = H0 - 4;
  if (POST_TX) { postRc = await net.provider.getTransactionReceipt(POST_TX); const re = findEvent(postRc, BI, "EpochRangeSettled")[0]; N = Number(re.args.toBlock); H0 = N + 4; }
  // seat transfers change ownerOfOperator; replay SeatTransferred events to attribute historic blocks
  const logs = await net.provider.getLogs({ address: ADDR.REG, fromBlock: 0, toBlock: "latest", topics: [ifaceOf("REG").getEvent("SeatTransferred").topicHash] });
  const transfers = logs.map((l) => { const p = ifaceOf("REG").parseLog(l); return { block: l.blockNumber, from: p.args.from, to: p.args.to }; });
  const opOwnerNow = {};
  const ownerAt = async (miner, blockNo) => {
    if (opOwnerNow[miner] === undefined) opOwnerNow[miner] = await reg.ownerOfOperator(miner);
    let o = opOwnerNow[miner];
    // walk transfers backwards: if the operator's current owner received the seat after blockNo, the older owner is the sender
    for (const t of transfers.slice().reverse()) if (t.block > blockNo && t.to === o) o = t.from;
    return o;
  };
  const perOwner = new Map(); let feesSum = 0n; let feesAll = 0n;
  const t0 = Date.now();
  const fees = []; // per block fee
  for (let n = 1; n <= H0; n++) {
    const b = await net.provider.send("eth_getBlockByNumber", [ethers.toQuantity(n), true]);
    let f = 0n;
    if (b.transactions.length) {
      const rcs = await net.provider.send("eth_getBlockReceipts", [ethers.toQuantity(n)]);
      for (const rc of rcs) f += BigInt(rc.gasUsed) * BigInt(rc.effectiveGasPrice);
    }
    fees.push(f); feesAll += f;
    if (n <= N) {
      feesSum += f;
      const miner = ethers.getAddress(b.miner);
      const owner = await ownerAt(miner, n);
      if (owner === ethers.ZeroAddress) throw new Error("miner without owner at block " + n + ": " + miner);
      perOwner.set(owner, (perOwner.get(owner) || 0n) + 1n);
    }
  }
  const accountingSeconds = Math.round((Date.now() - t0) / 1000);
  const owners = Array.from(perOwner.keys()).sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
  const blocksMined = owners.map((o) => perOwner.get(o));
  const totalBlocks = blocksMined.reduce((a, b) => a + b, 0n);
  c.ok(`attribution: ${N} blocks in [1,${N}] mapped to ${owners.length} owners; sum == range size`, totalBlocks === BigInt(N), Object.fromEntries(owners.map((o, i) => [o, blocksMined[i].toString()])));

  // Distributor balance equation at H0 (before any distribution): reward*H0 + all fees + pending membership fees
  let pendingBefore = 0n, balH0 = 0n;
  if (!POST_TX) { pendingBefore = await dist.pendingMembershipFees();
  balH0 = await net.balance(ADDR.DIST, ethers.toQuantity(H0));
  const eq = REWARD * BigInt(H0) + feesAll + pendingBefore;
  c.ok(`Distributor balance at block ${H0} == blockreward x ${H0} + sum of all tx fees + pending membership fees (exact, before the call)`, balH0 === eq, { balance: balH0.toString(), expected: eq.toString(), reward: REWARD.toString(), fees: feesAll.toString(), pendingMembershipFees: pendingBefore.toString() }); }

  const approved = await dist.maxRewardsForRange(1, N);
  c.ok(`maxRewardsForRange(1,${N}) == ${N} x 2 Suren (initial approved rate)`, approved === APPROVED_RATE * BigInt(N), approved);
  const reported = REWARD * BigInt(N); // actual reward of the range: blockreward x blocks
  const excess = reported > approved ? reported - approved : 0n;
  const range = { fromBlock: 1, toBlock: N };
  const reportedFees = feesSum;

  // negatives
  const neg = {};
  if (!POST_TX) {
  neg.notOracle = await expectRevert(net, "tester", "DIST", "distributeRewards", [range, owners, blocksMined, reported, reportedFees]);
  neg.gapStart = await expectRevert(net, "distOracle", "DIST", "distributeRewards", [{ fromBlock: 2, toBlock: N }, owners, blocksMined, reported, reportedFees]);
  neg.futureBlock = await expectRevert(net, "distOracle", "DIST", "distributeRewards", [{ fromBlock: 1, toBlock: H0 + 500 }, owners, blocksMined, reported, reportedFees]);
  neg.blocksExceedRange = await expectRevert(net, "distOracle", "DIST", "distributeRewards", [{ fromBlock: 1, toBlock: N - 10 }, owners, blocksMined, reported, reportedFees]);
  neg.notAscending = await expectRevert(net, "distOracle", "DIST", "distributeRewards", [range, owners.slice().reverse(), blocksMined.slice().reverse(), reported, reportedFees]);
  neg.neverActivated = await expectRevert(net, "distOracle", "DIST", "distributeRewards", [range, [net.addr("outsider"), ...owners].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1)), [net.addr("outsider"), ...owners].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1)).map((o) => (o === net.addr("outsider") ? 1n : perOwner.get(o))), reported, reportedFees]);
  neg.emptyList = await expectRevert(net, "distOracle", "DIST", "distributeRewards", [range, [], [], reported, reportedFees]);
  neg.tooMuchForBalance = await expectRevert(net, "distOracle", "DIST", "distributeRewards", [range, owners, blocksMined, balH0 * 2n, reportedFees]);
  for (const [k, v] of Object.entries(neg)) c.ok(`negative: ${k} reverts`, v.reverted, v.reason);
  c.ok("none of the negative attempts changed lastSettledBlock/epochCount", (await dist.lastSettledBlock()) === 0n && (await dist.epochCount()) === 0n);
  }

  // ---- recompute expected payouts (the negatives above were mined after H0: their fees are beyond N and beyond the range; they only add to the balance)
  const pending = POST_TX ? findEvent(postRc, BI, "RewardsDistributed")[0].args.totalFees - reportedFees : await dist.pendingMembershipFees();
  const direct = (approved <= reported ? approved : reported) * (await dist.validatorDirectShareBps()) / bps;
  const A = reported <= approved ? reported : approved;
  const foundation = A * 1500n / bps;
  const treasuryBase = A - foundation - direct;
  const feeBurn = reportedFees * 3000n / bps;
  const feeEff = reportedFees + pending;
  const feePool = feeEff - feeBurn;
  const expShare = owners.map((o, i) => ({ owner: o, reward: direct * blocksMined[i] / totalBlocks, fee: feePool * blocksMined[i] / totalBlocks }));
  const paidRewards = expShare.reduce((a, s) => a + s.reward, 0n), paidFees = expShare.reduce((a, s) => a + s.fee, 0n);
  const dust = (direct - paidRewards) + (feePool - paidFees);
  const treasuryExp = treasuryBase + dust;
  const balNow = POST_TX ? 0n : await net.balance(ADDR.DIST);
  c.ok("equation closed before sending: outflow == reported + effective fees == payouts + foundation + treasury + fee burn + excess burn", expShare.reduce((a, s) => a + s.reward + s.fee, 0n) + foundation + treasuryExp + feeBurn + excess === reported + feeEff, { reported: reported.toString(), feeEff: feeEff.toString() });
  if (!POST_TX) c.ok("Distributor balance covers reported + effective fees", balNow >= reported + feeEff, { balNow: balNow.toString(), need: (reported + feeEff).toString() });

  // snapshots before (latest)
  const snapPre = { dao: await net.balance(ADDR.DAO), treasury: await net.balance(ADDR.TREASURY), zero: await net.balance(ethers.ZeroAddress) };
  const r = POST_TX ? { receipt: postRc, hash: POST_TX, block: postRc.blockNumber, gasUsed: postRc.gasUsed.toString() } : await send(net, "distOracle", "DIST", "distributeRewards", [range, owners, blocksMined, reported, reportedFees]);
  const B = r.block;
  const rb = await net.provider.send("eth_getBlockByNumber", [ethers.toQuantity(B), true]);
  let feesB = 0n; for (const t of rb.transactions) { const rc = await net.provider.getTransactionReceipt(t.hash); feesB += rc.gasUsed * BigInt(t.gasPrice); }
  const bal = async (a, n) => net.balance(a, ethers.toQuantity(n));
  c.ok(`distributeRewards mined (block ${B}, gas ${r.gasUsed}) with ${owners.length} validators`, true, { tx: r.hash });
  const excessEv = findEvent(r.receipt, BI, "RewardExcessBurned");
  if (KEY === "S") {
    c.ok("RewardExcessBurned(epoch 1, from 1, to N, approvedRewards, excessBurned) emitted with the exact numbers", excessEv.length === 1 && excessEv[0].args.epochId === 1n && Number(excessEv[0].args.fromBlock) === 1 && Number(excessEv[0].args.toBlock) === N && excessEv[0].args.approvedRewards === approved && excessEv[0].args.excessBurned === excess, excessEv[0] && { approved: excessEv[0].args.approvedRewards.toString(), excess: excessEv[0].args.excessBurned.toString() });
    c.ok("totalExcessBurned == excess (" + ethers.formatEther(excess) + " Suren)", (await dist.totalExcessBurned()) === excess && excess > 0n);
  } else {
    c.ok("actual == approved: no RewardExcessBurned event, totalExcessBurned == 0", excessEv.length === 0 && (await dist.totalExcessBurned()) === 0n);
  }
  const rangeEv = findEvent(r.receipt, BI, "EpochRangeSettled")[0], rdEv = findEvent(r.receipt, BI, "RewardsDistributed")[0], ffEv = findEvent(r.receipt, BI, "FoundationFunded")[0], fbEv = findEvent(r.receipt, BI, "FeesBurned")[0];
  c.ok("EpochRangeSettled(1, 1, N), RewardsDistributed(epoch 1, totalRewards == APPROVED amount, totalFees, treasury incl. dust, blocks, validators)", rangeEv.args.epochId === 1n && Number(rangeEv.args.toBlock) === N && rdEv.args.totalRewards === A && rdEv.args.totalFees === reportedFees + pending && rdEv.args.treasuryAmount === treasuryExp && rdEv.args.totalBlocksMined === totalBlocks, { totalRewards: rdEv.args.totalRewards.toString(), treasury: rdEv.args.treasuryAmount.toString() });
  c.ok("FoundationFunded == 15% of the APPROVED rewards; FeesBurned == 30% of ordinary fees (membership fees exempt)", ffEv.args.amount === foundation && fbEv.args.amount === feeBurn, { foundation: ffEv.args.amount.toString(), feeBurn: fbEv.args.amount.toString() });
  const vr = findEvent(r.receipt, BI, "ValidatorRewarded");
  const ownerRows = [];
  for (let i = 0; i < owners.length; i++) {
    const ev = vr.find((e) => e.args.validator === owners[i]);
    const dB = (await bal(owners[i], B)) - (await bal(owners[i], B - 1));
    const exp = expShare[i];
    const ok = ev && ev.args.rewardShare === exp.reward && ev.args.feeShare === exp.fee && dB === exp.reward + exp.fee;
    ownerRows.push({ owner: owners[i], blocks: blocksMined[i].toString(), expectedReward: exp.reward.toString(), expectedFee: exp.fee.toString(), eventPayout: ev && ev.args.totalPayout.toString(), balanceDelta: dB.toString(), ok });
    c.ok(`validator ${owners[i].slice(0, 8)}...: ${blocksMined[i]} blocks -> event and balance delta == recomputed share (reward + fee)`, !!ok, ownerRows[i]);
  }
  c.ok("FoundationDAO balance delta == 15% of approved rewards", (await bal(ADDR.DAO, B)) - (await bal(ADDR.DAO, B - 1)) === foundation, { delta: ((await bal(ADDR.DAO, B)) - (await bal(ADDR.DAO, B - 1))).toString() });
  c.ok("ValidatorsTreasury balance delta == remainder + rounding dust", (await bal(ADDR.TREASURY, B)) - (await bal(ADDR.TREASURY, B - 1)) === treasuryExp, { delta: ((await bal(ADDR.TREASURY, B)) - (await bal(ADDR.TREASURY, B - 1))).toString(), expected: treasuryExp.toString() });
  const zeroDelta = (await bal(ethers.ZeroAddress, B)) - (await bal(ethers.ZeroAddress, B - 1));
  c.ok("address(0) balance delta == ordinary-fee burn + excess burn", zeroDelta === feeBurn + excess, { delta: zeroDelta.toString(), feeBurn: feeBurn.toString(), excess: excess.toString() });
  const distDelta = (await bal(ADDR.DIST, B)) - (await bal(ADDR.DIST, B - 1));
  c.ok("Distributor balance delta == -(reported rewards + effective fees) + blockreward + tx fees of block B (all money accounted for)", distDelta === -(reported + feeEff) + REWARD + feesB, { delta: distDelta.toString(), expected: (-(reported + feeEff) + REWARD + feesB).toString() });
  c.ok("lastSettledBlock == N, epochCount == 1, pendingMembershipFees reset to 0", (await dist.lastSettledBlock()) === BigInt(N) && (await dist.epochCount()) === 1n && (await dist.pendingMembershipFees()) === 0n);
  const ep = await dist.getEpoch(1);
  c.ok("getEpoch(1) readable and equals the event", ep.totalRewards === A && ep.totalBlocksMined === totalBlocks, { totalRewards: ep.totalRewards.toString() });
  const again = await expectRevert(net, "distOracle", "DIST", "distributeRewards", [{ fromBlock: N + 1, toBlock: N + 5 }, [owners[0]], [3n], 1n, 0n]);
  c.ok("negative: a second distribution inside 23 h reverts (too soon)", again.reverted && /too soon/.test(again.reason || ""), again.reason);
  writeResult(ID, { verdict: c.verdict, summary: `${KEY === "A" ? "control (actual == approved)" : "actual " + ethers.formatEther(reported) + " > approved " + ethers.formatEther(approved) + ": excess " + ethers.formatEther(excess) + " Suren burned"}; range [1,${N}], ${owners.length} validators, settled in block ${B}`, checks: c.items, net: KEY, range, owners: ownerRows, totals: { reported: reported.toString(), approved: approved.toString(), excess: excess.toString(), reportedFees: reportedFees.toString(), pendingMembershipFees: pending.toString(), foundation: foundation.toString(), treasury: treasuryExp.toString(), feeBurn: feeBurn.toString(), dust: dust.toString() }, tx: r.hash, settlingBlock: B, accountingSeconds, negatives: neg, postHocMode: !!POST_TX, preCallChecksLog: POST_TX ? ""+ (process.env.SUR25_BG08_PRELOG || "logs/_scriptout/bg08a.run1-pre-call-checks.out") +" (the complete first run of this script: attribution, balance equation, negatives, the call itself)" : undefined, seatTransfersReplayed: transfers });
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
